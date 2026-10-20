import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  calculateForCivilDate,
  calculatePrayerMonth,
  calculatePrayerTimes,
  LOCAL_PRAYER_ENGINE_ID,
  LOCAL_PRAYER_ENGINE_VERSION,
  LocalPrayerCalculationUnavailable,
  localPrayerMethod,
  PRAYER_CODES,
  prayerCalendarDates,
} from "./prayer-engine.ts";
import type { LocalPrayerMethod } from "./prayer-engine.ts";
import { headingFromOrientation, qiblaBearing } from "./qibla.ts";

type BackendFixture = {
  cases: Array<{
    id: string;
    date: string;
    latitude: number;
    longitude: number;
    high_latitude_rule: string;
    polar_resolution: string;
    expected_utc: Record<string, string>;
    expected_fallback?: { reference_date?: string };
  }>;
};

type AppParityFixture = {
  methods: Record<
    string,
    {
      fajr_angle: number;
      isha_angle: number | null;
      isha_interval_minutes: number | null;
      adjustments: Record<string, number>;
    }
  >;
  cases: Array<{
    id: string;
    lat: number;
    lng: number;
    tz: string;
    method: string;
    month: string;
    hanafi?: boolean;
    rule?: string;
    polar?: string;
    adjustments?: Record<string, number>;
    qibla: number;
    utc_minutes: number[][];
  }>;
};

const mwl: LocalPrayerMethod = {
  code: "muslim-world-league",
  fajrAngle: 18,
  ishaAngle: 17,
  ishaIntervalMinutes: null,
  adjustments: { dhuhr: 1 },
};

const backendFixture = JSON.parse(
  readFileSync(
    new URL("../../backend/tests/fixtures/prayer_times/adhan_js_4_4_4.json", import.meta.url),
    "utf8",
  ),
) as BackendFixture;

const appFixture = JSON.parse(
  readFileSync(new URL("./prayer-engine.app-parity.json", import.meta.url), "utf8"),
) as AppParityFixture;

for (const testCase of backendFixture.cases) {
  test(`matches pinned Adhan 4.4.4: ${testCase.id}`, () => {
    const result = calculatePrayerTimes({
      latitude: testCase.latitude,
      longitude: testCase.longitude,
      date: testCase.date,
      method: mwl,
      highLatitudeRule: testCase.high_latitude_rule,
      polarResolution: testCase.polar_resolution,
    });
    for (const [code, expected] of Object.entries(testCase.expected_utc)) {
      const delta = Math.abs(result.timesUtc[code as keyof typeof result.timesUtc] - Date.parse(expected));
      assert.ok(delta <= 1000, `${code}: ${delta} ms`);
    }
    assert.equal(result.fallback.applied, Boolean(testCase.expected_fallback));
    assert.equal(result.fallback.referenceDate, testCase.expected_fallback?.reference_date);
  });
}

for (const testCase of appFixture.cases) {
  test(`month matches the app engine to the minute: ${testCase.id}`, () => {
    const method = appFixture.methods[testCase.method];
    const [year, month] = testCase.month.split("-").map(Number);
    const days = calculatePrayerMonth(
      {
        latitude: testCase.lat,
        longitude: testCase.lng,
        method: {
          code: testCase.method,
          fajrAngle: method.fajr_angle,
          ishaAngle: method.isha_angle,
          ishaIntervalMinutes: method.isha_interval_minutes,
          adjustments: method.adjustments,
        },
        highLatitudeRule: testCase.rule ?? "middle_of_night",
        polarResolution: testCase.polar ?? "unresolved",
        hanafiAsr: testCase.hanafi === true,
        adjustments: testCase.adjustments,
      },
      testCase.tz,
      year,
      month,
    );
    assert.equal(days.length, testCase.utc_minutes.length);
    days.forEach((day, index) => {
      assert.deepEqual(
        PRAYER_CODES.map((code) => Math.floor(day.timesUtc[code] / 60_000)),
        testCase.utc_minutes[index],
        day.date,
      );
    });
    const bearing = qiblaBearing(testCase.lat, testCase.lng);
    assert.ok(bearing !== null && Math.abs(bearing - testCase.qibla) < 1e-6);
  });
}

