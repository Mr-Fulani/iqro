"""Every character of the Quran text the app shows (the test fixture of the text API) and of the text the table of
expected sounds is built from (quran-transcript): how often, in how many ayat, three examples. Also writes
table_text.json for units.py.   python census.py <repository>   (needs quran-transcript)"""
import gzip,json,sys,unicodedata,collections
R=sys.argv[1].rstrip('/')+'/'  # the repository
app=json.load(gzip.open(R+'clients/iqro_mobile/test/fixtures/quran_text_uthmani.json.gz'))
from quran_transcript import Aya
tab={}
for s in app:
    tab[s]=[Aya(int(s),a).get().uthmani for a in range(1,len(app[s])+1)]
json.dump(tab,open('table_text.json','w'),ensure_ascii=False)
def census(t):
    c=collections.Counter(); ex=collections.defaultdict(list); ay=collections.Counter()
    for s in t:
        for i,a in enumerate(t[s],1):
            seen=set()
            for w in a.split(' '):
                for ch in w:
                    c[ch]+=1
                    if ch not in seen:
                        seen.add(ch); ay[ch]+=1
                        if len(ex[ch])<3: ex[ch].append((f'{s}:{i}',w))
    return c,ex,ay
for name,t in (('APP',app),('TABLE',tab)):
    c,ex,ay=census(t)
    print('==',name, 'ayat',sum(len(v) for v in t.values()),'words',sum(len(a.split(' ')) for v in t.values() for a in v))
    for ch,n in sorted(c.items(), key=lambda x: ord(x[0])):
        print(f'U+{ord(ch):04X}\t{unicodedata.name(ch,"?")}\t{n}\t{ay[ch]}\t'+'; '.join(f'{k} {w}' for k,w in ex[ch]))
diff=[(s,i+1) for s in app for i in range(len(app[s])) if app[s][i]!=tab[s][i]]
print('differing ayat',len(diff),diff[:10])
for s,i in diff[:6]: print(app[s][i-1],'|',tab[s][i-1])
