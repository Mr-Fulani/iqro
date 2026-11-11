"""Store graphics for Google Play: screenshots 1080x1920 and the banner 1024x500, on four languages.

    python3 docs/release/store-graphics/make.py

mushaf, audio and prayer in src/ are screenshots of the test app on a phone, status bar cut off.
home, courses and more come from the app's screenshot tests (run from clients/iqro_mobile):
  flutter test test/features/home_screenshots_test.dart --plain-name "store:" --dart-define=SCREENSHOT_DIR=…
  flutter test test/features/course_screenshots_test.dart --plain-name "catalog with the site covers" --dart-define=SCREENSHOT_DIR=…
"""

import base64
from pathlib import Path

from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
SEAL = HERE.parents[2] / "services/web/public/iqro-wax-seal.png"

CAPTIONS = {
    "ru": (
        "Время намаза и чтение на сегодня",
        "Мусхаф с цветами таджвида",
        "Известные чтецы и весь Коран подряд",
        "Время намаза по вашему городу",
        "Курсы: намаз и таджвид по шагам",
        "Всё для ежедневной практики",
    ),
    "en": (
        "Prayer times and today’s reading",
        "Mushaf with tajweed colours",
        "Renowned reciters and the whole Quran",
        "Prayer times for your city",
        "Courses: prayer and tajweed step by step",
        "Everything for daily practice",
    ),
    "ar": (
        "مواقيت الصلاة وورد اليوم",
        "مصحف بألوان التجويد",
        "قرّاء مشهورون والقرآن كاملًا",
        "مواقيت الصلاة لمدينتك",
        "دورات: الصلاة والتجويد خطوة بخطوة",
        "كل ما تحتاجه لعبادتك اليومية",
    ),
    "tr": (
        "Namaz vakitleri ve günün okuması",
        "Tecvid renkli Mushaf",
        "Tanınmış kâriler ve Kur’an’ın tamamı",
        "Şehrinize göre namaz vakitleri",
        "Kurslar: adım adım namaz ve tecvid",
        "Günlük ibadet için her şey",
    ),
}
TAGLINES = {
    "ru": "Коран, аудио и намаз",
    "en": "Quran, audio and prayer",
    "ar": "القرآن والتلاوة والصلاة",
    "tr": "Kur’an, ses ve namaz",
}
SCREENS = ("home", "mushaf", "audio", "prayer", "courses", "more")
FONT = '-apple-system, "SF Pro Display", "SF Arabic", "Geeza Pro", "Helvetica Neue", Arial, sans-serif'


def data_uri(path: Path) -> str:
    kind = "jpeg" if path.suffix == ".jpg" else "png"
    return f"data:image/{kind};base64,{base64.b64encode(path.read_bytes()).decode()}"


def screenshot(language: str, screen: str, caption: str) -> str:
    direction = "rtl" if language == "ar" else "ltr"
    return f"""<html><body style="margin:0"><div dir="{direction}" style="width:1080px;height:1920px;overflow:hidden;position:relative;
background:linear-gradient(180deg,#f7f1e6,#e9dfcb);font-family:{FONT}">
<div style="position:absolute;top:96px;left:80px;right:80px;text-align:center;font-size:68px;line-height:1.18;font-weight:800;color:#065f46">{caption}</div>
<div style="position:absolute;top:380px;left:120px;width:840px;height:1820px;border-radius:64px;background:#10201b;
box-shadow:0 30px 80px rgba(6,60,46,.28)"><img src="{data_uri(HERE / 'src' / f'{screen}-{language}.jpg')}"
style="position:absolute;top:18px;left:18px;width:804px;border-radius:48px"></div></div></body></html>"""


def banner(language: str) -> str:
    direction = "rtl" if language == "ar" else "ltr"
    return f"""<html><body style="margin:0"><div dir="{direction}" style="width:1024px;height:500px;overflow:hidden;display:flex;align-items:center;
justify-content:center;gap:56px;background:radial-gradient(ellipse at 50% 40%,#0d6a51,#04302a);font-family:{FONT}">
<img src="{data_uri(SEAL)}" style="width:250px;height:250px;filter:drop-shadow(0 14px 30px rgba(0,0,0,.35))">
<div><div style="font-size:124px;font-weight:800;letter-spacing:4px;color:#f6e3b4;line-height:1" dir="ltr">IQRO</div>
<div style="margin-top:22px;font-size:44px;font-weight:500;color:#f3ece0">{TAGLINES[language]}</div></div></div></body></html>"""


def main() -> None:
    with sync_playwright() as pw:
        browser = pw.chromium.launch(channel="chrome")
        page = browser.new_page()
        for language, captions in CAPTIONS.items():
            folder = HERE / language
            folder.mkdir(exist_ok=True)
            page.set_viewport_size({"width": 1080, "height": 1920})
            for number, (screen, caption) in enumerate(zip(SCREENS, captions), start=1):
                page.set_content(screenshot(language, screen, caption))
                page.wait_for_timeout(300)
                page.screenshot(path=str(folder / f"{number}-{screen}.png"))
            page.set_viewport_size({"width": 1024, "height": 500})
            page.set_content(banner(language))
            page.wait_for_timeout(300)
            page.screenshot(path=str(folder / "banner-1024x500.png"))
        browser.close()


if __name__ == "__main__":
    main()