test("aligns the astronomical date to the requested civil date", () => {
  const { result, astronomicalDate } = calculateForCivilDate(
    {
      latitude: 1.8721,
      longitude: -157.4278,
      date: "2026-08-09",
      method: mwl,
      highLatitudeRule: "middle_of_night",
      polarResolution: "unresolved",
    },
    "Pacific/Kiritimati",
  );
  const localNoon = new Intl.DateTimeFormat("en-CA", { timeZone: "Pacific/Kiritimati" }).format(
    result.timesUtc.dhuhr,
  );
  assert.equal(localNoon, "2026-08-09");
  assert.equal(astronomicalDate, "2026-08-08");
});

test("rejects an unresolved polar day", () => {
  assert.throws(
    () =>
      calculatePrayerTimes({
        latitude: 69.6492,
        longitude: 18.9553,
        date: "2026-06-21",
        method: mwl,
        highLatitudeRule: "seventh_of_night",
        polarResolution: "unresolved",
      }),
    (error: unknown) =>
      error instanceof LocalPrayerCalculationUnavailable &&
      error.reason === "polar_sunrise_or_sunset_unresolved",
  );
});

test("applies Hanafi Asr and manual minute adjustments independently", () => {
  const base = {
    latitude: 41.0082,
    longitude: 28.9784,
    date: "2026-08-09",
    method: mwl,
    highLatitudeRule: "middle_of_night",
    polarResolution: "unresolved",
  };
  const standard = calculatePrayerTimes(base);
  const customized = calculatePrayerTimes({ ...base, hanafiAsr: true, adjustments: { fajr: 7 } });
  assert.equal(customized.timesUtc.fajr - standard.timesUtc.fajr, 7 * 60_000);
  assert.ok(customized.timesUtc.asr > standard.timesUtc.asr);
  assert.equal(customized.timesUtc.dhuhr, standard.timesUtc.dhuhr);
});

test("lists every civil date of the month", () => {
  assert.equal(prayerCalendarDates(2028, 2).length, 29);
  assert.equal(prayerCalendarDates(2026, 2).at(-1), "2026-02-28");
  assert.equal(prayerCalendarDates(2026, 10)[0], "2026-10-01");
});

test("reads only methods the pinned engine can reproduce", () => {
  const catalog = {
    algorithm: { id: LOCAL_PRAYER_ENGINE_ID, version: LOCAL_PRAYER_ENGINE_VERSION },
    methods: [
      {
        id: "mwl",
        code: "muslim-world-league",
        available: true,
        parameters: {
          fajr_angle: "18.00",
          isha: { angle: "17.00", interval_minutes: null },
          method_adjustments: { fajr: 0, sunrise: 0, dhuhr: 1, asr: 0, maghrib: 0, isha: 0 },
        },
      },
      { id: "bare", code: "bare", available: true },
    ],
  };
  assert.deepEqual(localPrayerMethod(catalog, "mwl"), {
    code: "muslim-world-league",
    fajrAngle: 18,
    ishaAngle: 17,
    ishaIntervalMinutes: null,
    adjustments: { fajr: 0, sunrise: 0, dhuhr: 1, asr: 0, maghrib: 0, isha: 0 },
  });
  assert.equal(localPrayerMethod(catalog, "bare"), null);
  assert.equal(
    localPrayerMethod({ ...catalog, algorithm: { id: LOCAL_PRAYER_ENGINE_ID, version: "5.0.0" } }, "mwl"),
    null,
  );
});

test("Qibla bearing is a normalized geographic bearing", () => {
  const london = qiblaBearing(51.5074, -0.1278);
  const newYork = qiblaBearing(40.7128, -74.006);
  assert.ok(london !== null && Math.abs(london - 118.99) < 0.15);
  assert.ok(newYork !== null && Math.abs(newYork - 58.48) < 0.15);
  assert.equal(qiblaBearing(100, 0), null);
  assert.equal(qiblaBearing(Number.NaN, 0), null);
});

test("compass heading uses only absolute orientation", () => {
  assert.equal(headingFromOrientation({ alpha: 90, absolute: true }), 270);
  assert.equal(headingFromOrientation({ alpha: 90, absolute: true }, 90), 0);
  assert.equal(headingFromOrientation({ alpha: 90, absolute: false }), null);
  assert.equal(headingFromOrientation({ alpha: null, absolute: true }), null);
  assert.equal(headingFromOrientation({ alpha: 10, webkitCompassHeading: 45 }), 45);
});
