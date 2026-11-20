import glob, json, os, sys
audio, out = sys.argv[1:3]; os.makedirs(out, exist_ok=True)
T = json.load(open(sys.argv[3]))
for p in sorted(glob.glob(audio + '/*/*.wav')):
    r, f = p.split('/')[-2:]; s, a = int(f[:3]), int(f[3:6])
    n = len(T['surahs'][str(s)][a - 1][1]) // 2
    name = f'whole-{r}-{s}-{a}'
    json.dump(dict(surah=s, ayahs=[a], reciter=r, miss=None, starts=[0] * n, kind='whole', places=[]), open(f'{out}/{name}.json', 'w'))
    if not os.path.exists(f'{out}/{name}.wav'): os.symlink(p, f'{out}/{name}.wav')
