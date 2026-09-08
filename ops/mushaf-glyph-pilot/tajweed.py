"""QF resource 19 -> IQRO colour pages, never a claimed print facsimile.

The downloaded /colrv1/ URL currently contains COLR v0 in all 604 fonts. Read
the actual table, preserve ordered CPAL layers, reject unknown paint formats.
Only headings use the pinned QPC Unicode decoration font; ayahs and basmala
use QF19's original page glyphs and palette 0 without substitutions.
"""
import argparse
from collections import defaultdict
import hashlib
import io
import json
from pathlib import Path
import subprocess
from types import SimpleNamespace

from fontTools.pens.boundsPen import BoundsPen
from fontTools.ttLib import TTFont
import uharfbuzz as hb

from build_full import write_once
import kfgqpc
import prepare as p

VERSION = "iqro-qcf-v4-tajweed-1"
EDITION = "qcf-v4-tajweed-hafs"


class ColorFont:
    def __init__(self, path, page):
        self.tt = TTFont(path)
        try:
            p.require(self.tt["name"].getDebugName(1) == f"QCF4{page:03d}_COLOR", "Wrong font identity")
            p.require(self.tt["COLR"].version == 0, "Unverified COLR version")
            p.require(not any(t in self.tt for t in ("SVG ", "CBDT", "sbix", "fvar")), "Unsupported font")
            self.layers = self.tt["COLR"].ColorLayers
            self.palette = self.tt["CPAL"].palettes[0]
            self.glyphs = self.tt.getGlyphSet()
            self.cmap = self.tt.getBestCmap()
            self.order = self.tt.getGlyphOrder()
            self.tt.flavor = None
            sfnt = io.BytesIO()
            self.tt.save(sfnt, reorderTables=False)
            self.sfnt = sfnt.getvalue()
            self.font = hb.Font(hb.Face(self.sfnt))
            hb.ot_font_set_funcs(self.font)
            self.font.scale = (self.tt["head"].unitsPerEm,) * 2
            p.require(all(self.font.get_nominal_glyph(c) == self.tt.getGlyphID(g) for c, g in self.cmap.items()), "Cmap differs")
        except BaseException:
            self.tt.close()
            raise

    def close(self):
        self.tt.close()

    def shape(self, text):
        p.require(text and all(ord(c) in self.cmap for c in text), "Missing colour glyph")
        buf = hb.Buffer()
        buf.add_str(text)
        buf.guess_segment_properties()
        buf.direction = "rtl"
        hb.shape(self.font, buf, {"kern": True, "liga": True})
        x, y, pieces, boxes, colors = 0, 0, [], [], []
        for info, pos in zip(buf.glyph_infos, buf.glyph_positions, strict=True):
            p.require(info.codepoint != 0, "Missing shaped glyph")
            name = self.order[info.codepoint]
            if name == self.cmap.get(32) and " " in text:
                x += pos.x_advance
                y += pos.y_advance
                continue
            # A glyph without a COLR record uses its own foreground outline,
            # per OpenType. Never substitute another font or glyph.
            layers = self.layers.get(name, [SimpleNamespace(name=name, colorID=0xFFFF)])
            for layer in layers:
                pen, bounds = p.OutlinePen(self.glyphs), BoundsPen(self.glyphs)
                self.glyphs[layer.name].draw(pen)
                self.glyphs[layer.name].draw(bounds)
                if bounds.bounds is None and not pen.commands:
                    continue  # Empty source layers paint nothing (e.g. p208/uniFC42).
                p.require(bounds.bounds and pen.commands, "Inconsistent colour layer")
                color = (0, 0, 0, 255) if layer.colorID == 0xFFFF else self.palette[layer.colorID]
                # CPAL Color exposes red/green/blue, although its tuple is BGRA.
                rgba = (0, 0, 0, 255) if layer.colorID == 0xFFFF else (color.red, color.green, color.blue, color.alpha)
                dx, dy = x + pos.x_offset, y + pos.y_offset
                box = bounds.bounds
                pieces.append((pen.commands, dx, dy))
                colors.append(rgba)
                boxes.append((box[0] + dx, box[1] + dy, box[2] + dx, box[3] + dy))
            x += pos.x_advance
            y += pos.y_advance
        p.require(pieces and boxes, "Entire word has no visible source outline")
        shape = p.Shaped(pieces, p.union(boxes))
        shape.colors = colors
        return shape


