"""The characters of the Quran text with tajweed colouring (Quran.Foundation text_uthmani_tajweed, the source of the
app's coloured words): pause marks, rub el hizb, sajdah and the rest; and how often each rule class is marked.
  curl -o taj.json https://api.quran.com/api/v4/quran/verses/uthmani_tajweed ; python census_tajweed_text.py taj.json"""
import json, re, sys, collections, unicodedata
d = json.load(open(sys.argv[1]))['verses']
c = collections.Counter(); ex = collections.defaultdict(list); ay = collections.Counter(); classes = collections.Counter()
for v in d:
    t = v['text_uthmani_tajweed']
    for m in re.finditer(r'class=([a-z_]+)', t): classes[m.group(1)] += 1
    t = re.sub(r'<[^>]+>', '', re.sub(r'<span class=end>.*?</span>', '', t))
    seen = set()
    for w in t.split(' '):
        for ch in w:
            c[ch] += 1
            if ch not in seen:
                seen.add(ch); ay[ch] += 1
                if len(ex[ch]) < 3: ex[ch].append((v['verse_key'], w))
for ch, n in sorted(c.items(), key=lambda x: ord(x[0])):
    if ord(ch) < 0x64B and ord(ch) != 0x640: continue
    print(f'U+{ord(ch):04X}\t{unicodedata.name(ch, "?")}\t{n}\t{ay[ch]}\t' + '; '.join(f'{k} {w}' for k, w in ex[ch]))
print(dict(classes.most_common()))
