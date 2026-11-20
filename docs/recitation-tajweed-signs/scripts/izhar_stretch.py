"""A ghunnah where there must be none: the clear nun of an izhar (a tanween or a nun with sukun before a throat
letter: «عَذَابٌ عَظِيمٌ», «أَنْعَمْتَ») held long. The nun of a master's right recitation is stretched to about two
counts; printed: how many counts of ن the model writes before and after. Writes cases for harness.dart.

  MODEL_DIR=… python izhar_stretch.py <spike scripts dir> <out cases dir> <expected.json> <audio dir> [<audio dir> …]"""
import glob, json, os, subprocess, sys, tempfile, wave, collections
scripts, out, table = sys.argv[1:4]; dirs = sys.argv[4:]
os.environ.setdefault('AUDIO_DIR', dirs[0]); sys.path.insert(0, scripts)
from common import *
T = json.load(open(table)); os.makedirs(out, exist_ok=True)
sess = session(threads=4)
THROAT, HAR = set('ءهعحغخ'), set('َُِ')

def write(path, x):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(16000)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype('<i2').tobytes())

def stretch(x, a, b, factor):
    """x with [a, b) s played `factor` times slower, the pitch kept (ffmpeg atempo)"""
    i, j = int(a * 16000), int(b * 16000)
    with tempfile.TemporaryDirectory() as d:
        write(d + '/a.wav', x[i:j])
        chain = ','.join(['atempo=0.5'] * int(round(np.log2(factor))))
        subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-i', d + '/a.wav', '-af', chain, '-ar', '16000', d + '/b.wav'], check=True)
        mid = read_wav(d + '/b.wav')
    return np.concatenate([x[:i], mid, x[j:]])

stat = collections.Counter(); rows = []
for d in dirs:
    for path in sorted(glob.glob(d + '/*/*.wav')):
        r, f = path.split('/')[-2:]; s, a = int(f[:3]), int(f[3:6])
        x = read_wav(path)
        if len(x) > 14 * 16000: continue
        ph, sp = T['surahs'][str(s)][a - 1][:2]
        heard, probs, times = decode(logprobs(sess, x))
        b = imam._boundaries(ph, heard)
        for i in range(1, len(ph) - 1):
            if not (ph[i] == 'ن' and ph[i - 1] in HAR and ph[i + 1] in THROAT and ph[i - 1] != 'ن'): continue
            if i < sp[1]: continue                      # not in the first word
            n0, hs, he = imam._run(heard, max(0, b[i] - 1), min(len(heard), b[i + 1] + 1), 'ن')
            if n0 != 1: stat['left out: the nun is not heard once as recited'] += 1; continue
            t0, t1 = times[hs], times[he]
            y = stretch(x, t0, t1, 4)
            h2, p2, tt2 = decode(logprobs(sess, y))
            b2 = imam._boundaries(ph, h2)
            n1, s2, e2 = imam._run(h2, max(0, b2[i] - 1), min(len(h2), b2[i + 1] + 1), 'ن')
            around = h2[max(0, s2 - 3):e2 + 3]
            stat['places'] += 1; stat[f'the model writes {n1} ن'] += 1
            if any(c in around for c in 'ں۾'): stat['… and a hidden nun (ں) beside it'] += 1
            word = next(k for k in range(len(sp) // 2) if sp[2 * k] <= i < sp[2 * k + 1])
            name = f'whole-{r}-{s}-{a}-{i}'
            write(f'{out}/{name}.wav', y)
            json.dump(dict(surah=s, ayahs=[a], reciter=r, miss=None, starts=[0] * (len(sp) // 2), kind='cut', rule=30, word=word,
                           was=round(t1 - t0, 2)), open(f'{out}/{name}.json', 'w'))
            rows.append(f'{r[:10]} {s}:{a} {ph[max(0, i - 4):i + 3]}  nun {t1 - t0:.2f} s → {(t1 - t0) * 4:.2f} s: model writes {around}')
print(dict(stat)); print('\n'.join(rows))
