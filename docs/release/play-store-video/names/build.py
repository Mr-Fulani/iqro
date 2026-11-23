#!/usr/bin/env python3
"""Русские Shorts «99 имён Аллаха», три части по 33 имени, 1080×1920.

    python3 build.py              # все три части в ~/Downloads/iqro-names-ru-part1..3.mp4
    python3 build.py --part 2     # одна часть
    python3 build.py --part 1 --stills 2,10,40   # только кадры для проверки

Список и порядок — как в приложении (аль-Кахтани), озвучка — записи владельца
из clients/iqro_mobile/assets/names_audio/ru. Нужны ffmpeg, playwright и Chrome.
"""
import argparse
import json
import math
import multiprocessing as mp
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
NAMES = ROOT / "services/backend/src/quran_backend/modules/names/data/asma-al-husna.json"
AUDIO = ROOT / "clients/iqro_mobile/assets/names_audio/ru"
FPS = 30
INTRO = 2.6      # заставка до первого имени
LEAD = 0.35      # голос начинается чуть позже смены имени
GAP = 0.75       # тишина после голоса
MIN_SLOT = 2.8
OUTRO = 4.0


def duration(path):
    return float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                                          "-of", "csv=p=0", str(path)], text=True))


def plan(part):
    names = json.loads(NAMES.read_text())["names"]
    t, slots, clips = INTRO, [], []
    for idx in range((part - 1) * 33, part * 33):
        n = names[idx]
        mp3 = AUDIO / f"{n['slug']}.mp3"
        d = duration(mp3)
        slots.append({"t": round(t, 3), "idx": idx})
        clips.append((mp3, t + LEAD))
        t += max(MIN_SLOT, LEAD + d + GAP)
    cfg = {
        "part": part,
        "all": [n["transliteration"]["ru"] for n in names],
        "names": [{"arabic": names[s["idx"]]["arabic"], "name": names[s["idx"]]["transliteration"]["ru"],
                   "meaning": names[s["idx"]]["meaning"]["ru"]} for s in slots],
        "slots": slots,
        "outro": round(t, 3),
    }
    return cfg, clips, round(t + OUTRO, 2)


def worker(args):
    cfg, times, frames_dir, first = args
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        b = p.chromium.launch(channel="chrome")
        page = b.new_page(viewport={"width": 1080, "height": 1920})
        page.goto((HERE / "index.html").as_uri())
        page.wait_for_load_state("networkidle")
        page.evaluate("c => setup(c)", cfg)
        for i, t in enumerate(times):
            page.evaluate("t => render(t)", t)
            page.screenshot(path=str(Path(frames_dir) / f"{first + i:05d}.jpg"), type="jpeg", quality=95)
        b.close()


def render(cfg, times, frames_dir, workers):
    per = math.ceil(len(times) / workers)
    jobs = [(cfg, times[k * per:(k + 1) * per], str(frames_dir), k * per) for k in range(workers) if times[k * per:(k + 1) * per]]
    pool = mp.get_context("spawn").Pool(len(jobs))
    res = pool.map_async(worker, jobs)
    # Chrome иногда не закрывается после съёмки — ждём кадры на диске, а не процессы
    while not res.ready():
        res.wait(5)
        if len(list(Path(frames_dir).glob("*.jpg"))) >= len(times):
            res.wait(20)
            break
    pool.terminate()
    missing = [i for i in range(len(times)) if not (Path(frames_dir) / f"{i:05d}.jpg").exists()]
    if missing:
        sys.exit(f"Не отрисованы кадры: {missing[:10]}")


def build(part, out_dir, workers):
    cfg, clips, dur = plan(part)
    out = out_dir / f"iqro-names-ru-part{part}.mp4"
    with tempfile.TemporaryDirectory(prefix=f"iqro-names-{part}-") as tmp:
        print(f"[часть {part}] {dur} с — рендер…", flush=True)
        render(cfg, [i / FPS for i in range(int(round(dur * FPS)))], tmp, workers)
        inputs, chains = [], []
        for k, (mp3, at) in enumerate(clips):
            inputs += ["-i", str(mp3)]
            ms = int(round(at * 1000))
            chains.append(f"[{k + 1}:a]aresample=48000,adelay={ms}:all=1[a{k}]")
        mix = "".join(f"[a{k}]" for k in range(len(clips)))
        fc = ";".join(chains) + f";{mix}amix=inputs={len(clips)}:normalize=0,loudnorm=I=-16:TP=-1.5:LRA=11,aresample=48000,apad[a]"
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-framerate", str(FPS), "-i", f"{tmp}/%05d.jpg", *inputs,
                        "-filter_complex", fc, "-map", "0:v", "-map", "[a]", "-t", str(dur),
                        "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-r", str(FPS),
                        "-c:a", "aac", "-b:a", "192k", "-ac", "2", "-movflags", "+faststart", str(out)], check=True)
    sheet = out_dir / f"iqro-names-ru-part{part}-storyboard.jpg"
    count = int(dur // 3) + 1
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(out), "-vf",
                    f"fps=1/3,scale=200:-2,tile=10x{math.ceil(count / 10)}:padding=4:color=0x222222",
                    "-frames:v", "1", "-q:v", "3", str(sheet)], check=True)
    print(f"[часть {part}] готово: {out}", flush=True)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--part", type=int, choices=[1, 2, 3])
    ap.add_argument("--out", default=str(Path.home() / "Downloads"))
    ap.add_argument("--workers", type=int, default=5)
    ap.add_argument("--stills", help="только кадры на этих секундах, через запятую")
    a = ap.parse_args()
    out = Path(a.out).expanduser()
    out.mkdir(parents=True, exist_ok=True)
    for part in ([a.part] if a.part else [1, 2, 3]):
        if a.stills:
            cfg, _, dur = plan(part)
            times = [float(x) for x in a.stills.split(",")]
            worker((cfg, times, str(out), 0))
            for i, t in enumerate(times):
                (out / f"{i:05d}.jpg").rename(out / f"part{part}-{t:06.2f}.jpg")
            print(f"часть {part}: {dur} с")
        else:
            build(part, out, a.workers)


if __name__ == "__main__":
    main()
