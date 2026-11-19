"""Test recitations for the tajweed remarks of harness.dart: single ayat as recited ("whole"), and the same with
one ghunnah, idgham with ghunnah or madd muttasil cut to 35 % of its length ("cut"), as
docs/recitation-on-device-spike/scripts/02b_tajweed_cuts.py makes them. Only places the model's own rule engine
judges right before the cut are used.

  MODEL_DIR=… AUDIO_DIR=… python make_tajweed_cases.py <docs/recitation-on-device-spike/scripts> <output folder>
"""
import glob, json, os, sys, wave
sys.path.insert(0, sys.argv[1]); sys.argv = sys.argv[:1] + sys.argv[2:]
from common import *
out = sys.argv[1]; os.makedirs(out, exist_ok=True)
sess = session(threads=4)
FADE = 80
RULE = {'ghunnah': 0, 'idgham_ghunnah': 1}


def cut(x, a, b):
    a, b = max(FADE, int(a * 16000)), min(len(x) - FADE, int(b * 16000))
    if b - a < FADE: return x
    r = np.linspace(0, 1, FADE, dtype=np.float32)
    return np.concatenate([x[:a - FADE], x[a - FADE:a] * (1 - r) + x[b:b + FADE] * r, x[b + FADE:]])


def save(name, audio, meta):
    with wave.open(f'{out}/{name}.wav', 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
        w.writeframes((np.clip(audio, -1, 1) * 32767).astype('<i2').tobytes())
    json.dump(meta, open(f'{out}/{name}.json', 'w'))


for path in sorted(glob.glob(AUDIO_DIR + '/*/*.wav') + glob.glob(AUDIO_DIR + '_madd/*/*.wav')):
    r, f = path.split('/')[-2:]
    s, a = int(f[:3]), int(f[3:6])
    x = read_wav(path)
    if len(x) > 12 * 16000: continue  # the app looks at ayat of up to 12 s
    ws = words(s, a)
    heard, probs, times = decode(logprobs(sess, x))
    ref, clean = remarks(ws, heard, probs, times)
    if len(ref.words) != len(ws): continue
    b = imam._boundaries(ref.phonemes, heard)
    t = lambda i: times[min(b[i], len(times) - 1)]
    noted = {w['index'] for w in clean if w['notes']}
    base = dict(surah=s, ayahs=[a], reciter=r, miss=None, starts=[0] * len(ws))
    units = [u for u in ref.units if u.kind in RULE or (u.kind == 'madd' and u.rule.startswith('Mottasel'))]
    save(f'whole-{r}-{s}-{a}', x, dict(base, kind='whole', places=[[RULE.get(u.kind, 2), u.word] for u in units]))
    for n, u in enumerate(units):
        if u.word in noted: continue
        a0, a1 = t(u.s), t(u.e)
        if a1 - a0 < 0.2: continue
        keep = (a1 - a0) * 0.35
        save(f'cut-{r}-{s}-{a}-{n}', cut(x, a0 + keep / 2, a1 - keep / 2),
             dict(base, kind='cut', rule=RULE.get(u.kind, 2), word=u.word, was=round(a1 - a0, 2)))
