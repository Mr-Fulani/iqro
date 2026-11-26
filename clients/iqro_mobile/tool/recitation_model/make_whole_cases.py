"""Single ayat as recited, for harness.dart (kind "whole"), with no model needed: any stop of the place is false.
  python make_whole_cases.py <audio dir> <expected.json> <output folder>"""
import glob, json, os, shutil, sys
audio, table, out = sys.argv[1:4]
os.makedirs(out, exist_ok=True)
t = json.load(open(table))['surahs']
for path in sorted(glob.glob(audio + '/*/*.wav')):
    r, f = path.split('/')[-2:]
    s, a = int(f[:3]), int(f[3:6])
    n = len(t[str(s)][a - 1][1]) // 2
    name = f'whole-{r}-{s}-{a}'
    shutil.copy(path, f'{out}/{name}.wav')
    json.dump(dict(surah=s, ayahs=[a], reciter=r, miss=None, starts=[0] * n, kind='whole', places=[]), open(f'{out}/{name}.json', 'w'))
