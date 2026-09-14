import assert from "node:assert/strict";
import test from "node:test";
import { fitMushafLines, qulGridRow } from "./mushaf-line-layout.ts";

test("justification spans the row with unchanged glyph scale and centered short rows", () => {
  const lines = [
    { width: 200, height: 60, words: 5, centered: false },
    { width: 100, height: 60, words: 3, centered: true },
    { width: 80, height: 60, words: 1, centered: false },
  ];
  for (const width of [280, 400, 800]) {
    const fitted = fitMushafLines(lines, width, 40);
    assert.equal(fitted.scale, 2 / 3);
    assert.ok(Math.abs((200 + 4 * fitted.gaps[0]) * fitted.scale - width) < .001);
    assert.equal(fitted.gaps[1], 3.5);
    assert.equal(fitted.gaps[2], 3.5);
  }
});

test("opening blocks center including headings; normal pages retain all rows", () => {
  for (const count of [15, 16]) {
    for (const occupied of [7, 8]) {
      const first = qulGridRow(1, 1, count, occupied);
      const last = qulGridRow(occupied, 1, count, occupied) + 2;
      assert.equal(first - 1, 2 * count + 1 - last);
      assert.equal(qulGridRow(1, 3, count, count), 1);
    }
  }
});
