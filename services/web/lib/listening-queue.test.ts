import assert from "node:assert/strict";
import test from "node:test";
import {
  SURAH_COUNT,
  adjacentQueueSurah,
  heldSurahs,
  nearestHeldSurah,
  parseListeningSnapshot,
  queueRows,
  serializeListeningSnapshot,
  stepSurah,
  surahAfter,
  wholeQuranMode,
} from "./listening-queue.ts";
import type { ListeningSnapshot } from "./listening-queue.ts";

// A partial recording: Al-Fatiha, Ya-Sin and the 30th juz.
const PARTIAL = [1, 36, ...Array.from({ length: 37 }, (_, index) => 78 + index)];

test("a recording holds its listed surahs in order, and the whole Quran when the list is missing", () => {
  assert.deepEqual(heldSurahs([36, 1, 36, 0, 115, 2.5]), [1, 36]);
  assert.equal(heldSurahs(undefined).length, SURAH_COUNT);
  assert.equal(heldSurahs([]).length, SURAH_COUNT);
});

test("after a surah the queue stops, moves on to the next held surah, or loops", () => {
  assert.equal(surahAfter(PARTIAL, 36, "stop"), null);
  assert.equal(surahAfter(PARTIAL, 1, "next"), 36);
  assert.equal(surahAfter(PARTIAL, 36, "next"), 78);
  assert.equal(surahAfter(PARTIAL, 114, "next"), null);
  assert.equal(surahAfter(PARTIAL, 114, "loop"), 1);
  assert.equal(surahAfter([36], 36, "loop"), 36);
  assert.equal(surahAfter(heldSurahs([]), 2, "next"), 3);
});

test("the previous and next buttons skip missing surahs and cross the ends only in the loop mode", () => {
  assert.equal(adjacentQueueSurah(PARTIAL, 78, -1, "next"), 36);
  assert.equal(adjacentQueueSurah(PARTIAL, 1, -1, "next"), null);
  assert.equal(adjacentQueueSurah(PARTIAL, 1, -1, "loop"), 114);
  assert.equal(adjacentQueueSurah(PARTIAL, 114, 1, "stop"), null);
  assert.equal(adjacentQueueSurah(PARTIAL, null, 1, "next"), null);
  assert.equal(stepSurah([], 1, 1, true), null);
});

test("switching recordings keeps the surah when it is held, else the next one, else the last", () => {
  assert.equal(nearestHeldSurah(PARTIAL, 36), 36);
  assert.equal(nearestHeldSurah(PARTIAL, 2), 36);
  assert.equal(nearestHeldSurah([1, 36], 50), 36);
  assert.equal(nearestHeldSurah([], 50), null);
});

test("the queue list folds each run of missing surahs into one row", () => {
  assert.deepEqual(queueRows([1, 3, 114]), [
    { kind: "surah", surah: 1 },
    { kind: "gap", from: 2, to: 2 },
    { kind: "surah", surah: 3 },
    { kind: "gap", from: 4, to: 113 },
    { kind: "surah", surah: 114 },
  ]);
  assert.deepEqual(queueRows([2, 3]).at(-1), { kind: "gap", from: 4, to: 114 });
  assert.equal(queueRows(heldSurahs([])).every((row) => row.kind === "surah"), true);
});

test("playing the whole Quran turns the stop mode into moving on", () => {
  assert.equal(wholeQuranMode("stop"), "next");
  assert.equal(wholeQuranMode("loop"), "loop");
});

test("the saved place survives a round trip and rejects what it cannot use", () => {
  const snapshot: ListeningSnapshot = {
    queue: {
      reciterId: "reciter",
      artist: "Abdul Basit",
      artworkUrl: null,
      variantId: "murattal",
      variants: [
        { id: "murattal", label: "Murattal · Hafs", editionCode: "madani-hafs", surahNumbers: [] },
        { id: "mujawwad", label: "Mujawwad · Hafs", editionCode: "madani-hafs", surahNumbers: [1, 36] },
      ],
    },
    surah: 36,
    positionMs: 401_250,
    mode: "loop",
    savedAt: "2026-10-25T20:00:00.000Z",
  };
  assert.deepEqual(parseListeningSnapshot(serializeListeningSnapshot(snapshot)), snapshot);

  const raw = JSON.parse(serializeListeningSnapshot(snapshot));
  assert.equal(parseListeningSnapshot(null), null);
  assert.equal(parseListeningSnapshot("{"), null);
  assert.equal(parseListeningSnapshot(JSON.stringify({ ...raw, v: 2 })), null);
  assert.equal(parseListeningSnapshot(JSON.stringify({ ...raw, surah: 115 })), null);
  assert.equal(
    parseListeningSnapshot(JSON.stringify({ ...raw, queue: { ...raw.queue, variantId: "gone" } })),
    null,
  );
  const repaired = parseListeningSnapshot(JSON.stringify({ ...raw, mode: "shuffle", positionMs: -5 }));
  assert.equal(repaired?.mode, "next");
  assert.equal(repaired?.positionMs, 0);
});
