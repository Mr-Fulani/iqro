"""Test recitations for harness.dart: clean ones, and ones with an ayah or a word cut out, each a WAV with the
times its words begin (from the model on each whole ayah, as docs/recitation-on-device-spike/scripts/03_follow.py).

  MODEL_DIR=… AUDIO_DIR=… python make_cases.py <docs/recitation-on-device-spike/scripts> <output folder>
"""
import importlib, json, os, sys, wave
sys.path.insert(0, sys.argv[1]); sys.argv = sys.argv[:1] + sys.argv[2:]
from common import *
f = importlib.import_module('03_follow')
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
sess = session(threads=4)
FADE = 80


def cut(x, a, b):
    a, b = max(FADE, int(a * 16000)), min(len(x) - FADE, int(b * 16000))
    r = np.linspace(0, 1, FADE, dtype=np.float32)
    return np.concatenate([x[:a - FADE], x[a - FADE:a] * (1 - r) + x[b:b + FADE] * r, x[b + FADE:]])


def save(name, audio, meta):
    with wave.open(f'{out}/{name}.wav', 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
        w.writeframes((np.clip(audio, -1, 1) * 32767).astype('<i2').tobytes())
    json.dump(meta, open(f'{out}/{name}.json', 'w'))


for r in sorted(os.listdir(AUDIO_DIR)):
    for s, n in ((1, 7), (103, 3), (112, 4), (113, 5), (114, 6), (2, 5)):
        p = f.Passage(s, range(1, n + 1))
        clips = [(a, clip(r, s, a)) for a in range(1, n + 1)]
        tr = f.truth(sess, p, clips)
        offs = np.cumsum([0] + [len(x) / 16000 for _, x in clips])
        base = dict(surah=s, ayahs=list(range(1, n + 1)), reciter=r)
        save(f'clean-{r}-{s}', np.concatenate([x for _, x in clips]), dict(base, kind='clean', starts=[t[0] for t in tr], miss=None))
        if s in (103, 2): continue
        k = 3 if s == 1 else 2
        ws = [w for w, a in enumerate(p.ayah_of) if a == k]
        gap = offs[k] - offs[k - 1]
        save(f'ayah-{r}-{s}', np.concatenate([x for a, x in clips if a != k]),
             dict(base, kind='ayah', miss=ws[0], resume=tr[ws[-1] + 1][0] - gap, starts=[t[0] - (gap if w > ws[-1] else 0) for w, t in enumerate(tr)]))
        for a in range(1, n + 1):  # one word from the middle of every ayah that has three
            ws = [w for w, q in enumerate(p.ayah_of) if q == a]
            if len(ws) < 3 or a == 1: continue
            w = ws[1]; a0, a1 = tr[w][0] - 0.03, tr[w + 1][0] - 0.03
            save(f'word-{r}-{s}-{a}', cut(np.concatenate([x for _, x in clips]), a0, a1),
                 dict(base, kind='word', miss=w, resume=a0, starts=[t[0] - ((a1 - a0) if q > w else 0) for q, t in enumerate(tr)]))
