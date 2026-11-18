"""Step 1, mistakes made by cutting audio (no live reader): a word cut out, another ayah read, a long madd cut short.
The cuts are placed with the model's own timing of the uncut clip, so they are only as exact as that timing.

  MODEL_DIR=… AUDIO_DIR=… python 02_errors.py > out/02_errors.txt
"""
import collections, os
from common import *

reciters = sorted(os.listdir(AUDIO_DIR))
sess = session()
FADE = 80  # samples (5 ms) of cross-fade at a cut


def hear(x):
    return decode(logprobs(sess, x))


def cut(x, a, b):
    """x without [a, b) seconds, cross-faded"""
    a, b = int(a * 16000), int(b * 16000)
    a, b = max(FADE, a), min(len(x) - FADE, b)
    if b - a < FADE: return x
    r = np.linspace(0, 1, FADE, dtype=np.float32)
    return np.concatenate([x[:a - FADE], x[a - FADE:a] * (1 - r) + x[b:b + FADE] * r, x[b + FADE:]])


def timing(ws, x):
    heard, probs, times = hear(x)
    ref, out = remarks(ws, heard, probs, times)
    b = imam._boundaries(ref.phonemes, heard)
    t = lambda i: times[min(b[i], len(times) - 1)]
    return ref, out, t


stat = collections.Counter()
lines = collections.defaultdict(list)
madd_kinds = collections.Counter()
for r in reciters:
    for n, (s, a) in enumerate(CLIPS):
        x, ws = clip(r, s, a), words(s, a)
        ref, clean, t = timing(ws, x)
        if ref.phonemes != ''.join(hear(x)[0]) or len(ref.words) != len(ws):
            stat['clips left out: the uncut clip is not heard exactly'] += 1
            continue
        stat['clips used'] += 1

        # A. a word in the middle is cut out
        for k in range(1, len(ws) - 1):
            (ps, pe) = ref.spans[k]
            if pe - ps < 3: continue
            y = cut(x, t(ps) - 0.03, t(pe) - 0.03)
            h, p, tm = hear(y)
            _, out = remarks(ws, h, p, tm)
            got = {w['index']: w for w in out if w['notes']}
            stat['A cuts'] += 1
            hit = k in got
            near = hit or k - 1 in got or k + 1 in got
            missing = hit and any(n['rule'] == 'word' or 'missing' in n['msg']['en'] or 'skipped' in n['msg']['en'] for n in got[k]['notes'])
            stat['A remark on the cut word'] += hit
            stat['A … and it says the word is missing'] += missing
            stat['A remark on the cut word or a neighbour'] += near
            stat['A no remark at all'] += not got
            stat['A words far from the cut that got a remark'] += sum(1 for i in got if abs(i - k) > 1)
            stat['A words far from the cut'] += sum(1 for i in range(len(ws)) if abs(i - k) > 1)
            if len(lines['A']) < 25:
                lines['A'].append(f"{r} {s}:{a} cut «{ws[k]}» → " + ('; '.join(f"{w['word']}: {n['msg']['en']}" for w in out for n in w['notes']) or 'no remark'))

        # B. the audio of this ayah against the text of the next clip
        s2, a2 = CLIPS[(n + 1) % len(CLIPS)]
        ws2 = words(s2, a2)
        h, p, tm = hear(x)
        _, out = remarks(ws2, h, p, tm)
        stat['B wrong-ayah trials'] += 1
        stat['B words expected'] += len(ws2)
        stat['B words with a remark'] += sum(1 for w in out if w['notes'])
        stat['B trials with at least half of the words remarked'] += sum(1 for w in out if w['notes']) * 2 >= len(ws2)
        stat['B trials with no remark'] += not any(w['notes'] for w in out)

        # C. a long madd (4 counts or more expected) cut to 35 % of its length
        for u in ref.units:
            if u.kind != 'madd' or u.golden < 4: continue
            a0, a1 = t(u.s), t(u.e)
            if a1 - a0 < 0.35: continue
            keep = (a1 - a0) * 0.35
            y = cut(x, a0 + keep / 2, a1 - keep / 2)
            h, p, tm = hear(y)
            _, out = remarks(ws, h, p, tm)
            w = next((w for w in out if w['index'] == u.word and w['notes']), None)
            short = bool(w) and any(('short' in n['msg']['en'] or 'dropped' in n['msg']['en']) and 'madd' in n['msg']['en'] for n in w['notes'])
            stat['C madd cuts'] += 1; stat['C remark "madd too short / dropped" on that word'] += short
            stat['C another remark on that word only'] += bool(w) and not short
            stat['C no remark on that word'] += not w
            madd_kinds[(u.rule, short)] += 1
            if len(lines['C']) < 25:
                lines['C'].append(f"{r} {s}:{a} «{ws[u.word]}» {u.rule} {a1 - a0:.2f} s → {keep:.2f} s: " + ('; '.join(n['msg']['en'] for w2 in out if w2['index'] == u.word for n in w2['notes']) or 'no remark'))

for k, v in stat.items(): print(f'{v:5d}  {k}')
print('\nC by kind of madd (caught / not):')
for (rule, ok), v in sorted(madd_kinds.items()): print(f'  {rule} {"caught" if ok else "missed"}: {v}')
for g in 'AC':
    print(f'\nexamples {g}:')
    for l in lines[g]: print('  ', l)
