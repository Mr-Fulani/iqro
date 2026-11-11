import assert from "node:assert/strict";
import test from "node:test";
import type { QuranFoundationMushafPage } from "./api";
import { mushafAyahScript, mushafPageEnds, readerDigits, selectedMushaf } from "./mushaf-script.ts";

function page(number: number, mode: string, words: [string, string, string][]): QuranFoundationMushafPage {
  return {
    page_number: number,
    rendering: { available: true, mode },
    words: words.map(([verse_key, char_type_name, text], index) => ({
      id: number * 100 + index, verse_key, char_type_name, text, css_class: "", position_in_page: index + 1,
    })),
  } as unknown as QuranFoundationMushafPage;
}

test("an ayah over two pages takes its words from both page fonts, and its end sign", () => {
  const loaded = new Map([
    [2, page(2, "page-font", [["2:1", "word", "a"], ["2:1", "end", "1"], ["2:2", "word", "b"]])],
    [3, page(3, "page-font", [["2:2", "word", "c"], ["2:2", "end", "2"], ["2:3", "word", "d"]])],
  ]);
  const script = mushafAyahScript(19, [2, 3], loaded, "2:2", 2);
  assert.deepEqual(script?.words.map((word) => word.text), ["b", "c"]);
  assert.equal(script?.words[0].fontFamily, "qf-mushaf-19-page-2");
  assert.equal(script?.words[1].fontFamily, "qf-mushaf-19-page-3");
  assert.equal(script?.end?.text, "2");
});

test("the plain text stays while a page loads, for word images and when the words differ", () => {
  const font = page(2, "unicode-font", [["2:1", "word", "a"], ["2:1", "end", "1"]]);
  assert.equal(mushafAyahScript(5, [2, 3], new Map([[2, font]]), "2:1", 1), null);
  assert.equal(mushafAyahScript(5, undefined, new Map([[2, font]]), "2:1", 1), null);
  assert.equal(mushafAyahScript(5, [2], new Map([[2, font]]), "2:1", 2), null);
  const images = page(2, "word-images", [["2:1", "word", "a"]]);
  assert.equal(mushafAyahScript(10, [2], new Map([[2, images]]), "2:1", 1), null);
  assert.equal(mushafAyahScript(5, [2], new Map([[2, font]]), "2:1", 1)?.words[0].fontFamily, "qf-mushaf-5");
});

test("a page ends before the first ayah of the next page", () => {
  assert.deepEqual(mushafPageEnds([1, 1, 2, 2, 4, undefined, 5]), [null, null, 1, null, 3, null, null]);
});

test("numbers beside the interface use the digits its reader knows", () => {
  assert.equal(readerDigits("ru", 255), "255");
  assert.equal(readerDigits("ar", 1255), "١٢٥٥");
});

test("the readers draw with the picked Mushaf, else KFGQPC Hafs, else the first that can be drawn", () => {
  const mushaf = (source_id: number, mode = "page-font", available = true) => ({ source_id, rendering: { available, mode } });
  const all = [mushaf(1), mushaf(5, "unicode-font"), mushaf(19)];
  assert.equal(selectedMushaf(all, 19)?.source_id, 19);
  assert.equal(selectedMushaf(all, null)?.source_id, 5);
  // A pick that is gone or cannot be drawn falls back.
  assert.equal(selectedMushaf(all, 7)?.source_id, 5);
  assert.equal(selectedMushaf([mushaf(1), mushaf(19, "page-font", false)], 19)?.source_id, 1);
  assert.equal(selectedMushaf([mushaf(3, "glyph-codes")], 3), null);
});
