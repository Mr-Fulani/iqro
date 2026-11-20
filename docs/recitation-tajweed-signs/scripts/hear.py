"""How the model writes each tajweed place on right recitations of masters (no app logic): for every place of a rule
in the expected script, the counts of its sound in what the model heard.
  MODEL_DIR=… python hear.py <scripts dir> <audio dir> [<audio dir> …]"""
import glob, json, os, sys, collections
scripts = sys.argv[1]; dirs = sys.argv[2:]
os.environ.setdefault('AUDIO_DIR', dirs[0])
sys.path.insert(0, scripts)
from common import *
sess = session(threads=4)
stat = collections.defaultdict(collections.Counter); ex = collections.defaultdict(list)
special = collections.defaultdict(collections.Counter)
n = skipped = 0
for d in dirs:
    for path in sorted(glob.glob(d + '/*/*.wav')):
        r, f = path.split('/')[-2:]
        s, a = int(f[:3]), int(f[3:6])
        x = read_wav(path)
        if len(x) > 28 * 16000: skipped += 1; continue
        ws = words(s, a)
        heard, probs, times = decode(logprobs(sess, x))
        ref = imam.recited(ws, heard, riwaya='hafs')
        b = imam._boundaries(ref.phonemes, heard)
        n += 1
        for u in ref.units:
            k = u.kind if u.kind != 'madd' else u.rule
            c = u.char if u.kind != 'qalqalah' else 'ڇ'
            got, _, _ = imam._run(heard, max(0, b[u.s] - 1), min(len(heard), b[u.e] + 1), c)
            want = u.golden if u.kind != 'qalqalah' else 1
            key = 'as written' if got == want else ('none' if got == 0 else ('fewer' if got < want else 'more'))
            stat[k][key] += 1; stat[k][f'{got} of {want}'] += 1
            if key in ('none', 'fewer') and len(ex[k]) < 6: ex[k].append(f'{r[:8]} {s}:{a} {ref.words[u.word]} {got}/{want}')
        for i, ch in enumerate(ref.phonemes):
            if ch in '۪ۜـٲؙ' and (i == 0 or ref.phonemes[i - 1] != ch):
                special[ch]['heard' if ch in heard[max(0, b[i] - 2):b[i + 1] + 2] else 'not heard'] += 1
                special[ch][f'{r[:8]} {s}:{a} → {heard[max(0, b[i] - 4):b[i + 1] + 4]}'] += 1
print(f'{n} recitations, {skipped} longer than 28 s left out')
for k, c in sorted(stat.items(), key=lambda x: -sum(v for q, v in x[1].items() if ' of ' in q)):
    tot = sum(v for q, v in c.items() if ' of ' in q)
    print(f"{k}: {tot} places; as written {c['as written']}, fewer {c['fewer']}, none {c['none']}, more {c['more']} | " +
          ', '.join(f'{q}: {v}' for q, v in sorted(c.items()) if ' of ' in q))
    if ex[k]: print('     e.g. ' + '; '.join(ex[k]))
for ch, c in special.items():
    print(f'U+{ord(ch):04X} {ch}:', dict(c))
