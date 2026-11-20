"""The places of every tajweed rule in the expected sounds of all 6236 ayat, as the rule engine shipped with the
model (imam.py) finds them: how many, the counts expected, examples.   python units.py <model folder>"""
import json,sys,collections
sys.path.insert(0,sys.argv[1])  # the folder of the model's files (imam.py)
import imam
tab=json.load(open('table_text.json'))
c=collections.Counter(); ex=collections.defaultdict(list); gold=collections.defaultdict(collections.Counter)
allu={}
for s in tab:
    for i,a in enumerate(tab[s],1):
        ws=a.split(' ')
        try: ref=imam.expected(ws)
        except Exception as e:
            print('FAIL',s,i,e); continue
        us=[]
        for u in ref.units:
            k=u.kind if u.kind!='madd' else u.rule
            c[k]+=1; gold[k][u.golden]+=1
            if len(ex[k])<4: ex[k].append(f'{s}:{i} {ws[u.word]} [{ref.phonemes[max(0,u.s-2):u.e+2]}]')
            us.append([k,u.s,u.e,u.word,u.golden])
        allu[f'{s}:{i}']=[ref.phonemes,[list(x) for x in ref.spans],us]
json.dump(allu,open('units_all.json','w'),ensure_ascii=False)
for k,n in c.most_common(): print(k,n,dict(gold[k]),' | '.join(ex[k]))
