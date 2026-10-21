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
import { isValidPrayerAdjustment, isValidPrayerDate } from "./prayer-input.ts";
import { magneticDeclination } from "./geomag.ts";
import {
  angleDifference,
  compassReadingFromOrientation,
  distanceToKaabaMeters,
  facesQibla,
  HeadingSmoother,
  headingFromOrientation,
  headingFromRotationMatrix,
  qiblaBearing,
  rotationMatrixFromOrientation,
} from "./qibla.ts";

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

const assertAngle = (actual: number | null, expected: number) =>
  assert.ok(
    actual !== null && Math.abs(angleDifference(actual, expected)) < 1e-9,
    `expected ${expected}°, got ${actual}°`,
  );

test("compass heading uses only absolute orientation", () => {
  assertAngle(headingFromOrientation({ alpha: 90, absolute: true }), 270);
  assertAngle(headingFromOrientation({ alpha: 90, absolute: true }, 90), 0);
  assertAngle(headingFromOrientation({ alpha: 0, absolute: true }, 270), 270);
  assert.equal(headingFromOrientation({ alpha: 90, absolute: false }), null);
  assert.equal(headingFromOrientation({ alpha: null, absolute: true }), null);
  assert.equal(headingFromOrientation({ alpha: 10, webkitCompassHeading: 45 }), 45);
  assert.equal(headingFromOrientation({ alpha: 10, webkitCompassHeading: -1 }), null);
});

test("compass heading of the screen top survives tilt, as in the app", () => {
  // Pitch and roll leave the projected top edge in place; upright, the back of the phone leads.
  assertAngle(headingFromOrientation({ alpha: 30, beta: 60, gamma: -40, absolute: true }), 330);
  assertAngle(headingFromOrientation({ alpha: 30, beta: 90, gamma: 0, absolute: true }), 330);
  // The same matrix layout as Android's SensorManager: a phone lying flat with its top east.
  const flatEast = rotationMatrixFromOrientation(270, 0, 0);
  assertAngle(headingFromRotationMatrix(flatEast), 90);
  assert.equal(headingFromRotationMatrix([1, 2, 3]), null);
});

test("compass readings move to true north and flag iOS calibration", () => {
  const android = compassReadingFromOrientation({ alpha: 360 - 170, absolute: true }, 0, 12);
  assert.ok(android && Math.abs(android.heading - 182) < 1e-9);
  assert.equal(android.needsCalibration, false);
  assert.equal(android.accuracyKnown, false);
  const ios = (accuracy: number) =>
    compassReadingFromOrientation({ alpha: 0, webkitCompassHeading: 355, webkitCompassAccuracy: accuracy }, 0, 10);
  assert.ok(Math.abs(ios(10)!.heading - 5) < 1e-9);
  assert.deepEqual(
    [ios(10)!.needsCalibration, ios(30)!.needsCalibration, ios(31)!.needsCalibration, ios(-1)!.needsCalibration],
    [false, false, true, true],
  );
  assert.equal(compassReadingFromOrientation({ alpha: 5, absolute: false }, 0, 10), null);
});

test("facing the Qibla holds within the release band and never while uncalibrated", () => {
  assert.equal(facesQibla(173.5, 176.35, false, false), true);
  assert.equal(facesQibla(172, 176.35, false, false), false);
  assert.equal(facesQibla(172, 176.35, true, false), true);
  assert.equal(facesQibla(171, 176.35, true, false), false);
  assert.equal(facesQibla(176.35, 176.35, false, true), false);
  assert.equal(facesQibla(359, 1, false, false), true);
});

test("heading smoother eases toward the sensor and never spins the long way round", () => {
  const smoother = new HeadingSmoother(200);
  assert.equal(smoother.step(350, 0), 350);
  const halfway = smoother.step(10, 200 * Math.LN2);
  assert.ok(Math.abs(halfway - 360) < 1e-9, `${halfway}`);
  const next = smoother.step(10, 10_000);
  assert.ok(Math.abs(next - 370) < 1e-9, `${next}`);
  assert.equal(smoother.value, next);
});

// The app's geomag package (WMM2025) for the same instants: local midnight at UTC+3.
const appDeclinations: Array<[number, number, string, number]> = [
  [55.7558, 37.6173, "2026-06-15", 12.113085440196249],
  [55.7558, 37.6173, "2028-01-01", 12.25956522288158],
  [21.4225, 39.8262, "2026-06-15", 3.504613672404009],
  [41.0082, 28.9784, "2026-06-15", 6.061925795828186],
  [41.2995, 69.2401, "2026-06-15", 5.683996731397475],
  [40.7128, -74.006, "2026-06-15", -12.476293996124271],
  [-6.2088, 106.8456, "2028-01-01", 0.6781455105450899],
  [64.1466, -21.9426, "2028-01-01", -10.688150435061141],
  [-33.9249, 18.4241, "2026-06-15", -26.72969358885945],
];

test("magnetic declination matches the app's World Magnetic Model", () => {
  for (const [latitude, longitude, date, expected] of appDeclinations) {
    const actual = magneticDeclination(latitude, longitude, new Date(`${date}T00:00:00+03:00`));
    // The app counts the year from local January 1; the site from UTC, three hours apart.
    assert.ok(actual !== null && Math.abs(actual - expected) < 2e-4, `${latitude},${longitude} ${date}: ${actual}`);
  }
  assert.equal(magneticDeclination(91, 0), null);
  assert.equal(magneticDeclination(0, Number.NaN), null);
  assert.ok(Number.isFinite(magneticDeclination(90, 0)));
});

test("prayer input follows the backend serializer limits", () => {
  assert.equal(isValidPrayerDate("2026-10-20"), true);
  assert.equal(isValidPrayerDate("2028-02-29"), true);
  for (const value of ["", "2026-02-30", "1899-12-31", "2101-01-01", "2026-1-5"]) {
    assert.equal(isValidPrayerDate(value), false, value);
  }
  for (const value of [0, -120, 120, 7]) assert.equal(isValidPrayerAdjustment(value), true);
  for (const value of [1.5, 121, -121, Number.NaN, "3"]) {
    assert.equal(isValidPrayerAdjustment(value), false, String(value));
  }
});

test("the month engine rejects adjustments the backend would reject", () => {
  for (const fajr of [1.5, 121]) {
    assert.throws(
      () =>
        calculatePrayerTimes({
          latitude: 41.0082,
          longitude: 28.9784,
          date: "2026-08-09",
          method: mwl,
          highLatitudeRule: "middle_of_night",
          polarResolution: "unresolved",
          adjustments: { fajr },
        }),
      (error: unknown) => error instanceof LocalPrayerCalculationUnavailable && error.reason === "invalid_input",
    );
  }
});

test("distance to the Kaaba separates the Haram from the rest of Makkah", () => {
  assert.equal(distanceToKaabaMeters(21.4225, 39.8262), 0);
  assert.ok((distanceToKaabaMeters(21.4228, 39.8262) ?? Infinity) < 50);
  assert.ok((distanceToKaabaMeters(21.4266, 39.8262) ?? 0) > 400);
  assert.equal(distanceToKaabaMeters(100, 0), null);
});
