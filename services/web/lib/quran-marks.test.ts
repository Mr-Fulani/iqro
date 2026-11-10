import assert from "node:assert/strict";
import test from "node:test";

import { quarterMarkMessage, quarterStartingIn, type QuarterStart } from "./quran-marks.ts";

const quarter = (number: number, surah: number, ayah: number): QuarterStart => ({
  number,
  hizb_number: Math.floor((number - 1) / 4) + 1,
  quarter_number: ((number - 1) % 4) + 1,
  start_ayah: { surah, number: ayah },
});

// Hizb 9 as in the Madani Mushaf: its half starts at 4:58 on page 87.
const quarters = [quarter(33, 4, 24), quarter(34, 4, 36), quarter(35, 4, 58), quarter(36, 4, 74)];

test("finds the quarter that starts on a page", () => {
  assert.equal(quarterStartingIn(quarters, ["4:52", "4:57", "4:58", "4:59"])?.number, 35);
  assert.equal(quarterStartingIn(quarters, ["4:59", "4:60"]), null);
  assert.equal(quarterStartingIn([], ["4:58"]), null);
});

test("labels a new juz, a new hizb and the quarters of a hizb", () => {
  assert.deepEqual(quarterMarkMessage(quarter(33, 4, 24)), { key: "quran.markJuz", variables: { juz: 5 } });
  assert.deepEqual(quarterMarkMessage(quarter(37, 4, 88)), { key: "quran.markHizb", variables: { hizb: 10 } });
  assert.deepEqual(quarterMarkMessage(quarter(34, 4, 36)), { key: "quran.markQuarter", variables: { hizb: 9 } });
  assert.deepEqual(quarterMarkMessage(quarter(35, 4, 58)), { key: "quran.markHalf", variables: { hizb: 9 } });
  assert.deepEqual(quarterMarkMessage(quarter(36, 4, 74)), { key: "quran.markThreeQuarters", variables: { hizb: 9 } });
});