def audit(data):
    # Reuse canonical/mapping validation on an in-memory audit view only. Never
    # mutate the source snapshot or render synthetic verse text/numbers.
    refs = [(s["number"], n) for s in data["surahs"] for n in range(1, s["ayah_count"] + 1)]
    pages = []
    for page in data["pages"]:
        words = []
        for word in page["words"]:
            terminal = word["char_type_name"] == "end"
            if word["id"] == 1950117:
                p.require((word["verse_id"], word["text"], word["page_number"]) == (188, "ﳍ", 27), "Unverified provider marker exception")
                terminal = True  # Provider labels the terminal 2:181 glyph as 'word'.
            words.append({**word, "text": str(refs[word["verse_id"] - 1][1]) if terminal else "glyph"})
        pages.append({**page, "words": words})
    return kfgqpc.audit({**data, "pages": pages})


def compose(data, page, font, heading, basmala, refs, lock):
    number = page["page_number"]
    groups = defaultdict(list)
    for word in page["words"]:
        surah, ayah = refs[word["verse_id"]]
        groups[word["line_number"]].append((font.shape(word["text"]), {**word, "surah": surah, "ayah": ayah}))
    rows = {}
    for line, items in groups.items():
        last = items[-1][1]
        closes = last["char_type_name"] == "end" and last["ayah"] == data["surahs"][last["surah"] - 1]["ayah_count"]
        rows[line] = ("ayah", number in (1, 2) or closes, items)
    for word in page["words"]:
        surah, ayah = refs[word["verse_id"]]
        if ayah != 1 or word["position_in_verse"] != 1:
            continue
        first = word["line_number"]
        line = first - (1 if surah in (1, 9) else 2)
        p.require(line >= 0 and line not in rows, "No heading slot")
        rows[line] = ("surah_name", True, [(heading.shape(w), None) for w in data["surahs"][surah - 1]["name_ar"].split()])
        if surah not in (1, 9):
            p.require(first - 1 not in rows, "No basmala slot")
            rows[first - 1] = ("basmallah", True, [(shape, None) for shape in basmala])
    lines = list(range(min(rows), max(rows) + 1))
    row_height = p.ROW * 15 / max(15, len(lines))
    typography = p.PageTypography.fit([items for kind, _, items in rows.values() if kind == "ayah"], row_height)
    top = p.TOP + (15 - len(lines)) * row_height / 2 if number in (1, 2) else p.TOP
    glyphs, regions, metrics = [], [], []
    for line in lines:
        if line not in rows:
            top += row_height
            continue
        kind, centered, items = rows[line]
        scale, baseline = typography.scale, top + typography.baseline_offset
        if kind != "ayah":
            box = p.union([shape.bounds for shape, _ in items])
            scale = min(row_height * .6 / (box[3] - box[1]), p.WIDTH * .66 / sum(s.width for s, _ in items))
            baseline = top + row_height / 2 + (box[3] + box[1]) * scale / 2
        widths = [shape.width * scale for shape, _ in items]
        gap, right = typography.horizontal(widths, centered=centered)
        metrics.append({"line": line, "kind": kind, "top": top, "height": row_height, "baseline": baseline, "scale": scale, "word_gap": gap, "centered": centered})
        boxes = defaultdict(list)
        for (shape, word), width in zip(items, widths, strict=True):
            left = right - width
            box = [left, baseline - shape.bounds[3] * scale, right, baseline - shape.bounds[1] * scale]
            glyph = {"line": line, "kind": kind, "word_id": word["id"] if word else None,
                "verse": f"{word['surah']}:{word['ayah']}" if word else None,
                "bounds": [round(v, 4) for v in box], "commands": p.place(shape, left, baseline, scale)}
            if hasattr(shape, "colors"):
                glyph["layers"] = [{"rgba": color, "commands": p.place(p.Shaped([piece], shape.bounds), left, baseline, scale)}
                    for piece, color in zip(shape.pieces, shape.colors, strict=True)]
            glyphs.append(glyph)
            if word:
                boxes[(word["surah"], word["ayah"])].append(box)
            right = left - gap
        for (surah, ayah), values in boxes.items():
            left, _, right, _ = p.union(values)
            regions.append({"surah": surah, "ayah": ayah, "line": line,
                "rect": [round(v, 4) for v in (left, top, right, top + row_height)]})
        top += row_height
    result = {"schema_version": 1, "status": "draft", "renderer": VERSION, "edition": EDITION,
        "source_lock_sha256": hashlib.sha256(p.canonical(lock)).hexdigest(), "page": number,
        "width": p.WIDTH, "height": p.HEIGHT, "glyphs": glyphs, "ayah_regions": regions, "lines": metrics}
    p.validate_artifact(result)
    return result


