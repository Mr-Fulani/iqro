"""Writes what the on-device recitation follower needs besides the model, into assets/recitation_model/:

  expected.json    for every ayah: the sounds a correct Hafs recitation has (the model's phonetic script, the ayah
                   read alone and stopped on), where each word's sounds are, and the places of the three tajweed
                   rules the trial build remarks on (ghunnah, idgham with ghunnah, madd muttasil)
                   A reader may stop on any word and go on from the next: the sounds a word has only when it is
                   stopped on, or only when read on from, or only when begun after a stop, are all written, and
                   listed as ones that need not be heard; those the ayah read through does not have are listed again
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


def runs(text):
    """The text as runs of one sound: (sound, how many)."""
    out = []
    for c in text:
        if out and out[-1][0] == c: out[-1][1] += 1
        else: out.append([c, 1])
    return out


def union(word, other):
    """`word`: [sound, count, needed, written in the ayah read through] runs; `other`: another way the word is said. Every sound of either, in order;
    one that only one of the two has need not be heard."""
    from difflib import SequenceMatcher
    b = runs(other)
    out = []
    for op, i1, i2, j1, j2 in SequenceMatcher(None, [r[0] for r in word], [r[0] for r in b], autojunk=False).get_opcodes():
        if op == 'equal': out += word[i1:i2]
        else:
            out += [[s, n, False, own] for s, n, _, own in word[i1:i2]]
            out += [[s, 1, False, False] for s, _ in b[j1:j2]]
    return out


def with_stops(words, ref):
    """The ayah's sounds with those of a stop after any word: (text, spans, old place -> new, places not needed,
    those of them that the ayah read through does not have)."""
    text, spans, place, loose, added = '', [], {}, [], []
    said = []
    for k, (s, e) in enumerate(ref.spans):
        word = [[c, n, True, True] for c, n in runs(ref.phonemes[s:e])]
        if k + 1 < len(words):  # stopped on
            r = imam.expected(words[max(0, k - 2):k + 1])
            word = union(word, r.phonemes[r.spans[-1][0]:r.spans[-1][1]])
        if k > 0:  # begun after a stop
            r = imam.expected(words[k:k + 3])
            word = union(word, r.phonemes[r.spans[0][0]:r.spans[0][1]])
        said.append(word)
    # A sound added at a word's edge that the word beside it has there too is that word's sound, held or said
    # again after the stop: written once, it is not taken from a place whose length is looked at.
    for a, b in zip(said, said[1:]):
        while a and b and not a[-1][3] and a[-1][0] == b[0][0]: a.pop()
        while a and b and not b[0][3] and b[0][0] == a[-1][0]: b.pop(0)
    for (s, e), word in zip(ref.spans, said):
        start, old = len(text), s
        for c, n, needed, own in word:
            if own:
                # (A place held is looked at only where its sounds are always said.)
                if needed:
                    for i in range(n): place[old + i] = len(text) + i
                old += n
            if not needed: loose += range(len(text), len(text) + n)
            if not own: added += range(len(text), len(text) + n)
            text += c * n
        assert old == e
        spans.append((start, len(text)))
    return text, spans, place, loose, added

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
            text, spans, place, loose, added = with_stops(words, ref)
            # The model writes the imala of 11:41 as a kasra and its long vowel: so it is written here, or a right
            # reading is stopped (docs/recitation-tajweed-signs).
            text = text.replace('۪', 'ِ').replace('ـ', 'ۦ')
            starts = [x for x, _ in ref.spans[1:]]
            units = []
            for u in ref.units:
                # The engine takes any long ي / و for a nun merged into it; the one of the letter ʿayn (19:1, 42:2)
                # lies within a word and is a madd, which may be read shorter.
                if u.kind == 'idgham_ghunnah' and not any(u.s <= x <= u.e for x in starts): continue
                # A place held is looked at only where every sound of it is always said.
                if any(i not in place for i in range(u.s, u.e)): continue
                at = [place[u.s], place[u.e - 1] + 1, u.word, u.golden]
                if u.kind in KIND: units += [KIND[u.kind], *at]
                elif u.kind == 'madd' and u.rule.startswith('Mottasel'): units += [2, *at]
            # Places of our own, by the counts the model writes (a letter doubled is written twice, a long vowel
            # once a count): 3 a letter with a shaddah, 4 a natural madd of two counts, 5 a nun said clearly
            # before a throat letter (izhar), which is not held. Only inside a word, and where every sound is
            # always said.
            ph, i = ref.phonemes, 0
            while i < len(ph):
                j = i
                while j < len(ph) and ph[j] == ph[i]: j += 1
                c, n = ph[i], j - i
                w = next(k for k, (s, e) in enumerate(ref.spans) if s <= i < e)
                if ref.spans[w][1] >= j and all(x in place for x in range(i, j)):
                    kind = None
                    # (4, a natural madd, is not written: the model, listening as the reader reads, writes one
                    # count of the two in one place of twenty of a right reading; out/16_tajweed_rules.txt.)
                    # (Nor 3, a letter with a shaddah, a run of two: read half as fast again, it is written once
                    # in a right reading, and the false stops of whole surahs went from 3 to 13.)
                    if n == 1 and c == 'ن' and j < len(ph) and ph[j] in 'ءهعحغخ': kind = 5
                    if kind: units += [kind, place[i], place[j - 1] + 1, w, n]
                i = j
            assert all(c in symbols for c in text)
            ayat.append([text, [x for span in spans for x in span], units, loose, added])
        except Exception as e:  # an ayah the phonetizer cannot write: the follower is not offered for its surah
            failed.append((s, a, repr(e)[:80])); ayat.append(None)
    surahs[str(s)] = ayat
    print(s, end=' ', flush=True)
json.dump({'symbols': symbols, 'surahs': surahs}, open(f'{out}/expected.json', 'w'), ensure_ascii=False, separators=(',', ':'))
FeatureExtractor(feature_size=80).mel_filters.astype('<f4').tofile(f'{out}/mel_filters.bin')
print('\nfailed:', failed)
