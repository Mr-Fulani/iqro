import assert from "node:assert/strict";
import test from "node:test";
import { syntheticHeadingFont } from "../e2e/truetype-fixture.ts";
import { readTrueTypeGlyph } from "./surah-header.ts";

test("reads quadratic TrueType outlines as SVG path data with y pointing down", () => {
  const font = new DataView(syntheticHeadingFont().buffer);
  assert.deepEqual(readTrueTypeGlyph(font, 1), {
    d: "M0 0L200 0Q200 -100 0 -100L0 0Z",
    viewBox: "0 -100 200 100",
  });
  assert.equal(readTrueTypeGlyph(font, 0), null);
  assert.equal(readTrueTypeGlyph(font, 2), null);
});
