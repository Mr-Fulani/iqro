"""Render IQRO how-to cards from docs/guides/<feature>/guide.json.

Each card is a 1080x1350 PNG (4:5, fits Telegram/Instagram posts): a title,
one or two screens (phone or desktop) with numbered taps, boxes and swipes,
and the numbered steps under them. README.md is written from the same file.

    python3 docs/guides/_tools/render.py docs/guides/dua-display-options
    python3 docs/guides/_tools/render.py --all

Mark coordinates are percentages of the screenshot (x, y, w, h in 0..100).
"""

import base64
import html
import io
import json
import mimetypes
import sys
from pathlib import Path

from PIL import Image
from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[1]
SEAL = ROOT.parents[1] / "services/web/public/iqro-wax-seal-128.webp"
W, H = 1080, 1350

PLATFORM = {
    "app": "Приложение",
    "site-phone": "Сайт · телефон",
    "site-desktop": "Сайт · компьютер",
    "site": "Сайт",
    "both": "Сайт и приложение",
}

CSS = """
* { box-sizing: border-box; margin: 0; }
body { width: %(W)dpx; height: %(H)dpx; overflow: hidden;
  font-family: -apple-system, "SF Pro Text", "Helvetica Neue", Arial, sans-serif;
  background: linear-gradient(180deg, #f7f1e6 0%%, #f3ece0 100%%); color: #0f172a; }
.card { position: absolute; inset: 0; display: flex; flex-direction: column; padding: 44px 56px 40px; }
.top { display: flex; align-items: center; gap: 14px; }
.top img { width: 46px; height: 46px; }
.brand { font-weight: 800; font-size: 26px; letter-spacing: .5px; color: #065f46; }
.brand small { font-weight: 500; color: #64748b; font-size: 22px; margin-left: 8px; letter-spacing: 0; }
.chip { margin-left: auto; padding: 8px 18px; border-radius: 999px; font-size: 21px; font-weight: 600;
  background: #ecfdf5; color: #065f46; border: 2px solid #a7f3d0; }
.page { font-size: 21px; color: #94a3b8; margin-left: 14px; font-weight: 600; }
h1 { font-size: 46px; line-height: 1.12; font-weight: 800; margin-top: 26px; letter-spacing: -.4px; }
.lead { font-size: 26px; line-height: 1.3; color: #475569; margin-top: 10px; }
.stage { flex: 1; display: flex; align-items: center; justify-content: center; gap: 34px; min-height: 0; margin: 20px 0 18px; }
.shot { position: relative; flex: none; }
.shot img.scr { display: block; width: 100%%; height: 100%%; object-fit: cover; object-position: top; }
.phone { border-radius: 38px; padding: 10px; background: #1e293b; box-shadow: 0 18px 44px rgba(15,23,42,.22); }
.phone .inner { position: relative; width: 100%%; height: 100%%; border-radius: 29px; overflow: hidden; background: #fff; }
.desk { border-radius: 14px; background: #fff; box-shadow: 0 18px 44px rgba(15,23,42,.2); overflow: hidden; border: 1px solid #cbd5e1; }
.desk .bar { height: 30px; background: #e2e8f0; display: flex; align-items: center; gap: 7px; padding: 0 12px; }
.desk .bar i { width: 11px; height: 11px; border-radius: 50%%; background: #cbd5e1; display: block; }
.desk .bar span { margin-left: 14px; font-size: 14px; color: #64748b; background: #fff; border-radius: 6px; padding: 2px 12px; }
.desk .inner { position: relative; overflow: hidden; }
.label { position: absolute; top: -40px; left: 0; right: 0; text-align: center; font-size: 20px; font-weight: 700; color: #475569; }
.ov { position: absolute; inset: 0; pointer-events: none; }
.num { position: absolute; width: 46px; height: 46px; border-radius: 50%%; background: #047857; color: #fff;
  font-weight: 800; font-size: 26px; display: flex; align-items: center; justify-content: center;
  border: 3px solid #fff; box-shadow: 0 4px 12px rgba(4,120,87,.45); transform: translate(-50%%, -50%%); z-index: 3; }
.tap { position: absolute; width: 74px; height: 74px; border-radius: 50%%; transform: translate(-50%%, -50%%);
  background: rgba(16,185,129,.28); border: 4px solid #10b981; box-shadow: 0 0 0 10px rgba(16,185,129,.18); z-index: 2; }
.box { position: absolute; border: 4px solid #d97706; border-radius: 14px; box-shadow: 0 0 0 4px rgba(255,255,255,.7); z-index: 2; }
.tip { position: absolute; width: 0; height: 0; z-index: 2; transform: translate(-50%%, -50%%) rotate(var(--a));
  border-left: 22px solid transparent; border-right: 22px solid transparent; border-bottom: 34px solid #10b981; }
svg.sw { position: absolute; inset: 0; width: 100%%; height: 100%%; z-index: 2; overflow: visible; }
.steps { display: flex; flex-direction: column; gap: 12px; }
.step { display: flex; gap: 16px; align-items: flex-start; font-size: 27px; line-height: 1.28; }
.step b { flex: none; width: 42px; height: 42px; border-radius: 50%%; background: #047857; color: #fff;
  display: flex; align-items: center; justify-content: center; font-size: 23px; margin-top: -3px; }
.note { margin-top: 14px; padding: 14px 18px; border-radius: 14px; background: #fffbeb; border: 2px solid #fde68a;
  color: #92400e; font-size: 23px; line-height: 1.3; }
"""


