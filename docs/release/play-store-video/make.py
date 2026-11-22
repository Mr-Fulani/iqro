"""The IQRO promo video: cuts the screen recordings to the voice-over.

    python3 docs/release/play-store-video/make.py <voice.mp3>

Reads the recordings from ~/Downloads/iqro-video-src (see README.md), writes to ~/Downloads/iqro-video:
iqro-reels-9x16.mp4 (1080x1920) and iqro-google-play-16x9.mp4 (1920x1080, the phone screen in the
middle of a calm background). Needs ffmpeg, the Python package `playwright` and an installed Chrome.
"""

import base64
import subprocess
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
SEAL = HERE.parents[2] / "services/web/public/iqro-wax-seal.png"
SRC = Path.home() / "Downloads/iqro-video-src"
OUT = Path.home() / "Downloads/iqro-video"
FONT = '-apple-system, "SF Pro Display", "Helvetica Neue", Arial, sans-serif'
LEAD = 0.3  # silence before the first word
END = 57.5
# (recording, from, to, the second of the film where the next scene begins). The voice sets the
# scene lengths: each cut falls in the pause before the next phrase.
SCENES = (
    ("n1-open-read-aloud", 0.5, 7.4, 3.45),  # 1 «…а проверить некому?»
    ("4a-recitation-follow", 5.5, 15.5, 8.42),  # 2 «…слово за словом»
    ("n3-stop-hint-return", 10.5, 22.5, 17.33),  # 3 «…остановится и подскажет…»
    ("n4-plan-progress", 1.0, 11.4, 22.50),  # 4 «…каждый день…»
    ("n5a-plan-set-goal", 2.0, 9.5, 26.22),  # 5 «Задайте дневную цель…»
    ("n5b-prayer-reminders", 2.0, 10.4, 30.40),  # 5 «…напомнит о времени намаза…»
    ("1-home", 0.5, 5.5, 33.74),  # 5 «Пять-десять минут…»
    ("2a-mushaf-day", 1.5, 7.0, 36.50),  # 6 «…Мусхаф с цветным таджвидом…»
    ("3-reader-tafsir-reciter", 9.0, 17.4, 39.29),  # 6 «…перевод, тафсир и любимые чтецы»
    ("5-names-of-allah", 1.5, 9.7, 43.40),  # 7а «Девяносто девять имён…»
    ("6a-prayer-qibla", 1.5, 7.5, 46.37),  # 7а «Время намаза и кибла…»
    ("6c-salah-course", 11.0, 21.2, 49.80),  # 7б «…Курс намаза…»
    ("n7b-courses", 1.0, 7.4, 52.97),  # 7б «…и курс таджвида…»
)


def run(*args: str) -> None:
    subprocess.run(["ffmpeg", "-v", "error", "-y", *args], check=True)


def stills() -> None:
    seal = f"data:image/png;base64,{base64.b64encode(SEAL.read_bytes()).decode()}"
    back = "background:radial-gradient(ellipse at 50% 40%,#0d6a51,#04302a)"
    logo = f"""<div style="width:{{w}}px;height:{{h}}px;{back};display:flex;flex-direction:column;align-items:center;
justify-content:center;font-family:{FONT}"><img src="{seal}" style="width:{{s}}px;filter:drop-shadow(0 14px 30px rgba(0,0,0,.35))">
<div style="margin-top:40px;font-size:150px;font-weight:800;letter-spacing:6px;color:#f6e3b4;line-height:1">IQRO</div>
<div style="margin-top:36px;font-size:54px;font-weight:500;color:#f3ece0">Скачайте в Google Play</div></div>"""
    pages = {
        "logo-9x16.png": (1080, 1920, logo.format(w=1080, h=1920, s=420)),
        "logo-16x9.png": (1920, 1080, logo.format(w=1920, h=1080, s=300)),
        "back-16x9.png": (1920, 1080, f'<div style="width:1920px;height:1080px;{back}"></div>'),
    }
    with sync_playwright() as pw:
        browser = pw.chromium.launch(channel="chrome")
        page = browser.new_page()
        for name, (width, height, html) in pages.items():
            page.set_viewport_size({"width": width, "height": height})
            page.set_content(f'<html><body style="margin:0">{html}</body></html>')
            page.wait_for_timeout(300)
            page.screenshot(path=str(OUT / name))
        browser.close()


def main() -> None:
    voice = sys.argv[1]
    OUT.mkdir(exist_ok=True)
    stills()
    inputs: list[str] = []
    filters: list[str] = []
    begin = 0.0
    for index, (name, start, stop, end) in enumerate(SCENES):
        length = end - begin
        speed = (stop - start) / length
        inputs += ["-i", str(SRC / f"{name}.mp4")]
        filters.append(
            f"[{index}:v]trim={start}:{stop},setpts=(PTS-STARTPTS)/{speed:.4f},fps=30,scale=1080:1920,"
            f"tpad=stop_mode=clone:stop_duration=1,trim=0:{length:.3f},setpts=PTS-STARTPTS,format=yuv420p[v{index}]"
        )
        begin = end
    count = len(SCENES)
    inputs += ["-loop", "1", "-t", f"{END - begin:.3f}", "-i", str(OUT / "logo-9x16.png")]
    filters.append(f"[{count}:v]fps=30,format=yuv420p,setpts=PTS-STARTPTS[v{count}]")
    chain = "".join(f"[v{index}]" for index in range(count + 1))
    filters.append(f"{chain}concat=n={count + 1}:v=1:a=0[v]")
    sound = f"adelay={int(LEAD * 1000)}:all=1,loudnorm=I=-16:TP=-1.5:LRA=11,apad,atrim=0:{END},aresample=48000"
    encode = ["-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p", "-r", "30"]
    audio = ["-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", "-t", str(END)]
    vertical = OUT / "iqro-reels-9x16.mp4"
    run(
        *inputs, "-i", voice,
        "-filter_complex", ";".join(filters) + f";[{count + 1}:a]{sound}[a]",
        "-map", "[v]", "-map", "[a]", *encode, *audio, str(vertical),
    )  # fmt: skip
    # 16:9: the phone screen with a thin light edge in the middle; the last scene is the wide logo.
    run(
        "-loop", "1", "-t", str(END), "-i", str(OUT / "back-16x9.png"), "-i", str(vertical),
        "-loop", "1", "-t", str(END), "-i", str(OUT / "logo-16x9.png"),
        "-filter_complex",
        "[1:v]scale=558:992,pad=566:1000:4:4:color=0xf6e3b4[p];[0:v][p]overlay=(W-w)/2:(H-h)/2[b];"
        f"[b][2:v]overlay=enable='gte(t,{begin})',format=yuv420p[v]",
        "-map", "[v]", "-map", "1:a", *encode, "-c:a", "copy", "-movflags", "+faststart", "-t", str(END),
        str(OUT / "iqro-google-play-16x9.mp4"),
    )  # fmt: skip


if __name__ == "__main__":
    main()
