import assert from "node:assert/strict";
import test from "node:test";
import { formatClock, formatTrackDuration } from "./audio-content.ts";

test("a recording under an hour reads minutes and seconds", () => {
  assert.equal(formatClock(9 * 60_000 + 44_000), "9:44");
  assert.equal(formatClock(0), "0:00");
});

test("a recording of an hour or more keeps its hours, as in the app", () => {
  assert.equal(formatClock((117 * 60 + 34) * 1_000), "1:57:34");
  assert.equal(formatTrackDuration((69 * 60 + 32) * 1_000, "ru"), "1:09:32");
});