def data_uri(path):
    mime = mimetypes.guess_type(str(path))[0] or "image/png"
    return f"data:{mime};base64,{base64.b64encode(path.read_bytes()).decode()}"


BADGE = {  # badge offset from the mark's anchor point, in px
    "left": (-64, 0), "right": (64, 0), "top": (0, -62), "bottom": (0, 62),
    "tl": (-6, -6), "tr": (6, -6), "bl": (-6, 6), "br": (6, 6),
}


def mark_html(m):
    kind = m.get("type", "tap")
    out = []
    if kind == "tap":
        out.append(f'<div class="tap" style="left:{m["x"]}%;top:{m["y"]}%"></div>')
        ax, ay, side = m["x"], m["y"], m.get("badge", "left")
    elif kind == "box":
        x, y, w, h = m["x"], m["y"], m["w"], m["h"]
        out.append(f'<div class="box" style="left:{x}%;top:{y}%;width:{w}%;height:{h}%"></div>')
        side = m.get("badge", "tl")
        ax = {"l": x, "r": x + w}.get(side[-1], x + w / 2) if len(side) == 2 else {"left": x, "right": x + w}.get(side, x + w / 2)
        ay = {"t": y, "b": y + h}[side[0]] if len(side) == 2 else {"top": y, "bottom": y + h}.get(side, y + h / 2)
    elif kind == "swipe":
        x1, y1, x2, y2 = m["x1"], m["y1"], m["x2"], m["y2"]
        out.append(
            '<svg class="sw" viewBox="0 0 100 100" preserveAspectRatio="none">'
            f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="#10b981" stroke-width="7" '
            'vector-effect="non-scaling-stroke" stroke-linecap="round" stroke-dasharray="1 16"/></svg>'
        )
        out.append(f'<div class="tap" style="left:{x1}%;top:{y1}%"></div>')
        out.append(f'<div class="tip" style="left:{x2}%;top:{y2}%;--a:{m.get("angle", 0)}deg"></div>')
        ax, ay, side = x1, y1, m.get("badge", "left")
    else:
        raise ValueError(kind)
    if m.get("n") is not None:
        dx, dy = BADGE[side]
        out.append(
            f'<div class="num" style="left:calc({ax}% + {dx}px);top:calc({ay}% + {dy}px)">{m["n"]}</div>'
        )
    return "".join(out)


def shot_html(folder, s, max_h, max_w):
    src = (folder / s["src"]).resolve()
    with Image.open(src) as im:
        iw, ih = im.size
    top, bottom = s.get("crop", (0, 100))  # visible part of the screenshot, % of its height
    left, right = s.get("cropx", (0, 100))  # and of its width
    vis_w, vis_h = iw * (right - left) / 100, ih * (bottom - top) / 100
    kind = s.get("frame", "phone")
    pad_w, pad_h = (20, 20) if kind == "phone" else (0, 30)
    scale = min((max_h - pad_h) / vis_h, (max_w - pad_w) / vis_w)
    if not s.get("exact"):
        # a width-bound shot shows more of the screenshot instead of leaving the stage empty
        room = (max_h - pad_h) / scale / ih * 100
        bottom = min(100, top + room)
        top = max(0, min(top, bottom - room))
        vis_h = ih * (bottom - top) / 100
    w, h = round(vis_w * scale), round(vis_h * scale)
    full_w, full_h = round(iw * scale), round(ih * scale)
    marks = "".join(mark_html(m) for m in s.get("marks", []))
    # marks are in % of the full screenshot, so the overlay covers the full image
    img = (
        f'<div style="position:absolute;left:{-round(full_w * left / 100)}px;top:{-round(full_h * top / 100)}px;'
        f'width:{full_w}px;height:{full_h}px"><img class="scr" src="{data_uri(src)}"><div class="ov">{marks}</div></div>'
    )
    label = f'<div class="label">{html.escape(s["label"])}</div>' if s.get("label") else ""
    if kind == "phone":
        return (
            f'<div class="shot phone" style="width:{w + 20}px;height:{h + 20}px">{label}'
            f'<div class="inner">{img}</div></div>'
        )
    url = html.escape(s.get("url", "iqro.forum"))
    return (
        f'<div class="shot desk" style="width:{w}px;height:{h + 30}px">{label}'
        f'<div class="bar"><i></i><i></i><i></i><span>{url}</span></div>'
        f'<div class="inner" style="width:{w}px;height:{h}px">{img}</div></div>'
    )


