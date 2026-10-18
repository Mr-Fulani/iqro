import assert from "node:assert/strict";
import test from "node:test";
import { syntheticHeadingFont } from "../e2e/truetype-fixture.ts";
import { readTrueTypeGlyph, SURAH_HEADER_FONT_SHA256, SURAH_HEADER_FONT_URL } from "./surah-header.ts";

test("reads quadratic TrueType outlines as SVG path data with y pointing down", () => {
  const font = new DataView(syntheticHeadingFont().buffer);
  assert.deepEqual(readTrueTypeGlyph(font, 1), {
    d: "M0 0L200 0Q200 -100 0 -100L0 0Z",
    viewBox: "0 -100 200 100",
  });
  assert.equal(readTrueTypeGlyph(font, 0), null);
  assert.equal(readTrueTypeGlyph(font, 2), null);
});

test("a contour filter keeps only the accepted contours and their bounds", () => {
  const font = new DataView(syntheticHeadingFont().buffer);
  assert.equal(readTrueTypeGlyph(font, 1, () => false), null);
  assert.deepEqual(readTrueTypeGlyph(font, 1, () => true), {
    d: "M0 0L200 0Q200 -100 0 -100L0 0Z",
    viewBox: "0 -100 200 100",
  });
});

test("the site pins the same heading font as the backend", async () => {
  const { readFile } = await import("node:fs/promises");
  const backend = (await readFile(
    new URL("../../backend/src/quran_backend/modules/quran/surah_header.py", import.meta.url),
    "utf8",
  )).replace(/"\s*\n\s*"/g, "");
  assert.ok(backend.includes(SURAH_HEADER_FONT_URL));
  assert.ok(backend.includes(SURAH_HEADER_FONT_SHA256));
});
