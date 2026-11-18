"""Step 1, tajweed mistakes made by cutting audio: an obligatory long madd (muttasil, lazim) or a ghunnah is cut to
35 % of its length. Only places the model judged right before the cut are used. Clips: AUDIO_DIR and AUDIO_DIR_madd.

  MODEL_DIR=… AUDIO_DIR=… python 02b_tajweed_cuts.py > out/02b_tajweed_cuts.txt
"""
import collections, glob, os
from common import *

FADE = 80
sess = session()


def cut(x, a, b):
    a, b = int(a * 16000), int(b * 16000)
    a, b = max(FADE, a), min(len(x) - FADE, b)
    if b - a < FADE: return x
    r = np.linspace(0, 1, FADE, dtype=np.float32)
    return np.concatenate([x[:a - FADE], x[a - FADE:a] * (1 - r) + x[b:b + FADE] * r, x[b + FADE:]])


NASAL = ('ghunnah', 'ikhfa', 'iqlab', 'idgham_ghunnah')
stat = collections.defaultdict(collections.Counter)
lines = collections.defaultdict(list)
for path in sorted(glob.glob(AUDIO_DIR + '/*/*.wav') + glob.glob(AUDIO_DIR + '_madd/*/*.wav')):
    r, f = path.split('/')[-2:]
    s, a = int(f[:3]), int(f[3:6])
    x = read_wav(path)
    if len(x) > 29 * 16000: continue
    ws = words(s, a)
    heard, probs, times = decode(logprobs(sess, x))
    ref, clean = remarks(ws, heard, probs, times)
    if len(ref.words) != len(ws): continue  # the reciter stopped inside the ayah: left out to keep word indices plain
    b = imam._boundaries(ref.phonemes, heard)
    t = lambda i: times[min(b[i], len(times) - 1)]
    noted = {w['index'] for w in clean if w['notes']}
    for u in ref.units:
        if u.kind == 'madd' and (u.rule.startswith('Mottasel') or u.rule == 'LazemMaddRule'): group, want = u.rule, 'madd'
        elif u.kind in NASAL: group, want = u.kind, 'ghunnah'
        else: continue
        c = stat[group]
        if u.word in noted: c['left out: remarked before the cut'] += 1; continue
        a0, a1 = t(u.s), t(u.e)
        if a1 - a0 < 0.2: c['left out: shorter than 0.2 s'] += 1; continue
        keep = (a1 - a0) * 0.35
        h, p, tm = decode(logprobs(sess, cut(x, a0 + keep / 2, a1 - keep / 2)))
        _, out = remarks(ws, h, p, tm)
        notes = [n for w in out if w['index'] == u.word for n in w['notes']]
        msgs = [n['msg']['en'] for n in notes]
        if want == 'madd': hit = any('madd' in m and ('short' in m or 'dropped' in m) for m in msgs)
        else: hit = any(k in m for m in msgs for k in ('ghunnah', 'ikhfa', 'iqlab', 'idgham', 'nun', 'shadda'))
        c['cuts'] += 1
        c['caught: a remark of that kind on the word'] += hit
        c['another remark on the word'] += bool(msgs) and not hit
        c['no remark'] += not msgs
        c['other words that got a new remark'] += sum(1 for w in out if w['notes'] and w['index'] != u.word and w['index'] not in noted)
        if len(lines[group]) < 12:
            lines[group].append(f"{r} {s}:{a} «{ws[u.word]}» {a1 - a0:.2f} s → {keep:.2f} s: " + ('; '.join(msgs) or 'no remark'))

for g, c in stat.items():
    print(g)
    for k, v in c.items(): print(f'  {v:4d}  {k}')
    for l in lines[g]: print('      ', l)