def svg(page):
    parts = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{p.WIDTH}" height="{p.HEIGHT}" viewBox="0 0 {p.WIDTH} {p.HEIGHT}">', '<rect width="100%" height="100%" fill="#fffcf6"/>']
    for glyph in page["glyphs"]:
        for layer in glyph.get("layers", [{"rgba": (36, 30, 23, 255), "commands": glyph["commands"]}]):
            r, g, b, alpha = layer["rgba"]
            path = " ".join(c[0] + " ".join(str(v) for v in c[1:]) for c in layer["commands"])
            parts.append(f'<path fill="#{r:02x}{g:02x}{b:02x}" fill-opacity="{alpha / 255}" d="{path}"/>')
    return "\n".join(parts + ["</svg>"])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", required=True, type=Path)
    parser.add_argument("--decoration-source", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--pages")
    args = parser.parse_args()
    runtime = p.verify_runtime()
    lock = json.loads(Path(__file__).with_name("tajweed.source.lock.json").read_bytes())
    p.require(p.digest(args.source_dir / "snapshot.json") == lock["snapshot_sha256"], "Snapshot changed")
    for name, spec in lock["files"].items():
        p.require(Path(name).name == name and p.digest(args.source_dir / name) == spec["sha256"], "Font changed")
    data = json.loads((args.source_dir / "snapshot.json").read_bytes())
    p.require(data["source_id"] == 19 and data["source_checksum_sha256"] == lock["source_checksum_sha256"], "Wrong source")
    refs = audit(data)
    _, decoration_lock = kfgqpc.load_source(args.decoration_source)
    source = {"kind": "quran-foundation", "edition": EDITION, **lock, "decoration_font_sha256": decoration_lock["font_sha256"]}
    identity = {"schema_version": 1, "edition": EDITION, "source": source, "renderer": VERSION,
        "runtime": runtime, "widths": [720, 1440, 2160], "renderer_code_sha256": hashlib.sha256(b"".join(Path(__file__).with_name(n).read_bytes() for n in ("prepare.py", "kfgqpc.py", "tajweed.py", "raster.cjs", "render_page.cjs"))).hexdigest()}
    args.output_dir.mkdir(exist_ok=True)
    write_once(args.output_dir / "build-identity.json", p.canonical(identity))
    selected = list(map(int, args.pages.split(","))) if args.pages else list(range(1, 605))
    p.require(selected == sorted(set(selected)) and all(1 <= n <= 604 for n in selected), "Invalid sample")
    heading = p.SourceFont(args.decoration_source / kfgqpc.FONT, "KFGQPC HAFS Uthmanic Script")
    first = ColorFont(args.source_dir / "p1.woff2", 1)
    entries = []
    try:
        basmala = [first.shape(w["text"]) for w in data["pages"][0]["words"] if w["verse_id"] == 1 and w["char_type_name"] == "word"]
        for number in selected:
            font = ColorFont(args.source_dir / f"p{number}.woff2", number)
            try:
                page = compose(data, data["pages"][number - 1], font, heading, basmala, refs, lock)
            finally:
                font.close()
            vector = svg(page).encode()
            stem = f"page-{number:03d}"
            receipt = args.output_dir / f"{stem}.bundle.json"
            if receipt.exists():
                entry = json.loads(receipt.read_bytes())
                p.require(entry["source_svg_sha256"] == hashlib.sha256(vector).hexdigest(), "Resume rendering differs")
                for spec in [entry["geometry"], *entry["assets"]]:
                    p.require(Path(spec["path"]).name == spec["path"] and p.digest(args.output_dir / spec["path"]) == spec["sha256"], "Resume bytes differ")
            else:
                raster = subprocess.run(["node", str(Path(__file__).with_name("render_page.cjs")), str(args.output_dir), stem], input=vector, capture_output=True, check=True, timeout=120)
                geometry = p.canonical(p.mobile_geometry(page))
                write_once(args.output_dir / f"{stem}.mobile.json", geometry)
                entry = {"page": number, "source_svg_sha256": hashlib.sha256(vector).hexdigest(),
                    "geometry": {"path": f"{stem}.mobile.json", "bytes": len(geometry), "sha256": hashlib.sha256(geometry).hexdigest()}, "assets": json.loads(raster.stdout)}
                write_once(receipt, p.canonical(entry))
            entries.append(entry)
            if len(entries) % 10 == 0 or args.pages:
                print(f"Tajweed pages: {len(entries)}/{len(selected)}", flush=True)
    finally:
        heading.close()
        first.close()
    if not args.pages:
        manifest = {**identity, "status": "prepared", "publication_scope": "staging", "canonical_edition": "madani-hafs",
            "version": "qcf-v4-tajweed-iqro-20260908-v1", "page_count": 604, "pages": entries}
        raw = p.canonical(manifest)
        write_once(args.output_dir / "manifest.json", raw)
        write_once(args.output_dir / "manifest.sha256", f"{hashlib.sha256(raw).hexdigest()}  manifest.json\n".encode())
    print(f"Verified {len(selected)} colour pages / {len(refs)} canonical references", flush=True)


if __name__ == "__main__":
    main()
