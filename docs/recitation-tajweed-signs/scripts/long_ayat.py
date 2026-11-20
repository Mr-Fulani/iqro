import sys,os
sys.path.insert(0,sys.argv[1])
from common import *
sess=session(threads=2)
for spec in sys.argv[2:]:
    f,find=spec.split('=')
    for r in sorted(os.listdir(AUDIO_DIR)):
        x=read_wav(f'{AUDIO_DIR}/{r}/{f}.wav'); out=''
        for a in range(0,len(x),20*16000):
            h,_,_=decode(logprobs(sess,x[a:a+24*16000])); out+=h+' | '
        i=out.find(find)
        print(f, r[:8], 'ٲ' in out, '۪' in out, 'ۜ' in out, 'ؙ' in out, out[max(0,i-12):i+25] if i>=0 else out[:0], flush=True)
