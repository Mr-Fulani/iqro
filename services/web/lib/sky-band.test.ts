import assert from "node:assert/strict";
import test from "node:test";

import {
  countdown,
  minutesInZone,
  nextStop,
  skyPalette,
  skyStart,
  skyTimeline,
  skyX,
  spreadLabels,
  wallMinutes,
} from "./sky-band.ts";

const times = {
  fajr: { local: "2026-11-06T05:52:00+03:00" },
  sunrise: { local: "2026-11-06T07:41:00+03:00" },
  dhuhr: { local: "2026-11-06T12:15:00+03:00" },
  asr: { local: "2026-11-06T14:18:00+03:00" },
  maghrib: { local: "2026-11-06T16:38:00+03:00" },
  isha: { local: "2026-11-06T18:22:00+03:00" },
};

test("the timeline reads the city's wall clock", () => {
  assert.equal(wallMinutes("2026-11-06T05:52:30+03:00"), 352.5);
  assert.deepEqual(skyTimeline(times), [352, 461, 735, 858, 998, 1102]);
  assert.equal(skyTimeline({ ...times, isha: undefined }), null);
  assert.equal(skyTimeline({ ...times, asr: { local: "2026-11-06T11:00:00+03:00" } }), null);
});

test("the next prayer skips sunrise and wraps to tomorrow's fajr", () => {
  const timeline = skyTimeline(times)!;
  assert.deepEqual(nextStop(timeline, 400), { index: 2, tomorrow: false });
  assert.deepEqual(nextStop(timeline, 788), { index: 3, tomorrow: false });
  assert.deepEqual(nextStop(timeline, 1300), { index: 0, tomorrow: true });
  assert.equal(countdown(timeline, 788), "1:10");
  assert.equal(countdown(timeline, 1300), "8:12");
});

test("the sky is night, dawn, day and sunset at the right moments", () => {
  const timeline = skyTimeline(times)!;
  assert.equal(skyPalette(timeline, 100).top, "rgb(6, 14, 35)");
  assert.equal(skyPalette(timeline, 400).horizon, "rgb(240, 160, 108)");
  assert.equal(skyPalette(timeline, 788).darkness, 1);
  assert.equal(skyPalette(timeline, 965).middle, "rgb(199, 96, 122)");
  assert.equal(skyPalette(timeline, 1300).stars, 1);
});

test("the sun starts below the horizon and the stops spread over the band", () => {
  const timeline = skyTimeline(times)!;
  assert.equal(skyStart(timeline, 788), 400);
  assert.equal(skyStart(timeline, 120), 30);
  assert.equal(skyX(timeline, 352, 361), 28);
  assert.equal(skyX(timeline, 1102, 361), 333);
  assert.equal(skyX(timeline, 461, 361, true), 28 + 305 / 5);
});

test("the clock is read in the schedule's time zone", () => {
  const moment = new Date("2026-11-06T10:08:00Z");
  assert.equal(minutesInZone("Europe/Moscow", moment), 13 * 60 + 8);
  assert.equal(minutesInZone("Asia/Tashkent", moment), 15 * 60 + 8);
});

test("close times keep their marks but spread their labels", () => {
  const spread = spreadLabels([28, 60, 180, 240, 300, 330], 361, 46);
  assert.deepEqual(spread, [28, 74, 180, 240, 293, 339]);
  for (let index = 1; index < spread.length; index++) assert.ok(spread[index] - spread[index - 1] >= 46 - 1e-9);
});
