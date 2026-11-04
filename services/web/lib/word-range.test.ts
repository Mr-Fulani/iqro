import assert from "node:assert/strict";
import test from "node:test";

import {
  ayahTextParts,
  parseWordKey,
  quranWords,
  wordKey,
  wordRangeBetween,
  wordRangeContains,
  wordRangeCount,
  wordRangeSpansAyahEnd,
  wordRangeBarPlace,
  WORD_RANGE_HANDLE_REACH,
} from "./word-range.ts";

test("a pause mark written apart belongs to the word before it", () => {
  const words = quranWords("ذَٰلِكَ ٱلْكِتَٰبُ لَا رَيْبَ ۛ فِيهِ ۛ هُدًى لِّلْمُتَّقِينَ");
  assert.equal(words.length, 7);
  assert.equal(words[3], "رَيْبَ ۛ");
});

test("the basmala before a first ayah carries no word positions", () => {
  const parts = ayahTextParts(2, 1, "بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ الٓمٓ");
  assert.deepEqual(parts.map((part) => part.words), [null, ["الٓمٓ"]]);
  // Al-Fatiha counts its basmala as the first ayah.
  assert.equal(ayahTextParts(1, 1, "بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ")[0].words?.length, 4);
});

test("a range is ordered, stays in one surah and spans ayah ends", () => {
  const range = wordRangeBetween({ surah: 1, ayah: 6, position: 2 }, { surah: 1, ayah: 5, position: 3 })!;
  assert.deepEqual(range.start, { surah: 1, ayah: 5, position: 3 });
  assert.equal(wordRangeContains(range, { surah: 1, ayah: 5, position: 4 }), true);
  assert.equal(wordRangeContains(range, { surah: 1, ayah: 6, position: 3 }), false);
  assert.equal(wordRangeSpansAyahEnd(range, 1, 5), true);
  assert.equal(wordRangeSpansAyahEnd(range, 1, 6), false);
  assert.equal(wordRangeBetween({ surah: 1, ayah: 7, position: 1 }, { surah: 2, ayah: 1, position: 1 }), null);
  // 1:5 has four words: two of them, then two of 1:6.
  assert.equal(wordRangeCount(range, () => 4), 4);
});

test("a word key round-trips and rejects other values", () => {
  assert.deepEqual(parseWordKey(wordKey({ surah: 2, ayah: 255, position: 7 })), { surah: 2, ayah: 255, position: 7 });
  assert.equal(parseWordKey("2:255"), null);
  assert.equal(parseWordKey(undefined), null);
});

test("the bar stands above the selected words, centred on them", () => {
  const place = wordRangeBarPlace({ top: 400, bottom: 440, left: 150, right: 250 }, { width: 400, height: 900 }, { width: 240, height: 52 });
  assert.ok(place.y + 52 <= 400);
  assert.equal(place.x + 120, 200);
});

test("the bar goes under words at the top, and keeps to the screen", () => {
  const under = wordRangeBarPlace({ top: 40, bottom: 80, left: 360, right: 396 }, { width: 400, height: 900 }, { width: 240, height: 52 });
  assert.ok(under.y >= 80 + WORD_RANGE_HANDLE_REACH);
  assert.ok(under.x + 240 <= 400 - 12);
});

test("the bar waits at the bottom while the words are off screen", () => {
  const size = { width: 400, height: 900 };
  const bar = { width: 240, height: 52 };
  assert.equal(wordRangeBarPlace(null, size, bar, { top: 0, bottom: 16 }).y, 900 - 16 - 12 - 52);
  assert.equal(wordRangeBarPlace({ top: -300, bottom: -260, left: 0, right: 100 }, size, bar).y, 900 - 12 - 52);
});
