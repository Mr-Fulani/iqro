import assert from "node:assert/strict";
import test from "node:test";

import {
  READER_SWIPE_HINT_LIMIT,
  parseReaderSwipeHint,
  readerSwipeHintOpacity,
  readerSwipeHintPull,
} from "./reader-swipe-hint.ts";

test("the swipe hint pulls the text right, then left, and leaves it in place", () => {
  assert.equal(readerSwipeHintPull(0), 0);
  assert.equal(readerSwipeHintPull(0.3), 1);
  assert.equal(readerSwipeHintPull(0.5), 0);
  assert.equal(readerSwipeHintPull(0.75), -1);
  assert.equal(readerSwipeHintPull(1), 0);
  assert.ok(readerSwipeHintPull(0.15) > 0 && readerSwipeHintPull(0.15) < 1);
  assert.ok(readerSwipeHintPull(0.6) < 0 && readerSwipeHintPull(0.6) > -1);
});

test("the swipe hint fades in and out", () => {
  assert.equal(readerSwipeHintOpacity(0), 0);
  assert.equal(readerSwipeHintOpacity(0.5), 1);
  assert.equal(readerSwipeHintOpacity(1), 0);
});

test("a missing or malformed record means the swipe hint was never shown", () => {
  assert.equal(parseReaderSwipeHint(null), 0);
  assert.equal(parseReaderSwipeHint("x"), 0);
  assert.equal(parseReaderSwipeHint("-2"), 0);
  assert.equal(parseReaderSwipeHint("2"), 2);
  assert.equal(parseReaderSwipeHint(String(READER_SWIPE_HINT_LIMIT)), READER_SWIPE_HINT_LIMIT);
});
