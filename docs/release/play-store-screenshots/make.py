"""Google Play screenshots, second set: the captioned variant and the overview sheets.

    python3 docs/release/play-store-screenshots/make.py

The clean screens in ru/, en/, ar/, tr/ are emulator captures (see README.md); this script only
reads them. It writes <language>/captions/ (the first three screens with a short caption) and
overview-<language>.jpg plus overview.jpg (all four languages on one sheet).
Needs the Python package `playwright` and an installed Chrome.
"""

import base64
from pathlib import Path

from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
LANGUAGES = ("ru", "en", "ar", "tr")
CAPTIONS = {
    "ru": ("Коран, намаз и знания — в одном приложении", "Мусхаф с цветным таджвидом", "99 имён Аллаха со значением"),
    "en": ("Quran, prayer and learning in one app", "Mushaf with colour-coded tajweed", "99 Names of Allah with meanings"),
    "ar": ("القرآن والصلاة والعلم في تطبيق واحد", "مصحف بألوان التجويد", "أسماء الله الحسنى ومعانيها"),
    "tr": ("Kur’an, namaz ve ilim tek uygulamada", "Tecvid renkli Mushaf", "Esmâü’l-Hüsnâ ve anlamları"),
}
TITLES = {"ru": "Русский", "en": "English", "ar": "العربية", "tr": "Türkçe"}
FONT = '-apple-system, "SF Pro Display", "SF Arabic", "Geeza Pro", "Helvetica Neue", Arial, sans-serif'


def screens(language: str) -> list[Path]:
    return sorted((HERE / language).glob("[1-8]-*.png"))


def data_uri(path: Path) -> str:
    return f"data:image/png;base64,{base64.b64encode(path.read_bytes()).decode()}"


def captioned(language: str, screen: Path, caption: str) -> str:
    direction = "rtl" if language == "ar" else "ltr"
    return f"""<html><body style="margin:0"><div style="width:1080px;height:1920px;overflow:hidden;position:relative;
background:linear-gradient(180deg,#f7f1e6,#e9dfcb);font-family:{FONT}">
<div dir="{direction}" style="position:absolute;top:0;left:70px;right:70px;height:330px;display:flex;align-items:center;
justify-content:center;text-align:center;font-size:66px;line-height:1.18;font-weight:800;color:#065f46">{caption}</div>
<img src="{data_uri(screen)}" style="position:absolute;top:330px;left:93px;width:894px;border-radius:44px;
box-shadow:0 24px 70px rgba(6,60,46,.28)"></div></body></html>"""


def overview(rows: list[tuple[str, list[Path]]]) -> str:
    body = ""
    for title, files in rows:
        cells = "".join(
            f'<div style="width:270px"><img src="{data_uri(f)}" style="width:270px;border-radius:14px;'
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
    with sync_playwright() as pw:
        browser = pw.chromium.launch(channel="chrome")
        page = browser.new_page()
        page.set_viewport_size({"width": 1080, "height": 1920})
        for language in LANGUAGES:
            folder = HERE / language / "captions"
            folder.mkdir(exist_ok=True)
            for screen, caption in zip(screens(language), CAPTIONS[language]):
                page.set_content(captioned(language, screen, caption))
                page.wait_for_timeout(300)
                page.screenshot(path=str(folder / screen.name))
        page.set_viewport_size({"width": 2400, "height": 1200})
        sheets = {language: [(TITLES[language], screens(language))] for language in LANGUAGES}
        sheets[""] = [(TITLES[language], screens(language)) for language in LANGUAGES]
        sheets["captions"] = [
            (TITLES[language], sorted((HERE / language / "captions").glob("*.png"))) for language in LANGUAGES
        ]
        for name, rows in sheets.items():
            page.set_content(overview(rows))
            page.wait_for_timeout(500)
            target = HERE / ("overview.jpg" if not name else f"overview-{name}.jpg")
            page.locator("#sheet").screenshot(path=str(target), type="jpeg", quality=85)
        browser.close()


if __name__ == "__main__":
    main()