def card_html(folder, guide, card, index, total, stage_h=None):
    """Without stage_h the stage is empty: the first pass only measures how tall it may be."""
    shots = card["shots"]
    gap = 34
    max_w = (W - 112 - gap * (len(shots) - 1)) / len(shots)
    labels = any(s.get("label") for s in shots)
    stage = "".join(shot_html(folder, s, stage_h - (40 if labels else 0), max_w) for s in shots) if stage_h else ""
    steps = "".join(
        f'<div class="step"><b>{i + 1}</b><span>{html.escape(t)}</span></div>'
        for i, t in enumerate(card.get("steps", []))
    )
    note = f'<div class="note">{html.escape(card["note"])}</div>' if card.get("note") else ""
    lead = f'<p class="lead">{html.escape(card["lead"])}</p>' if card.get("lead") else ""
    platform = PLATFORM.get(card.get("platform", guide.get("platform", "both")), card.get("platform"))
    page = f'<span class="page">{index}/{total}</span>' if total > 1 else ""
    pad_top = "padding-top:40px;" if labels else ""
    return f"""<!doctype html><html lang="ru"><head><meta charset="utf-8"><style>{CSS % {"W": W, "H": H}}</style></head>
<body><div class="card">
<div class="top"><img src="{data_uri(SEAL)}"><div class="brand">IQRO<small>{html.escape(guide["title"])}</small></div>
<div class="chip">{html.escape(platform)}</div>{page}</div>
<h1>{html.escape(card["title"])}</h1>{lead}
<div class="stage" style="{pad_top}">{stage}</div>
<div class="steps">{steps}</div>{note}
</div></body></html>"""


def readme(guide):
    lines = [f"# {guide['title']}", "", guide["about"], ""]
    if guide.get("where"):
        lines += [f"**Где найти:** {guide['where']}", ""]
    if guide.get("difference"):
        lines += [f"**Сайт и приложение:** {guide['difference']}", ""]
    for card in guide["cards"]:
        lines += [f"## {card['title']}", "", f"![{card['title']}]({card['file']})", "", card["caption"], ""]
    if guide.get("sources"):
        lines += ["---", "", f"Основа снимков: {guide['sources']}", ""]
    return "\n".join(lines)


def render(folder, page):
    guide = json.loads((folder / "guide.json").read_text())
    cards = guide["cards"]
    for i, card in enumerate(cards, 1):
        page.set_content(card_html(folder, guide, card, i, len(cards)), wait_until="load")
        stage_h = page.eval_on_selector(".stage", "e => e.clientHeight")
        page.set_content(card_html(folder, guide, card, i, len(cards), stage_h), wait_until="load")
        png = page.screenshot(type="png")
        # 256-colour palette keeps cards around a third of the plain PNG size
        im = Image.open(io.BytesIO(png)).convert("RGB").quantize(256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
        im.save(folder / card["file"], optimize=True)
        print(folder / card["file"])
    (folder / "README.md").write_text(readme(guide))


def main(argv):
    if argv == ["--all"]:
        folders = sorted(p.parent for p in ROOT.glob("*/guide.json"))
    else:
        folders = [Path(a).resolve() for a in argv]
    with sync_playwright() as pw:
        browser = pw.chromium.launch(channel="chrome")  # installed Chrome; no Playwright browser download
        page = browser.new_page(viewport={"width": W, "height": H})
        for folder in folders:
            render(folder, page)
        browser.close()


if __name__ == "__main__":
    main(sys.argv[1:])
