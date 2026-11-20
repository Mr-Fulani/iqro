"""Cases for tool/recitation_model/harness.dart that ask of each tajweed rule: when a reader breaks it, does the
app's follower stop on the word? A right recitation of a master is run against a text changed in one place, so that
the recitation differs from the text by exactly that rule (text: ikhfa, read: a clear nun; text: a long vowel, read:
a short one …). Writes a table folder (expected.json with one "surah" per case, mel_filters.bin) and a cases folder.

  python mutate_cases.py <assets/recitation_model> <folder of clean cases: *.json + *.wav> <out> [per rule=40]
"""
import glob, json, os, random, shutil, sys
assets, src, out = sys.argv[1:4]
per = int(sys.argv[4]) if len(sys.argv) > 4 else 40
T = json.load(open(f'{assets}/expected.json'))
HAR, LONG = 'َُِ', {'َ': 'ا', 'ُ': 'ۥ', 'ِ': 'ۦ'}
LETTERS = set(T['symbols'][:28])
THROAT = set('ءهعحغخ')

def edit(ayah, i, j, new):
    """the ayah with sounds [i, j) replaced by new: spans and units moved"""
    ph, sp, un = ayah
    d = len(new) - (j - i)
    mv = lambda p, end=False: p if (p < j or (end and p <= i)) else p + d
    sp2 = [(p if p <= i else max(i, p + d) if p >= j else p) for p in sp]
    un2 = []
    for k in range(0, len(un), 5):
        kind, s, e, w, g = un[k:k + 5]
        if e <= i: un2 += [kind, s, e, w, g]
        elif s >= j: un2 += [kind, s + d, e + d, w, g]
    return [ph[:i] + new + ph[j:], sp2, un2]

def word_at(sp, i):
    return next(k for k in range(len(sp) // 2) if sp[2 * k] <= i < sp[2 * k + 1])

def places(ph, sp, rule):
    """(start, end, replacement) of every place the rule can be broken at"""
    n = len(ph)
    for i in range(n):
        c, p, q = ph[i], ph[i - 1] if i else '', ph[i + 1] if i + 1 < n else ''
        if rule == 'ikhfa_as_izhar' and c == 'ں' and p != 'ں':
            j = i
            while j < n and ph[j] == 'ں': j += 1
            yield i, j, 'ن'                       # read: ikhfa; text says a clear nun
        elif rule == 'izhar_as_ikhfa' and c == 'ن' and p in HAR and q in LETTERS - set('نمويلرب'):
            yield i, i + 1, 'ںںں'                 # read: a clear nun; text says ikhfa
        elif rule == 'no_qalqalah' and c in LETTERS and p in HAR and q in LETTERS and q != c and p != c:
            yield i + 1, i + 1, 'ڇ'               # read: no qalqalah; text has one
        elif rule == 'qalqalah_added' and c == 'ڇ':
            yield i, i + 1, ''                    # read: a qalqalah; text has none
        elif rule == 'madd_dropped' and c in HAR and q in LETTERS and p in LETTERS:
            yield i + 1, i + 1, LONG[c] * 2       # read: a short vowel; text has a natural madd
        elif rule == 'madd_added' and c in LONG.values() and p in HAR and ph[i:i + 2] == c * 2 and ph[i + 2:i + 3] != c and q:
            yield i, i + 2, ''                    # read: a natural madd; text has a short vowel
        elif rule == 'vowel_on_sukun' and c in HAR and p in LETTERS and q in LETTERS and i + 2 < n and ph[i + 2] in HAR:
            yield i, i + 1, ''                    # read: a vowel; text has a sukun
        elif rule == 'sukun_on_vowel' and c in LETTERS and p in HAR and q in LETTERS and q != c and p != c:
            yield i + 1, i + 1, 'َ'               # read: a sukun; text has a fatha
        elif rule == 'mim_ikhfa_as_izhar' and c == '۾' and p != '۾':
            j = i
            while j < n and ph[j] == '۾': j += 1
            yield i, j, 'م'                       # read: iqlab / hidden mim; text says a clear mim
        elif rule == 'mim_izhar_as_ikhfa' and c == 'م' and p in HAR and q in LETTERS - set('مب'):
            yield i, i + 1, '۾۾۾'                 # read: a clear mim; text says a hidden one
        elif rule == 'shadda_dropped' and c in LETTERS - set('نم') and p in HAR and q in HAR:
            yield i, i + 1, c * 2                 # read: one letter; text has a shadda
        elif rule == 'letter_added' and c in LETTERS and p in HAR and q in LETTERS and q != c and p != c:
            yield i, i + 1, ''                    # read: a letter more; text does not have it
        elif rule == 'no_sakt' and c == 'ۜ':
            yield i, i + 1, ''                    # read: a sakt; text has none
RULES = ['ikhfa_as_izhar', 'izhar_as_ikhfa', 'no_qalqalah', 'qalqalah_added', 'madd_dropped', 'madd_added',
         'vowel_on_sukun', 'sukun_on_vowel', 'mim_ikhfa_as_izhar', 'mim_izhar_as_ikhfa', 'shadda_dropped', 'no_sakt', 'letter_added']
os.makedirs(f'{out}/table', exist_ok=True); os.makedirs(f'{out}/cases', exist_ok=True)
shutil.copy(f'{assets}/mel_filters.bin', f'{out}/table/mel_filters.bin')
surahs, legend, made = {}, {}, {r: 0 for r in RULES}
metas = sorted(glob.glob(f'{src}/*.json'))
random.Random(7).shuffle(metas)
ident = 1000
ONLY = sys.argv[5].split(',') if len(sys.argv) > 5 else RULES
for rule_id, rule in enumerate(RULES, 10):
    if rule not in ONLY: continue
    legend[rule_id] = rule
    for path in metas:
        if made[rule] >= per: break
        m = json.load(open(path))
        if m.get('kind') not in ('whole', 'clean') or len(m['ayahs']) != 1: continue
        ayah = T['surahs'][str(m['surah'])][m['ayahs'][0] - 1]
        ph, sp, un = ayah
        if len(sp) < 4: continue
        # not in the first word (what is said before the first word is no mistake) nor on the ayah's last sound
        ok = [(i, j, new) for i, j, new in places(ph, sp, rule) if sp[1] <= i and j < len(ph) - 1]
        if not ok: continue
        i, j, new = ok[len(ok) // 2]
        ident += 1
        surahs[str(ident)] = [edit(ayah, i, j, new)]
        w = word_at(sp, min(i, len(ph) - 1)) if i < sp[-1] else len(sp) // 2 - 1
        name = f"{rule}-{os.path.basename(path)[:-5]}"
        json.dump(dict(surah=ident, ayahs=[1], miss=None, starts=[0] * (len(sp) // 2), kind='cut', rule=rule_id, word=w,
                       was=f"{m['surah']}:{m['ayahs'][0]} {ph[max(0, i - 3):j + 3]} → {surahs[str(ident)][0][0][max(0, i - 3):i + len(new) + 3]}"),
                  open(f'{out}/cases/{name}.json', 'w'), ensure_ascii=False)
        os.symlink(os.path.abspath(path[:-5] + '.wav'), f'{out}/cases/{name}.wav')
        made[rule] += 1
json.dump({'symbols': T['symbols'], 'surahs': surahs}, open(f'{out}/table/expected.json', 'w'), ensure_ascii=False)
json.dump(legend, open(f'{out}/legend.json', 'w'))
print(made)
