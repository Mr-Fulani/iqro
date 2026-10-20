import assert from "node:assert/strict";
import test from "node:test";

import { titleLines } from "./share-card.ts";

// Every character is 1 px wide.
const context = { measureText: (text: string) => ({ width: text.length }) as TextMetrics };

test("a short title is wrapped as it is", () => {
  assert.deepEqual(titleLines(context, "Аль-Бакара · 2:255", 40, 2), ["Аль-Бакара · 2:255"]);
});

test("a long du'a chapter loses words of its name, never its number", () => {
  const title = "Слова поминания, которые следует произносить человеку, испытывающему страх перед правителем · #69";
  const lines = titleLines(context, title, 40, 2);
  assert.equal(lines.length, 2);
  assert.ok(lines.every((line) => line.length <= 40), lines.join("|"));
  assert.match(lines.join(" "), /…\s·\s#69$/);
  assert.ok(lines.join(" ").startsWith("Слова поминания, которые следует"));
});
