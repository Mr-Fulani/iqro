import assert from "node:assert/strict";
import test from "node:test";

import { splitDuaArabic } from "./dua-arabic.ts";

// Cases of dua_arabic_test.dart.
test("each basmala before a surah gets its own line", () => {
  assert.deepEqual(
    splitDuaArabic(
      "بسم الله الرحمن الرحيم ﴿قُلْ هُوَ اللَّهُ أَحَدٌ﴾. "
        + "بسم الله الرحمن الرحيم ﴿قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ﴾",
    ),
    [
      { text: "بسم الله الرحمن الرحيم", opening: true },
      { text: "﴿قُلْ هُوَ اللَّهُ أَحَدٌ﴾", opening: false },
      { text: "بسم الله الرحمن الرحيم", opening: true },
      { text: "﴿قُلْ أَعُوذُ بِرَبِّ الْفَلَقِ﴾", opening: false },
    ],
  );
});

test("the isti'adha is found with full vowels", () => {
  const parts = splitDuaArabic(
    "أَعُوذُ بِاللَّهِ مِنَ الشَّيْطَانِ الرَّجِيمِ ﴿اللَّهُ لاَ إِلَهَ إِلاَّ هُوَ﴾",
  );
  assert.deepEqual(parts[0], { text: "أَعُوذُ بِاللَّهِ مِنَ الشَّيْطَانِ الرَّجِيمِ", opening: true });
  assert.deepEqual(parts.at(-1), { text: "﴿اللَّهُ لاَ إِلَهَ إِلاَّ هُوَ﴾", opening: false });
});

test("a du'a without a formula stays one line", () => {
  assert.deepEqual(splitDuaArabic("الْحَمْدُ لِلَّهِ"), [{ text: "الْحَمْدُ لِلَّهِ", opening: false }]);
});

test("a du'a that is only the basmala keeps the full size", () => {
  assert.deepEqual(splitDuaArabic("بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ"), [
    { text: "بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ", opening: false },
  ]);
});

test("the formula inside a sentence is not split off mid-word", () => {
  // «باسمك» is not the basmala.
  assert.equal(splitDuaArabic("بِاسْمِكَ اللَّهُمَّ أَمُوتُ وَأَحْيَا").length, 1);
});
