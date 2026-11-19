"""Step 2, the follower on recitations with something left out (made by cutting audio): a whole ayah, or one word.
Asked: does the follower say that exactly these words were jumped over, how long after the reader went on, and
does it then follow to the end.

  MODEL_DIR=… AUDIO_DIR=… python 04_follow_skips.py > out/04_follow_skips.txt
"""
import importlib, os
from common import *
f = importlib.import_module('03_follow')

HOP, WINDOW, TAIL = 0.2, 3, 0.4
FADE = 80
reciters = sorted(os.listdir(AUDIO_DIR))
sess = session(threads=4)


def cut(x, a, b):
    a, b = max(FADE, int(a * 16000)), min(len(x) - FADE, int(b * 16000))
    r = np.linspace(0, 1, FADE, dtype=np.float32)
    return np.concatenate([x[:a - FADE], x[a - FADE:a] * (1 - r) + x[b:b + FADE] * r, x[b + FADE:]])


def run(p, audio, gone, t_next):
    """gone: (first, last) word left out; t_next: when the word after it begins in this audio"""
    steps, _ = f.follow(sess, p, audio, HOP, WINDOW, 0.0, TAIL)
    first = next(((now, v, w) for now, pos, js in steps for _, v, w in js if v < gone[0] <= gone[1] < w or (v, w) == (gone[0] - 1, gone[1] + 1)), None)
    final = {(v, w) for _, v, w in steps[-1][2]} | {(v, w) for now, pos, js in steps for t, v, w in js if now - t > 1.5}
    exact = (gone[0] - 1, gone[1] + 1) in final
    return first, exact, final, steps[-1][1] >= len(p.ids) - 2


rows = []
for kind in ('ayah', 'word'):
    n = found = exact_n = to_end = extra = 0; delays = []
    for r in reciters:
        for s, na in ((1, 7), (112, 4), (113, 5), (114, 6)):
            p = f.Passage(s, range(1, na + 1))
            clips = [(a, clip(r, s, a)) for a in range(1, na + 1)]
            tr = f.truth(sess, p, clips)
            offs = np.cumsum([0] + [len(x) / 16000 for _, x in clips])
            k = 3 if s == 1 else 2  # the ayah that is touched
            ws = [w for w, a in enumerate(p.ayah_of) if a == k]
            if kind == 'ayah':
                audio = np.concatenate([x for a, x in clips if a != k])
                gone = (ws[0], ws[-1]); t_next = tr[ws[-1] + 1][0] - (offs[k] - offs[k - 1])
            else:
                if len(ws) < 3: continue
                w = ws[1]; a0, a1 = tr[w][0] - 0.03, tr[w + 1][0] - 0.03
                audio = cut(np.concatenate([x for _, x in clips]), a0, a1)
                gone = (w, w); t_next = a0
            first, exact, final, end = run(p, audio, gone, t_next)
            n += 1; found += first is not None; exact_n += exact; to_end += end; extra += len(final - {(gone[0] - 1, gone[1] + 1)})
            if first: delays.append(first[0] - t_next)
            rows.append(f"{kind} | {r} | {s}:{k} | left out «{' '.join(p.words[gone[0]:gone[1] + 1])}» | "
                        f"first said after {first[0] - t_next:.2f} s" if first else f"{kind} | {r} | {s}:{k} | not noticed" )
            rows[-1] += f" | settled jumps: {sorted(final)} (expected {(gone[0] - 1, gone[1] + 1)}) | followed to the end: {end}"
    print(f'left out: one {kind} — {n} trials; noticed in {found}; settled on exactly the right words in {exact_n}; '
          f'other (false) jumps {extra}; followed to the end in {to_end}; '
          f'the next word begins → "left out" first said: median {np.median(delays or [np.nan]):.2f} s, slowest {max(delays or [np.nan]):.2f} s', flush=True)
print()
for r in rows: print(r)
