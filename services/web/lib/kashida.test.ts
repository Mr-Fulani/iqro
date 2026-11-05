import assert from "node:assert/strict";
import test from "node:test";

import { kashidaLayout, kashidaSpots, TATWEEL } from "./kashida.ts";
import { quranWords } from "./word-range.ts";

test("a kashida goes between joined letters, after their marks", () => {
  // نَادَىٰ: nun joins alef; alef joins nothing after it.
  assert.deepEqual(kashidaSpots("نَادَىٰ"), [2]);
  // رَبِّكَ: ra joins nothing; ba joins kaf after its shadda and kasra.
  assert.deepEqual(kashidaSpots("رَبِّكَ"), [5]);
});

test("never inside lam-alef nor in the name of Allah", () => {
  assert.deepEqual(kashidaSpots("لَا"), []);
  assert.deepEqual(kashidaSpots("ٱللَّهِ"), []);
  assert.deepEqual(kashidaSpots("وَٱللَّهُ"), []);
  assert.deepEqual(kashidaSpots("بِٱللَّهِ"), []);
  assert.deepEqual(kashidaSpots("﴿٥﴾"), []);
});

// A stand-in font: every letter 10 wide, a tatweel 6, a space 4, marks none.
function measure(text: string) {
  let width = 0;
  for (const ch of text) {
    if (ch === " " || ch === " ") width += 4;
    else if (ch === TATWEEL) width += 6;
    else if (!/[ً-ٰٟۖ-ۭ]/.test(ch)) width += 10;
  }
  return width;
}

test("every line but the last reaches the edge and none goes past it", () => {
  const words = quranWords("وَإِنِّى خِفْتُ ٱلْمَوَٰلِىَ مِن وَرَآءِى وَكَانَتِ ٱمْرَأَتِى عَاقِرًا فَهَبْ لِى مِن لَّدُنكَ وَلِيًّا");
  for (const width of [160, 260, 380]) {
    const layout = kashidaLayout(words, width, measure, { marker: " ﴿٥﴾", fontSize: 40 });
    assert.deepEqual(layout.words.map((word) => word.replaceAll(TATWEEL, "")), words);
    let start = 0;
    const lines: string[][] = [];
    words.forEach((_, i) => {
      if (layout.breaks.has(i) || i === words.length - 1) {
        lines.push(layout.words.slice(start, i + 1));
        start = i + 1;
      }
    });
    lines.forEach((line, index) => {
      const last = index === lines.length - 1;
      const lineWidth = measure(line.join(" ") + (last ? " ﴿٥﴾" : ""));
      assert.ok(lineWidth <= width, `${width}: ${lineWidth}`);
      if (!last && line.some((word) => kashidaSpots(word.replaceAll(TATWEEL, "")).length)) {
        assert.ok(lineWidth > width - 7, `${width}: line ${index} is ${lineWidth}`);
      }
    });
  }
});
