"""Writes what the on-device recitation follower needs besides the model, into assets/recitation_model/:

  expected.json    for every ayah: the sounds a correct Hafs recitation has (the model's phonetic script, the ayah
                   read alone and stopped on), where each word's sounds are, and the places of the three tajweed
                   rules the trial build remarks on (ghunnah, idgham with ghunnah, madd muttasil)
  mel_filters.bin  Whisper's 80 mel filters over 201 frequency bins, float32

  python build_table.py <folder of the model's files: config.json, imam.py> <output folder>

Needs: numpy faster-whisper quran-transcript levenshtein (imam.py imports them).
"""
import json, sys
import numpy as np

model_dir, out = sys.argv[1], sys.argv[2]
sys.path.insert(0, model_dir)
import imam  # noqa: E402  the rule engine shipped with the model
from quran_transcript import Aya  # noqa: E402
from faster_whisper.feature_extractor import FeatureExtractor  # noqa: E402

symbols = json.load(open(f'{model_dir}/config.json'))['phonemes']
KIND = {'ghunnah': 0, 'idgham_ghunnah': 1}
surahs, failed = {}, []
counts = [7, 286, 200, 176, 120, 165, 206, 75, 129, 109, 123, 111, 43, 52, 99, 128, 111, 110, 98, 135, 112, 78, 118,
          64, 77, 227, 93, 88, 69, 60, 34, 30, 73, 54, 45, 83, 182, 88, 75, 85, 54, 53, 89, 59, 37, 35, 38, 29, 18,
          45, 60, 49, 62, 55, 78, 96, 29, 22, 24, 13, 14, 11, 11, 18, 12, 12, 30, 52, 52, 44, 28, 28, 20, 56, 40, 31,
          50, 40, 46, 42, 29, 19, 36, 25, 22, 17, 19, 26, 30, 20, 15, 21, 11, 8, 8, 19, 5, 8, 8, 11, 11, 8, 3, 9, 5,
          4, 7, 3, 6, 3, 5, 4, 5, 6]
assert sum(counts) == 6236
for s, n in enumerate(counts, 1):
    ayat = []
    for a in range(1, n + 1):
        try:
            words = Aya(s, a).get().uthmani.split(' ')
            ref = imam.expected(words)
            units = []
            for u in ref.units:
                if u.kind in KIND: units += [KIND[u.kind], u.s, u.e, u.word, u.golden]
                elif u.kind == 'madd' and u.rule.startswith('Mottasel'): units += [2, u.s, u.e, u.word, u.golden]
            assert all(c in symbols for c in ref.phonemes)
            ayat.append([ref.phonemes, [x for span in ref.spans for x in span], units])
        except Exception as e:  # an ayah the phonetizer cannot write: the follower is not offered for its surah
            failed.append((s, a, repr(e)[:80])); ayat.append(None)
    surahs[str(s)] = ayat
    print(s, end=' ', flush=True)
json.dump({'symbols': symbols, 'surahs': surahs}, open(f'{out}/expected.json', 'w'), ensure_ascii=False, separators=(',', ':'))
FeatureExtractor(feature_size=80).mel_filters.astype('<f4').tofile(f'{out}/mel_filters.bin')
print('\nfailed:', failed)
