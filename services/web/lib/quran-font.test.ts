import assert from "node:assert/strict";
import test from "node:test";
import { isAllowedQuranFontUrl, isAllowedQuranWordImageUrl } from "./quran-font.ts";

test("provider fonts accept QF WOFF2 and the exact QPC Nastaleeq TTF", () => {
  assert.equal(isAllowedQuranFontUrl("https://verses.quran.foundation/fonts/quran/hafs/v2/woff2/p42.woff2"), true);
  assert.equal(isAllowedQuranFontUrl("https://static-cdn.tarteel.ai/qul/fonts/nastaleeq/KFGQPCNastaleeq-Regular.ttf"), true);
  for (const url of [undefined, "http://verses.quran.foundation/fonts/quran/font.woff2",
    "https://verses.quran.foundation.evil.test/fonts/quran/a.woff2",
    "https://user:password@verses.quran.foundation/fonts/quran/a.woff2",
    "https://static-cdn.tarteel.ai/unapproved.ttf",
    "https://verses.quran.foundation/fonts/quran/a.woff2?redirect=evil"]) {
    assert.equal(isAllowedQuranFontUrl(url), false, url);
  }
});

test("only official versioned word images and verse markers are allowed", () => {
  for (const family of ["qa-color", "rq-color", "qa-black"]) {
    assert.equal(isAllowedQuranWordImageUrl(`https://static.qurancdn.com/images/w/${family}/1/2/3.png?v=1`), true);
  }
  assert.equal(isAllowedQuranWordImageUrl("https://static.qurancdn.com/images/w/common/7.png?v=1"), true);
  for (const url of ["https://static.qurancdn.com/images/w/qa-color/1/2/3.png",
    "https://static.qurancdn.com/images/w/other/1/2/3.png?v=1",
    "https://user@static.qurancdn.com/images/w/common/7.png?v=1",
    "https://static.qurancdn.com/images/w/common/7.svg?v=1", "data:image/png;base64,abc"]) {
    assert.equal(isAllowedQuranWordImageUrl(url), false, url);
  }
});
