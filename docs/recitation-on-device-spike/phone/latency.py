import json, re, sys, wave
import numpy as np
S = sys.argv[1]
allv, allp = [], []
for r in sys.argv[2:]:
    pcm = np.fromfile(f'{S}/live/final-{r}.pcm', '<i2').astype(float) / 32768
    w = wave.open(f'{S}/cases/clean-{r}-1.wav'); src = np.frombuffer(w.readframes(w.getnframes()), '<i2').astype(float) / 32768
    starts = json.load(open(f'{S}/cases/clean-{r}-1.json'))['starts']
    env = lambda x: np.sqrt(np.convolve(x ** 2, np.ones(160) / 160, 'same'))[::160]  # 100 values a second
    a, b = env(pcm), env(src)
    a, b = a - a.mean(), b - b.mean()
    c = np.correlate(a, b, 'valid') if len(a) >= len(b) else None
    lag = int(np.argmax(c)) / 100
    e = env(pcm); snr = 20 * np.log10(np.percentile(e, 90) / np.percentile(e, 10))
    seen, total, proc, steps, models = {}, [], [], [], []
    for line in open(f'{S}/live/final-{r}.log'):
        m = re.search(r'place word=(\d+) wrong=(\w+) heard=([\d.]+) after=(\d+)ms', line)
        if m and m.group(2) == 'false' and int(m.group(1)) not in seen:
            wd, heard, after = int(m.group(1)), float(m.group(3)), int(m.group(4))
            seen[wd] = 1
            total.append(heard + after / 1000 - (starts[wd] + lag)); proc.append(after)
        m = re.search(r'step heard=([\d.]+) model=(\d+)ms rest=(\d+)ms done=(\d+)ms', line)
        if m: steps.append(float(m.group(1))); models.append(int(m.group(2)))
    misses = sum(1 for l in open(f'{S}/live/final-{r}.log') if 'wrong=true' in l)
    gaps = np.diff(steps)
    print(f'{r}: playback began {lag:.2f} s into the recording; signal {snr:.0f} dB over the room; words {len(seen)}/29; false stops {misses}; '
          f'word begins → lens: median {np.median(total):.2f} s, 90 % {np.percentile(total, 90):.2f} s, worst {max(total):.2f} s; '
          f'of it after the sound came: median {np.median(proc):.0f} ms; model step median {np.median(models):.0f} ms, a step every {np.median(gaps):.2f} s')
    allv += total; allp += proc
print(f'ALL: {len(allv)} words; word begins → lens: median {np.median(allv):.2f} s, 90 % {np.percentile(allv, 90):.2f} s, worst {max(allv):.2f} s; lens before the word began (< -0.1 s): {sum(1 for v in allv if v < -0.1)}; after the sound came: median {np.median(allp):.0f} ms, 90 % {np.percentile(allp, 90):.0f} ms')
