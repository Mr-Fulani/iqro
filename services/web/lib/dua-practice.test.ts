import assert from "node:assert/strict";
import test from "node:test";

import {
  advanceRepetitionCount,
  duaRepetitionStages,
  duaRepetitionTotal,
  nextPlaybackSpeed,
} from "./dua-practice.ts";

// Cases of dua_presentation_test.dart.
test("repetition labels become stages", () => {
  assert.deepEqual(duaRepetitionStages("33 · 33 · 34", 33), [33, 33, 34]);
  assert.deepEqual(duaRepetitionStages("3 / 7", 1), [3, 7]);
  assert.equal(duaRepetitionTotal("33 · 33 · 34", 33), 100);
});

test("malformed or excessive repetition labels fall back safely", () => {
  assert.deepEqual(duaRepetitionStages("33 times", 3), [3]);
  assert.deepEqual(duaRepetitionStages("1001 · 2", 4), [4]);
  assert.deepEqual(duaRepetitionStages("", 0), [1]);
});

test("a finished count starts again on the next tap", () => {
  assert.equal(advanceRepetitionCount(0, 3), 1);
  assert.equal(advanceRepetitionCount(2, 3), 3);
  assert.equal(advanceRepetitionCount(3, 3), 0);
});

test("speed steps 1, 1.25, 1.5, 0.75 and back, as in the app", () => {
  assert.deepEqual([1, 1.25, 1.5, 0.75].map(nextPlaybackSpeed), [1.25, 1.5, 0.75, 1]);
  assert.equal(nextPlaybackSpeed(2), 1);
});
