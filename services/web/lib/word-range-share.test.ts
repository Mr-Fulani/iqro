import assert from "node:assert/strict";
import test from "node:test";

import { wordRangeShare, type AyahShareScript } from "./word-range-share.ts";

const ayahs = [
  { number: 285, text_uthmani: "ءَامَنَ ٱلرَّسُولُ بِمَآ أُنزِلَ" },
  { number: 286, text_uthmani: "لَا يُكَلِّفُ ٱللَّهُ نَفْسًا إِلَّا وُسْعَهَا ۚ لَهَا" },
];
const word = (ayah: number, position: number) => ({ surah: 2, ayah, position });

function share(start: [number, number], end: [number, number], scripts?: Map<number, AyahShareScript>) {
  return wordRangeShare({
    range: { start: word(...start), end: word(...end) },
    surahName: "Аль-Бакара",
    ayahs,
    partOf: (reference, several) => `${several ? "из аятов" : "из аята"} ${reference}`,
    plainFont: "plain",
    scripts,
    translations: new Map([[285, "Посланник уверовал"], [286, "Аллах не возлагает"]]),
  });
}
const drawn = (units: { text: string }[][]) => units.map((unit) => unit.map((piece) => piece.text).join("+"));

test("a part of an ayah has its words alone: no meaning, no end sign, and says it is a part", () => {
  const part = share([286, 1], [286, 5]);
  assert.equal(part.arabic, ayahs[1].text_uthmani.split(" ").slice(0, 5).join(" "));
  assert.deepEqual(drawn(part.units), part.arabic.split(" "));
  assert.equal(part.translation, "");
  assert.equal(part.title, "Аль-Бакара · из аята 2:286");
});

test("the last word of an ayah brings its end sign; a pause mark stays with its word", () => {
  const words = ayahs[1].text_uthmani.split(" ");
  const part = share([286, 6], [286, 7]);
  assert.deepEqual(drawn(part.units), [`${words[5]} ${words[6]}`, `${words[7]}+۝٢٨٦`]);
  assert.equal(part.arabic, words.slice(5).join(" "));
});

test("whole ayahs carry their meanings and both end signs", () => {
  const whole = share([285, 1], [286, 7]);
  assert.equal(whole.title, "Аль-Бакара · 2:285–286");
  assert.equal(whole.translation, "Посланник уверовал Аллах не возлагает");
  assert.equal(whole.arabic, ayahs.map((ayah) => ayah.text_uthmani).join(" "));
  assert.match(drawn(whole.units)[3], /\+۝٢٨٥$/);
  assert.match(drawn(whole.units).at(-1)!, /\+۝٢٨٦$/);
});

test("words across two ayahs say so; one whole ayah is as the ayah", () => {
  assert.equal(share([285, 3], [286, 2]).title, "Аль-Бакара · из аятов 2:285–286");
  const one = share([285, 1], [285, 4]);
  assert.equal(one.title, "Аль-Бакара · 2:285");
  assert.equal(one.translation, "Посланник уверовал");
});

test("the Mushaf's script is drawn when it has the words the reader counts, else the plain script", () => {
  const glyph = (text: string) => ({ text, fontFamily: "p49" });
  const script = { words: ["ﱁ", "ﱂ", "ﱃ", "ﱄ"].map(glyph), end: glyph("ﱅ") };
  const inScript = share([285, 3], [285, 4], new Map([[285, script]]));
  assert.deepEqual(drawn(inScript.units), ["ﱃ", "ﱄ+ﱅ"]);
  assert.equal(inScript.units[0][0].fontFamily, "p49");
  // The message keeps the plain text.
  assert.equal(inScript.arabic, ayahs[0].text_uthmani.split(" ").slice(2).join(" "));

  const mismatch = share([286, 1], [286, 2], new Map([[286, script]]));
  assert.deepEqual(mismatch.units.map((unit) => unit[0].fontFamily), ["plain", "plain"]);
});
