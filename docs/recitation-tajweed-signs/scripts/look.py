"""What the table of expected sounds holds for an ayah, word by word.   APP=clients/iqro_mobile python look.py 11:41 75:27 …"""
import json,sys,gzip
import os
R=os.environ['APP']+'/'  # clients/iqro_mobile
T=json.load(open(R+'assets/recitation_model/expected.json'))
app=json.load(gzip.open(R+'test/fixtures/quran_text_uthmani.json.gz'))
tab=json.load(open('table_text.json'))
def show(s,a,only=None):
    ph,sp,un=T['surahs'][str(s)][a-1]
    ws=tab[str(s)][a-1].split(' ')
    out=[]
    for k,w in enumerate(ws):
        if only and not any(o in w for o in only): continue
        out.append(f'{w}→{ph[sp[2*k]:sp[2*k+1]] or "∅"}')
    print(f'{s}:{a}', '  '.join(out), '| units',un if not only else '')
for arg in sys.argv[1:]:
    s,a,*o=arg.split(':'); show(int(s),int(a),o or None)
