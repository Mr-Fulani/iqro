#!/usr/bin/env python3
"""Сборка анимационного ролика IQRO под озвучку.

    python3 build.py                          # оба формата по timing.json
    python3 build.py --voice новый.mp3 --timing мои-тайминги.json
    python3 build.py --format 9x16 --stills 5,12.5,40   # только отдельные кадры для проверки

Нужны ffmpeg/ffprobe, Python-пакет playwright и Google Chrome.
Кадры рисует index.html (render(t)), сюда приходят времена фраз из timing.json.
"""
import argparse
import json
import math
import multiprocessing as mp
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
FPS = 30
SIZES = {"9x16": (1080, 1920), "16x9": (1920, 1080)}
NAMES = {"9x16": "vertical", "16x9": "horizontal"}


def probe_duration(path):
    out = subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                                   "-of", "csv=p=0", str(path)], text=True)
    return float(out.strip())


def page_config(timing, fmt, duration):
    fatiha = json.loads((HERE / "assets/fatiha.json").read_text())["ayahs"]
    names = json.loads((ROOT / "services/backend/src/quran_backend/modules/names/data/asma-al-husna.json")
                       .read_text())["names"]
    return {
        "format": fmt,
        "cues": timing["cues"],
        "voice_offset": timing.get("voice_offset", 0),
        "duration": duration,
        "fatiha": fatiha,
        "names": [{"ru": n["transliteration"]["ru"]} for n in names],
        "featured": [{"arabic": n["arabic"], "ru": n["transliteration"]["ru"], "meaning": n["meaning"]["ru"]}
                     for n in names[:3]],
    }


def render_worker(args):
    cfg, times, frames_dir, first_index = args
    from playwright.sync_api import sync_playwright
    w, h = SIZES[cfg["format"]]
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", args=["--allow-file-access-from-files"])
        page = browser.new_page(viewport={"width": w, "height": h}, device_scale_factor=1)
        page.goto((HERE / "index.html").as_uri())
        info = page.evaluate("cfg => setup(cfg)", cfg)
        for i, t in enumerate(times):
            page.evaluate("t => render(t)", t)
            page.screenshot(path=str(Path(frames_dir) / f"{first_index + i:05d}.jpg"), type="jpeg", quality=95)
        browser.close()
    return info


def render_frames(cfg, times, frames_dir, workers):
    chunks, n = [], len(times)
    per = math.ceil(n / workers)
    for k in range(workers):
        part = times[k * per:(k + 1) * per]
        if part:
            chunks.append((cfg, part, str(frames_dir), k * per))
    with mp.get_context("spawn").Pool(len(chunks)) as pool:
        infos = pool.map(render_worker, chunks)
    return infos[0]


def build(fmt, timing, voice, out_dir, workers, name):
    w, h = SIZES[fmt]
    vdur = probe_duration(voice)
    off = timing.get("voice_offset", 0)
    duration = round(off + vdur + timing.get("tail", 2.0), 2)
    nframes = int(round(duration * FPS))
    cfg = page_config(timing, fmt, duration)
    out = out_dir / f"{name}-{NAMES[fmt]}.mp4"
    with tempfile.TemporaryDirectory(prefix=f"iqro-frames-{fmt}-") as tmp:
        print(f"[{fmt}] {nframes} кадров, {duration} с — рендер…", flush=True)
        info = render_frames(cfg, [i / FPS for i in range(nframes)], tmp, workers)
        print(f"[{fmt}] слов в аятах: {info['words']}", flush=True)
        delay = int(round(off * 1000))
        subprocess.run([
            "ffmpeg", "-v", "error", "-y", "-framerate", str(FPS), "-i", f"{tmp}/%05d.jpg", "-i", str(voice),
            "-filter_complex",
            f"[1:a]adelay={delay}:all=1,loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000,apad[a]",
            "-map", "0:v", "-map", "[a]", "-t", f"{duration}",
            "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-r", str(FPS),
            "-c:a", "aac", "-b:a", "192k", "-ac", "2", "-movflags", "+faststart", str(out),
        ], check=True)
    storyboard(out, fmt, out_dir / f"{name}-{NAMES[fmt]}-storyboard.jpg", duration)
    print(f"[{fmt}] готово: {out}", flush=True)


def storyboard(video, fmt, dest, duration, step=1.5):
    """Кадр каждые step секунд, с временем в углу."""
    cols = 8 if fmt == "9x16" else 5
    count = int(duration // step) + 1
    rows = math.ceil(count / cols)
    tw = 240 if fmt == "9x16" else 384
    subprocess.run([
        "ffmpeg", "-v", "error", "-y", "-i", str(video), "-vf",
        f"fps=1/{step},scale={tw}:-2,drawtext=text='%{{pts\\:hms}}':x=6:y=6:fontsize=18:fontcolor=white:box=1:boxcolor=black@0.6,"
        f"tile={cols}x{rows}:padding=4:color=0x222222",
        "-frames:v", "1", "-q:v", "3", str(dest),
    ], check=True)


def stills(fmt, timing, voice, out_dir, times):
    vdur = probe_duration(voice)
    duration = round(timing.get("voice_offset", 0) + vdur + timing.get("tail", 2.0), 2)
    cfg = page_config(timing, fmt, duration)
    out_dir.mkdir(parents=True, exist_ok=True)
    info = render_worker((cfg, times, str(out_dir), 0))
    for i, t in enumerate(times):
        (out_dir / f"{i:05d}.jpg").rename(out_dir / f"{fmt}-{t:06.2f}.jpg")
    print(info)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--timing", default=str(HERE / "timing.json"), help="JSON с началами фраз (по файлу озвучки)")
    ap.add_argument("--voice", help="файл озвучки; по умолчанию — из timing.json")
    ap.add_argument("--format", choices=["9x16", "16x9", "both"], default="both")
    ap.add_argument("--out", default=str(Path.home() / "Downloads"))
    ap.add_argument("--name", default="iqro-promo", help="начало имени файла: <name>-vertical.mp4 / <name>-horizontal.mp4")
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--stills", help="только кадры на этих секундах ролика, через запятую")
    a = ap.parse_args()

    timing = json.loads(Path(a.timing).read_text())
    voice = Path(a.voice or timing["voice"]).expanduser()
    if not voice.exists():
        sys.exit(f"Нет файла озвучки: {voice}")
    if not shutil.which("ffmpeg"):
        sys.exit("Нужен ffmpeg")
    out_dir = Path(a.out).expanduser()
    out_dir.mkdir(parents=True, exist_ok=True)
    fmts = ["9x16", "16x9"] if a.format == "both" else [a.format]
    for fmt in fmts:
        if a.stills:
            stills(fmt, timing, voice, out_dir, [float(x) for x in a.stills.split(",")])
        else:
            build(fmt, timing, voice, out_dir, a.workers, a.name)


if __name__ == "__main__":
    main()
