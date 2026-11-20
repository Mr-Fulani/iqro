"""Reads the verbose output of harness.dart on the cases of mutate_cases.py and own_cases.py:
per rule, on how many recitations the follower stopped on the changed word (or a neighbour), stopped elsewhere, did
not stop; for the unchanged ayat, the false stops.   python parse.py <case folders…> -- <harness outputs…>"""
import glob, json, os, re, sys, collections
k = sys.argv.index('--'); folders, outs = sys.argv[1:k], sys.argv[k + 1:]
meta = {}
for d in folders:
    for p in glob.glob(d + '/*.json'): meta[os.path.basename(p)] = json.load(open(p))
blocks = {}
for f in outs:
    text = open(f).read()
    parts = re.split(r'^# (.+)$', text, flags=re.M)
    cut = 'counts heard' not in text  # a run that was stopped: its last recitation is not whole
    names = parts[1::2]; bodies = parts[2::2]
    for n, b in list(zip(names, bodies))[:len(names) - (1 if cut else 0)]:
        blocks[os.path.basename(n)] = b
rule = collections.defaultdict(collections.Counter); ex = collections.defaultdict(list)
clean = collections.defaultdict(lambda: collections.Counter()); stops = []
for name, body in sorted(blocks.items()):
    m = meta.get(name)
    if not m: continue
    misses = [(int(w), float(t)) for t, w in re.findall(r'^\s+([\d.]+) MISS (\d+)', body, re.M)]
    reached = {int(w) for w in re.findall(r'^\s+[\d.]+ on (\d+)', body, re.M)}
    if m['kind'] == 'cut':
        r = name.split('-whole')[0]; w = m['word']
        near = [x for x in misses if abs(x[0] - w) <= 1]
        key = 'stopped on the word' if near else ('stopped elsewhere only' if misses else 'not stopped')
        rule[r]['recitations'] += 1; rule[r][key] += 1
        if len(ex[r]) < 3: ex[r].append(m['was'] + (' ✓' if near else ' —'))
    else:
        key = f"{m['surah']}:{m['ayahs'][0]}"
        clean[key]['recitations'] += 1; clean[key]['words'] = len(m['starts'])
        clean[key]['false stops'] += len(misses); clean[key]['words reached'] += len(reached)
        for w, t in misses: stops.append(f"{m['reciter']} {key} word {w + 1} at {t:.1f} s")
print('# a right recitation against a text changed in one place: did the follower stop?')
for r, c in rule.items():
    print(f"{r}: {dict(c)}   e.g. " + '; '.join(ex[r]))
print('\n# ayat with special signs as recited (3 reciters): false stops')
for key, c in sorted(clean.items(), key=lambda x: [int(v) for v in x[0].split(':')]):
    print(f"{key}: recitations {c['recitations']}, words {c['words']}, reached {c['words reached']} of {c['words'] * c['recitations']}, false stops {c['false stops']}")
print('\n'.join(stops))
