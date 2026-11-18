"""Step 1: the model on whole ayat of professional reciters: sound error rate, words with a remark, speed.

  MODEL_DIR=… AUDIO_DIR=… python 01_offline.py > out/01_offline.txt
"""
import collections, os, time
import Levenshtein
from common import *

reciters = sorted(os.listdir(AUDIO_DIR))
sess = session()
tot = collections.defaultdict(lambda: collections.Counter())
kinds = collections.Counter()
examples = []
for r in reciters:
    for s, a in CLIPS:
        x = clip(r, s, a)
        heard, probs, times = decode(logprobs(sess, x))
        ws = words(s, a)
        ref, out = remarks(ws, heard, probs, times)
        c = tot[r]
        c['sounds'] += len(ref.phonemes); c['sound_errors'] += Levenshtein.distance(ref.phonemes, heard)
        c['words'] += len(out); c['words_remark'] += sum(1 for w in out if w['notes'])
        c['words_jali'] += sum(1 for w in out if any(n['severity'] == 'jali' for n in w['notes']))
        c['clips'] += 1; c['clips_exact'] += ref.phonemes == heard
        c['seconds'] += len(x) / 16000
        for w in out:
            for n in w['notes']:
                kinds[(n['severity'], n['rule'])] += 1
                if len(examples) < 400: examples.append((r, s, a, w['word'], n['severity'], n['rule'], n['msg']['en']))

print('reciter | clips | audio s | sound error rate | clips heard exactly | words | words with a remark | of them "clear mistake"')
allc = collections.Counter()
for r in reciters:
    c = tot[r]; allc.update(c)
for r, c in list(tot.items()) + [('ALL', allc)]:
    print(f"{r} | {c['clips']} | {c['seconds']:.0f} | {100 * c['sound_errors'] / c['sounds']:.1f} % | {c['clips_exact']} | "
          f"{c['words']} | {c['words_remark']} ({100 * c['words_remark'] / c['words']:.1f} %) | {c['words_jali']} ({100 * c['words_jali'] / c['words']:.1f} %)")

print('\nremarks on these (correct) recitations by kind:')
for k, n in kinds.most_common(): print(f'  {n:3d}  {k[0]:5s} {k[1]}')
print('\nall remarks:')
for e in examples: print('  ', *e, sep=' | ')

print('\nspeed on this computer (median of 5 runs, the model alone and with the log-mel):')
x = clip(reciters[0], 2, 5)
for model in ('onnx/model-int8.onnx', 'onnx/model-fp32.onnx'):
    for threads in (1, 2, 4):
        se = session(model, threads)
        for secs in (2, 4, 8, 15):
            seg = np.resize(x, secs * 16000)
            ts = []
            for _ in range(6):
                t = time.perf_counter(); logprobs(se, seg, lead=False); ts.append(time.perf_counter() - t)
            m = sorted(ts[1:])[2]
            print(f'  {model[11:-5]} threads={threads} audio={secs:2d} s → {1000 * m:6.1f} ms  ({1000 * m / secs:.1f} ms per second of audio)')
