import assert from "node:assert/strict";
import test from "node:test";

import { mushafPageRuns, nextPlayerSpeed } from "./mushaf-page-runs.ts";

const page = ["4:175", "4:176", "5:1", "5:2"];

test("the play button reads the page by surah runs from the chosen ayah, as the app's", () => {
  assert.deepEqual(mushafPageRuns(page), [
    { surah: 4, start: 175, end: 176 },
    { surah: 5, start: 1, end: 2 },
  ]);
  assert.deepEqual(mushafPageRuns(page, "4:176"), [
    { surah: 4, start: 176, end: 176 },
    { surah: 5, start: 1, end: 2 },
  ]);
  assert.deepEqual(mushafPageRuns(page, "5:2"), [{ surah: 5, start: 2, end: 2 }]);
  // An ayah from another page starts at the top of this one.
  assert.equal(mushafPageRuns(page, "9:1").length, 2);
  assert.deepEqual(mushafPageRuns([]), []);
});

test("the speed button steps through the Audio player's speeds", () => {
  assert.deepEqual([1, 1.25, 1.5, 2, 0.75].map(nextPlayerSpeed), [1.25, 1.5, 2, 0.75, 1]);
  assert.equal(nextPlayerSpeed(1.75), 1);
});
