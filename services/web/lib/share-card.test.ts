import assert from "node:assert/strict";
import fs from "node:fs";
import test from "node:test";

import { composeShareCard, wrapWords } from "./share-card-compose.ts";
import {
  parseShareCardStyle,
  shareCardArabicUnits,
  shareCardLayout,
  shareCardLines,
  shareCardTranslationWords,
} from "./share-card.ts";

const specification = new URL("../../../docs/share-card/", import.meta.url);

test("the site carries the layout of the specification", () => {
  assert.deepEqual(shareCardLayout, JSON.parse(fs.readFileSync(new URL("layout.json", specification), "utf8")));
});

test("texts become the same cards as in the app", () => {
  const { cases } = JSON.parse(fs.readFileSync(new URL("fixtures.json", specification), "utf8"));
  for (const { name, format, arabic, translation, pages } of cases) {
    assert.deepEqual(composeShareCard(shareCardLayout, format, arabic, translation), pages, name);
  }
});

test("words wrap whole, and a word wider than the line gets a line of its own", () => {
  assert.deepEqual(wrapWords([30, 30, 30, 120, 10], 5, 100), [[0, 3], [3, 4], [4, 5]]);
  assert.deepEqual(wrapWords([], 5, 100), []);
});

test("a series holds every word once, in order; too long a text gives no card", () => {
  const words = (count: number) => ({ widths: Array.from({ length: count }, (_, index) => 1 + (index % 5) / 2), space: 0.25 });
  const arabic = words(140);
  const translation = words(280);
  const pages = composeShareCard(shareCardLayout, "story", arabic, translation)!;
  assert.ok(pages.length > 1 && pages.length <= shareCardLayout.maxCards);
  const indices = (lines: [number, number][]) => lines.flatMap(([start, end]) =>
    Array.from({ length: end - start }, (_, index) => start + index));
  assert.deepEqual(pages.flatMap((page) => indices(page.arabicLines)), arabic.widths.map((_, index) => index));
  assert.deepEqual(pages.flatMap((page) => indices(page.translationLines)), translation.widths.map((_, index) => index));
  assert.equal(composeShareCard(shareCardLayout, "post", words(2000), words(0)), null);
});

test("the card draws the words of the source, unchanged, the end sign with the last", () => {
  const arabic = "ٱللَّهُ لَآ إِلَٰهَ إِلَّا هُوَ ٱلْحَىُّ ٱلْقَيُّومُ";
  const units = shareCardArabicUnits(arabic, "۝٢٥٥", null);
  assert.deepEqual(units.at(-1)!.map((piece) => piece.text), ["ٱلْقَيُّومُ", "۝٢٥٥"]);
  assert.equal(units.map((unit) => unit[0].text).join(" "), arabic);
  const pages = composeShareCard(shareCardLayout, "story", { widths: units.map(() => 2), space: 0.25 }, { widths: [], space: 0 })!;
  assert.equal(
    pages.flatMap((page) => shareCardLines(units, page.arabicLines)).flat().map((unit) => unit[0].text).join(" "),
    arabic,
  );

  // The Mushaf's glyphs replace the plain words, and bring their own end sign.
  const loaded = [[{ text: "ﱁ", fontFamily: "p2" }], [{ text: "ﱂ", fontFamily: "p2" }, { text: "ﱃ", fontFamily: "p2" }]];
  assert.equal(shareCardArabicUnits(arabic, "\u06dd٢٥٥", loaded), loaded);
  assert.equal(shareCardArabicUnits(arabic, "\u06dd٢٥٥", []).length, 7);
  assert.deepEqual(shareCardTranslationWords("  Аллах — нет божества  "), ["«Аллах", "—", "нет", "божества»"]);
  assert.deepEqual(shareCardTranslationWords(" "), []);
});

test("the remembered style falls back to a story on emerald silk", () => {
  assert.deepEqual(parseShareCardStyle("post:midnight"), { format: "post", colour: "midnight" });
  assert.deepEqual(parseShareCardStyle("square:pink"), { format: "story", colour: "emerald" });
  assert.deepEqual(parseShareCardStyle(null), { format: "story", colour: "emerald" });
});
