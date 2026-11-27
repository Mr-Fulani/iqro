"""App Store screenshots: the clean screens from CI, the captioned variant and the overview sheets.

    python3 docs/release/app-store-screenshots/make.py --from <artifact folder>
    python3 docs/release/app-store-screenshots/make.py

The clean screens come from the "App Store screenshots" workflow (artifact
app-store-screenshots-iphone-6.9, one folder per language with 01-home.png …
08-mushaf-night.png). --from copies them here as <language>/<n>-<name>.jpg:
1320×2868, no transparency, as App Store Connect takes for the iPhone 6.9″ slot.
Then, as for Google Play (../play-store-screenshots/make.py), it writes
<language>/captions/ — the first three screens with a short caption — and
overview-<language>.jpg plus overview.jpg. Needs Pillow, the Python package
`playwright` and an installed Chrome.
"""

import argparse
import base64
import re
import sys
from pathlib import Path

from PIL import Image
from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
LANGUAGES = ("ru", "en", "ar", "tr")
WIDTH, HEIGHT = 1320, 2868
# The same captions as the Google Play set.
CAPTIONS = {
    "ru": ("Коран, намаз и знания — в одном приложении", "Мусхаф с цветным таджвидом", "99 имён Аллаха со значением"),
    "en": ("Quran, prayer and learning in one app", "Mushaf with colour-coded tajweed", "99 Names of Allah with meanings"),
    "ar": ("القرآن والصلاة والعلم في تطبيق واحد", "مصحف بألوان التجويد", "أسماء الله الحسنى ومعانيها"),
    "tr": ("Kur’an, namaz ve ilim tek uygulamada", "Tecvid renkli Mushaf", "Esmâü’l-Hüsnâ ve anlamları"),
}
TITLES = {"ru": "Русский", "en": "English", "ar": "العربية", "tr": "Türkçe"}
FONT = '-apple-system, "SF Pro Display", "SF Arabic", "Geeza Pro", "Helvetica Neue", Arial, sans-serif'


def import_screens(artifact: Path) -> None:
    for language in LANGUAGES:
        source = artifact / language
        shots = sorted(source.glob("[0-9][0-9]-*.png"))
        shots = [shot for shot in shots if "-timeout-" not in shot.name]
        if len(shots) != 8:
            sys.exit(f"{source}: expected 8 screens, found {len(shots)}")
        target = HERE / language
        target.mkdir(exist_ok=True)
        for old in target.glob("[1-8]-*.jpg"):
            old.unlink()
        for shot in shots:
            number, name = re.match(r"0?(\d+)-(.+)\.png", shot.name).groups()
            image = Image.open(shot)
            if image.size != (WIDTH, HEIGHT):
                sys.exit(f"{shot}: {image.size[0]}×{image.size[1]}, not {WIDTH}×{HEIGHT}")
            image.convert("RGB").save(target / f"{number}-{name}.jpg", quality=90, optimize=True)


def screens(language: str) -> list[Path]:
    return sorted((HERE / language).glob("[1-8]-*.jpg"))


def data_uri(path: Path) -> str:
    return f"data:image/jpeg;base64,{base64.b64encode(path.read_bytes()).decode()}"


def captioned(language: str, screen: Path, caption: str) -> str:
    direction = "rtl" if language == "ar" else "ltr"
    return f"""<html><body style="margin:0"><div style="width:{WIDTH}px;height:{HEIGHT}px;overflow:hidden;position:relative;
background:linear-gradient(180deg,#f7f1e6,#e9dfcb);font-family:{FONT}">
<div dir="{direction}" style="position:absolute;top:0;left:90px;right:90px;height:470px;display:flex;align-items:center;
justify-content:center;text-align:center;font-size:84px;line-height:1.16;font-weight:800;color:#065f46">{caption}</div>
<img src="{data_uri(screen)}" style="position:absolute;top:470px;left:114px;width:1092px;border-radius:64px;
box-shadow:0 30px 84px rgba(6,60,46,.28)"></div></body></html>"""


def overview(rows: list[tuple[str, list[Path]]]) -> str:
    body = ""
    for title, files in rows:
        cells = "".join(
            f'<div style="width:250px"><img src="{data_uri(f)}" style="width:250px;border-radius:16px;'
            f'box-shadow:0 4px 14px rgba(0,0,0,.18)"><div style="margin-top:8px;font-size:20px;color:#3d4a45;'
            f'text-align:center">{number}</div></div>'
            for number, f in enumerate(files, start=1)
        )
        body += (
            f'<div style="font-size:34px;font-weight:700;color:#065f46;margin:26px 0 14px">{title}</div>'
            f'<div style="display:flex;gap:18px">{cells}</div>'
        )
    return f"""<html><body style="margin:0"><div id="sheet" style="display:inline-block;padding:10px 36px 36px;
background:#f3ede1;font-family:{FONT}">{body}</div></body></html>"""


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--from", dest="artifact", type=Path, help="the downloaded CI artifact folder")
    args = parser.parse_args()
    if args.artifact:
        import_screens(args.artifact)
    with sync_playwright() as pw:
        browser = pw.chromium.launch(channel="chrome")
        page = browser.new_page()
        page.set_viewport_size({"width": WIDTH, "height": HEIGHT})
        for language in LANGUAGES:
            folder = HERE / language / "captions"
            folder.mkdir(exist_ok=True)
            for screen, caption in zip(screens(language), CAPTIONS[language]):
                page.set_content(captioned(language, screen, caption))
                page.wait_for_timeout(300)
                page.screenshot(path=str(folder / screen.name), type="jpeg", quality=90)
        page.set_viewport_size({"width": 2400, "height": 1200})
        sheets = {language: [(TITLES[language], screens(language))] for language in LANGUAGES}
        sheets[""] = [(TITLES[language], screens(language)) for language in LANGUAGES]
        sheets["captions"] = [
            (TITLES[language], sorted((HERE / language / "captions").glob("*.jpg"))) for language in LANGUAGES
        ]
        for name, rows in sheets.items():
            page.set_content(overview(rows))
            page.wait_for_timeout(500)
            target = HERE / ("overview.jpg" if not name else f"overview-{name}.jpg")
            page.locator("#sheet").screenshot(path=str(target), type="jpeg", quality=85)
        browser.close()


if __name__ == "__main__":
    main()
