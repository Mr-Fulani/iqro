// A TypeScript port of the mobile app's local prayer engine
// (clients/iqro_mobile/lib/features/prayer/prayer_local_engine.dart), which itself
// mirrors the backend's pinned Adhan 4.4.4 adapter. It accepts only the exact engine
// version exposed by the backend so the month calendar matches the app.

import { isValidPrayerAdjustment } from "./prayer-input.ts";

export const LOCAL_PRAYER_ENGINE_ID = "adhan-js-python-adapter";
export const LOCAL_PRAYER_ENGINE_VERSION = "4.4.4-quran.1-adhanpy.1.0.5";

export const PRAYER_CODES = ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"] as const;
export type PrayerCode = (typeof PRAYER_CODES)[number];
export type PrayerTimesUtc = Record<PrayerCode, number>;

export class LocalPrayerCalculationUnavailable extends Error {
  readonly reason: string;

  constructor(reason: string) {
    super(`Local prayer calculation unavailable: ${reason}`);
    this.reason = reason;
  }
}

export type LocalPrayerMethod = {
  code: string;
  fajrAngle: number;
  ishaAngle: number | null;
  ishaIntervalMinutes: number | null;
  adjustments: Partial<Record<PrayerCode, number>>;
};

export type LocalPrayerInput = {
  latitude: number;
  longitude: number;
  /** Civil date as YYYY-MM-DD. */
  date: string;
  method: LocalPrayerMethod;
  highLatitudeRule: string;
  polarResolution: string;
  hanafiAsr?: boolean;
  adjustments?: Partial<Record<PrayerCode, number>>;
};

export type LocalPrayerFallback = {
  applied: boolean;
  strategy?: string;
  reason?: string;
  referenceDate?: string;
  referenceLatitude?: number;
};

export type LocalPrayerResult = { timesUtc: PrayerTimesUtc; fallback: LocalPrayerFallback };

const DAY_MS = 86_400_000;

type MethodsCatalogLike = {
  algorithm?: { id?: string; version?: string };
  methods: Array<{
    id: string;
    code: string;
    available: boolean;
    parameters?: {
      fajr_angle?: string | number;
      isha?: { angle?: string | number | null; interval_minutes?: number | null };
      method_adjustments?: Partial<Record<PrayerCode, number>>;
    };
  }>;
};

/** Mirrors `PrayerMethod.supportsLocalCalculation` + `localMethod` in the app. */
export function localPrayerMethod(
  catalog: MethodsCatalogLike,
  methodId: string,
): LocalPrayerMethod | null {
  const method = catalog.methods.find((item) => item.id === methodId);
  if (
    !method ||
    !method.available ||
    catalog.algorithm?.id !== LOCAL_PRAYER_ENGINE_ID ||
    catalog.algorithm?.version !== LOCAL_PRAYER_ENGINE_VERSION
  ) {
    return null;
  }
  const parameters = method.parameters;
  const fajrAngle = parseNumber(parameters?.fajr_angle) ?? 0;
  const ishaAngle = parseNumber(parameters?.isha?.angle);
  const interval = parameters?.isha?.interval_minutes;
  const ishaIntervalMinutes = typeof interval === "number" ? Math.trunc(interval) : null;
  if (!(fajrAngle > 0) || (ishaAngle !== null) === (ishaIntervalMinutes !== null)) return null;
  const adjustments: Partial<Record<PrayerCode, number>> = {};
  for (const code of PRAYER_CODES) {
    const value = parameters?.method_adjustments?.[code];
    adjustments[code] = typeof value === "number" ? Math.trunc(value) : 0;
  }
  return { code: method.code, fajrAngle, ishaAngle, ishaIntervalMinutes, adjustments };
}

function parseNumber(value: unknown): number | null {
  if (value === null || value === undefined || value === "") return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

/** Every civil date of the given month (month is 1-based). */
export function prayerCalendarDates(year: number, month: number): string[] {
  const dayCount = new Date(Date.UTC(year, month, 0)).getUTCDate();
  return Array.from({ length: dayCount }, (_, index) => isoDate(Date.UTC(year, month - 1, index + 1)));
}

/** Calculates times for the civil date in `timezone`, as the app's `calculateForCivilDate`. */
export function calculateForCivilDate(
  input: LocalPrayerInput,
  timezone: string,
): { result: LocalPrayerResult; astronomicalDate: string } {
  const requested = dateOnly(input.date);
  let result = calculatePrayerTimes({ ...input, date: isoDate(requested) });
  const observed = zonedDateMs(result.timesUtc.dhuhr, timezone);
  const shift = Math.round((requested - observed) / DAY_MS);
  if (shift === 0) return { result, astronomicalDate: isoDate(requested) };
  const astronomicalDate = isoDate(requested + shift * DAY_MS);
  result = calculatePrayerTimes({ ...input, date: astronomicalDate });
  if (zonedDateMs(result.timesUtc.dhuhr, timezone) !== requested) {
    throw new LocalPrayerCalculationUnavailable("civil_date_alignment_failed");
  }
  return { result, astronomicalDate };
}

/** Calculates the whole month; throws like the app when any day cannot be resolved. */
export function calculatePrayerMonth(
  input: Omit<LocalPrayerInput, "date">,
  timezone: string,
  year: number,
  month: number,
): Array<{ date: string; timesUtc: PrayerTimesUtc }> {
  return prayerCalendarDates(year, month).map((date) => ({
    date,
    timesUtc: calculateForCivilDate({ ...input, date }, timezone).result.timesUtc,
  }));
}

export function calculatePrayerTimes(input: LocalPrayerInput): LocalPrayerResult {
  const { latitude, longitude, method } = input;
  if (
    !Number.isFinite(latitude) ||
    !Number.isFinite(longitude) ||
    latitude < -90 ||
    latitude > 90 ||
    longitude < -180 ||
    longitude > 180 ||
    method.fajrAngle <= 0 ||
    (method.ishaAngle === null) === (method.ishaIntervalMinutes === null) ||
    !Object.values(input.adjustments ?? {}).every(isValidPrayerAdjustment)
  ) {
    throw new LocalPrayerCalculationUnavailable("invalid_input");
  }
  const resolved = resolveSolarTime(input);
  return { timesUtc: calculateTimes(input, resolved), fallback: resolved.fallback };
}

type ResolvedSolarTime = {
  today: SolarTime;
  tomorrow: SolarTime;
  fallback: LocalPrayerFallback;
};

function resolveSolarTime(input: LocalPrayerInput): ResolvedSolarTime {
  const date = dateOnly(input.date);
  const today = new SolarTime(date, input.latitude, input.longitude);
  const tomorrow = new SolarTime(date + DAY_MS, input.latitude, input.longitude);
  if (today.valid && tomorrow.valid) {
    return { today, tomorrow, fallback: { applied: false } };
  }
  const resolved =
    input.polarResolution === "aqrab_yaum"
      ? resolveAqrabYaum(input)
      : input.polarResolution === "aqrab_balad"
        ? resolveAqrabBalad(input)
        : null;
  if (!resolved) {
    throw new LocalPrayerCalculationUnavailable("polar_sunrise_or_sunset_unresolved");
  }
  return resolved;
}

function resolveAqrabYaum(input: LocalPrayerInput): ResolvedSolarTime | null {
  const date = dateOnly(input.date);
  for (let distance = 1; distance <= 183; distance += 1) {
    for (const direction of [1, -1]) {
      const reference = date + distance * direction * DAY_MS;
      const today = new SolarTime(reference, input.latitude, input.longitude);
      const tomorrow = new SolarTime(reference + DAY_MS, input.latitude, input.longitude);
      if (today.valid && tomorrow.valid) {
        return {
          today,
          tomorrow,
          fallback: {
            applied: true,
            strategy: "aqrab_yaum",
            reason: "polar_sunrise_or_sunset_unavailable",
            referenceDate: isoDate(reference),
          },
        };
      }
    }
  }
  return null;
}

function resolveAqrabBalad(input: LocalPrayerInput): ResolvedSolarTime | null {
  const direction = input.latitude > 0 ? 1 : -1;
  let latitude = input.latitude - direction * 0.5;
  const date = dateOnly(input.date);
  while (Math.abs(latitude) >= 65) {
    const today = new SolarTime(date, latitude, input.longitude);
    const tomorrow = new SolarTime(date + DAY_MS, latitude, input.longitude);
    if (today.valid && tomorrow.valid) {
      return {
        today,
        tomorrow,
        fallback: {
          applied: true,
          strategy: "aqrab_balad",
          reason: "polar_sunrise_or_sunset_unavailable",
          referenceLatitude: latitude,
        },
      };
    }
    latitude -= direction * 0.5;
  }
  return null;
}

function calculateTimes(input: LocalPrayerInput, resolved: ResolvedSolarTime): PrayerTimesUtc {
  const date = dateOnly(input.date);
  const solar = resolved.today;
  const { method } = input;
  const dhuhr = asUtcDateTime(solar.transit, date);
  const sunrise = asUtcDateTime(solar.sunrise, date);
  const sunset = asUtcDateTime(solar.sunset, date);
  const tomorrowSunrise = asUtcDateTime(resolved.tomorrow.sunrise, date + DAY_MS);
  const asr = asUtcDateTime(solar.afternoon(input.hanafiAsr ? 2 : 1), date);
  if (dhuhr === null || sunrise === null || sunset === null || tomorrowSunrise === null || asr === null) {
    throw new LocalPrayerCalculationUnavailable("required_solar_event_unavailable");
  }
  const nightSeconds = (tomorrowSunrise - sunset) / 1000;
  if (!Number.isFinite(nightSeconds) || nightSeconds <= 0) {
    throw new LocalPrayerCalculationUnavailable("invalid_night_duration");
  }
  const moonsighting = isMoonsighting(method.code);

  let fajr = asUtcDateTime(solar.hourAngle(-method.fajrAngle, false), date);
  if (moonsighting && input.latitude >= 55) fajr = sunrise - seconds(nightSeconds / 7);
  const safeFajr = moonsighting
    ? seasonAdjustedMorning(input.latitude, date, sunrise)
    : sunrise - seconds(nightSeconds * nightPortion(input.highLatitudeRule, method.fajrAngle));
  if (fajr === null || safeFajr > fajr) fajr = safeFajr;

  let isha: number;
  if (method.ishaIntervalMinutes !== null) {
    isha = sunset + method.ishaIntervalMinutes * 60_000;
  } else {
    const candidate = asUtcDateTime(solar.hourAngle(-(method.ishaAngle as number), true), date);
    const moonCandidate =
      moonsighting && input.latitude >= 55 ? sunset + seconds(nightSeconds / 7) : candidate;
    const safeIsha = moonsighting
      ? seasonAdjustedEvening(input.latitude, date, sunset)
      : sunset + seconds(nightSeconds * nightPortion(input.highLatitudeRule, method.ishaAngle as number));
    isha = moonCandidate === null || safeIsha < moonCandidate ? safeIsha : moonCandidate;
  }

  const raw: PrayerTimesUtc = { fajr, sunrise, dhuhr, asr, maghrib: sunset, isha };
  const times = {} as PrayerTimesUtc;
  for (const code of PRAYER_CODES) {
    const adjustment = (method.adjustments[code] ?? 0) + (input.adjustments?.[code] ?? 0);
    times[code] = roundNearest(raw[code] + adjustment * 60_000);
  }
  return times;
}

class SolarTime {
  readonly latitude: number;
  readonly longitude: number;
  readonly transit: number;
  readonly sunrise: number;
  readonly sunset: number;
  private readonly approximate: number;
  private readonly previous: SolarCoordinates;
  private readonly current: SolarCoordinates;
  private readonly following: SolarCoordinates;

  constructor(date: number, latitude: number, longitude: number) {
    this.latitude = latitude;
    this.longitude = longitude;
    const day = new Date(date);
    const julian = julianDay(day.getUTCFullYear(), day.getUTCMonth() + 1, day.getUTCDate());
    this.previous = new SolarCoordinates(julian - 1);
    this.current = new SolarCoordinates(julian);
    this.following = new SolarCoordinates(julian + 1);
    this.approximate = approximateTransit(
      longitude,
      this.current.apparentSiderealTime,
      this.current.rightAscension,
    );
    this.transit = correctedTransit(
      this.approximate,
      longitude,
      this.current.apparentSiderealTime,
      this.current.rightAscension,
      this.previous.rightAscension,
      this.following.rightAscension,
    );
    this.sunrise = this.hourAngle(-50 / 60, false);
    this.sunset = this.hourAngle(-50 / 60, true);
  }

  get valid(): boolean {
    return Number.isFinite(this.sunrise) && Number.isFinite(this.sunset);
  }

  hourAngle(angle: number, afterTransit: boolean): number {
    return correctedHourAngle(
      this.approximate,
      angle,
      this.latitude,
      this.longitude,
      afterTransit,
      this.current.apparentSiderealTime,
      this.current.rightAscension,
      this.previous.rightAscension,
      this.following.rightAscension,
      this.current.declination,
      this.previous.declination,
      this.following.declination,
    );
  }

  afternoon(shadowLength: number): number {
    const tangent = Math.abs(this.latitude - this.current.declination);
    const inverse = shadowLength + Math.tan(radians(tangent));
    const angle = degrees(Math.atan(1 / inverse));
    return this.hourAngle(angle, true);
  }
}

class SolarCoordinates {
  readonly declination: number;
  readonly rightAscension: number;
  readonly apparentSiderealTime: number;

  constructor(julianDayValue: number) {
    const century = (julianDayValue - 2451545.0) / 36525;
    const meanSolar = meanSolarLongitude(century);
    const meanLunar = meanLunarLongitude(century);
    const node = ascendingLunarNodeLongitude(century);
    const longitude = radians(apparentSolarLongitude(century, meanSolar));
    const sidereal = meanSiderealTime(century);
    const nutationLongitude = nutationInLongitude(meanSolar, meanLunar, node);
    const nutationObliquity = nutationInObliquity(meanSolar, meanLunar, node);
    const meanObliquityValue = meanObliquity(century);
    const apparentObliquityValue = radians(apparentObliquity(century, meanObliquityValue));
    this.declination = degrees(Math.asin(Math.sin(apparentObliquityValue) * Math.sin(longitude)));
    this.rightAscension = unwind(
      degrees(
        Math.atan2(Math.cos(apparentObliquityValue) * Math.sin(longitude), Math.cos(longitude)),
      ),
    );
    this.apparentSiderealTime =
      sidereal +
      (nutationLongitude * 3600 * Math.cos(radians(meanObliquityValue + nutationObliquity))) / 3600;
  }
}

function julianDay(year: number, month: number, day: number): number {
  const y = month > 2 ? year : year - 1;
  const m = month > 2 ? month : month + 12;
  const a = Math.floor(y / 100);
  const b = Math.floor(2 - a + a / 4);
  const i0 = Math.trunc(365.25 * (y + 4716));
  const i1 = Math.trunc(30.6001 * (m + 1));
  return i0 + i1 + day + b - 1524.5;
}

const meanSolarLongitude = (t: number) => unwind(280.4664567 + 36000.76983 * t + 0.0003032 * t * t);
const meanLunarLongitude = (t: number) => unwind(218.3165 + 481267.8813 * t);
const ascendingLunarNodeLongitude = (t: number) =>
  unwind(125.04452 - 1934.136261 * t + 0.0020708 * t * t + (t * t * t) / 450000);
const meanSolarAnomaly = (t: number) => unwind(357.52911 + 35999.05029 * t - 0.0001537 * t * t);

function solarEquation(t: number, anomaly: number): number {
  const m = radians(anomaly);
  return (
    (1.914602 - 0.004817 * t - 0.000014 * t * t) * Math.sin(m) +
    (0.019993 - 0.000101 * t) * Math.sin(2 * m) +
    0.000289 * Math.sin(3 * m)
  );
}

function apparentSolarLongitude(t: number, meanSolar: number): number {
  const longitude = meanSolar + solarEquation(t, meanSolarAnomaly(t));
  const omega = 125.04 - 1934.136 * t;
  return unwind(longitude - 0.00569 - 0.00478 * Math.sin(radians(omega)));
}

function meanSiderealTime(t: number): number {
  const julian = t * 36525 + 2451545;
  return unwind(
    280.46061837 +
      360.98564736629 * (julian - 2451545) +
      0.000387933 * t * t -
      (t * t * t) / 38710000,
  );
}

const nutationInLongitude = (l0: number, lp: number, node: number) =>
  (-17.2 / 3600) * Math.sin(radians(node)) -
  (1.32 / 3600) * Math.sin(2 * radians(l0)) -
  (0.23 / 3600) * Math.sin(2 * radians(lp)) +
  (0.21 / 3600) * Math.sin(2 * radians(node));
const nutationInObliquity = (l0: number, lp: number, node: number) =>
  (9.2 / 3600) * Math.cos(radians(node)) +
  (0.57 / 3600) * Math.cos(2 * radians(l0)) +
  (0.1 / 3600) * Math.cos(2 * radians(lp)) -
  (0.09 / 3600) * Math.cos(2 * radians(node));
const meanObliquity = (t: number) =>
  23.439291 - 0.013004167 * t - 0.0000001639 * t * t + 0.0000005036 * t * t * t;
const apparentObliquity = (t: number, mean: number) =>
  mean + 0.00256 * Math.cos(radians(125.04 - 1934.136 * t));

function approximateTransit(longitude: number, sidereal: number, rightAscension: number): number {
  const transit = normalize((rightAscension - longitude - sidereal) / 360, 1);
  const expected = normalize((12 - longitude / 15) / 24, 1);
  if (transit - expected > 0.5) return transit - 1;
  if (expected - transit > 0.5) return transit + 1;
  return transit;
}

function correctedTransit(
  m0: number,
  longitude: number,
  sidereal: number,
  rightAscension: number,
  previousRightAscension: number,
  followingRightAscension: number,
): number {
  const longitudeWest = -longitude;
  const theta = unwind(sidereal + 360.985647 * m0);
  const alpha = unwind(
    interpolateAngles(rightAscension, previousRightAscension, followingRightAscension, m0),
  );
  const h = closestAngle(theta - longitudeWest - alpha);
  return (m0 + h / -360) * 24;
}

function correctedHourAngle(
  m0: number,
  angle: number,
  latitude: number,
  longitude: number,
  afterTransit: boolean,
  sidereal: number,
  rightAscension: number,
  previousRightAscension: number,
  followingRightAscension: number,
  declination: number,
  previousDeclination: number,
  followingDeclination: number,
): number {
  const term1 =
    Math.sin(radians(angle)) - Math.sin(radians(latitude)) * Math.sin(radians(declination));
  const term2 = Math.cos(radians(latitude)) * Math.cos(radians(declination));
  const h0 = degrees(Math.acos(term1 / term2));
  if (!Number.isFinite(h0)) return Number.NaN;
  const m = afterTransit ? m0 + h0 / 360 : m0 - h0 / 360;
  const theta = unwind(sidereal + 360.985647 * m);
  const alpha = unwind(
    interpolateAngles(rightAscension, previousRightAscension, followingRightAscension, m),
  );
  const delta = interpolate(declination, previousDeclination, followingDeclination, m);
  const h = theta + longitude - alpha;
  const altitudeValue = altitude(latitude, delta, h);
  const denominator =
    360 * Math.cos(radians(delta)) * Math.cos(radians(latitude)) * Math.sin(radians(h));
  const correction = (altitudeValue - angle) / denominator;
  return (m + correction) * 24;
}

function interpolate(y2: number, y1: number, y3: number, n: number): number {
  const a = y2 - y1;
  const b = y3 - y2;
  return y2 + (n / 2) * (a + b + n * (b - a));
}

function interpolateAngles(y2: number, y1: number, y3: number, n: number): number {
  const a = unwind(y2 - y1);
  const b = unwind(y3 - y2);
  return y2 + (n / 2) * (a + b + n * (b - a));
}

const altitude = (latitude: number, declination: number, hourAngle: number) =>
  degrees(
    Math.asin(
      Math.sin(radians(latitude)) * Math.sin(radians(declination)) +
        Math.cos(radians(latitude)) * Math.cos(radians(declination)) * Math.cos(radians(hourAngle)),
    ),
  );

function asUtcDateTime(value: number, date: number): number | null {
  if (!Number.isFinite(value)) return null;
  const hours = Math.floor(value);
  const minutes = Math.floor((value - hours) * 60);
  const secondsValue = Math.floor((value - (hours + minutes / 60)) * 3600);
  return date + hours * 3_600_000 + minutes * 60_000 + secondsValue * 1000;
}

// Times are epoch milliseconds that may carry microsecond fractions, as Dart's
// DateTime does. Like Dart, rounding clears seconds and microseconds only.
function roundNearest(value: number): number {
  const micros = Math.round(value * 1000);
  const second = (((Math.floor(micros / 1_000_000) % 60) + 60) % 60);
  const microsecond = ((micros % 1000) + 1000) % 1000;
  const offset = second >= 30 ? 60 - second : -second;
  return (micros + offset * 1_000_000 - microsecond) / 1000;
}

function nightPortion(rule: string, angle: number): number {
  if (rule === "middle_of_night") return 0.5;
  if (rule === "seventh_of_night") return 1 / 7;
  if (rule === "twilight_angle") return angle / 60;
  throw new LocalPrayerCalculationUnavailable("invalid_high_latitude_rule");
}

const isMoonsighting = (code: string) => code.replaceAll("-", "_") === "moonsighting_committee";

function seasonAdjustedMorning(latitude: number, date: number, sunrise: number): number {
  const absolute = Math.abs(latitude);
  const adjustment = seasonalAdjustment(date, latitude, [
    75 + (28.65 / 55) * absolute,
    75 + (19.44 / 55) * absolute,
    75 + (32.74 / 55) * absolute,
    75 + (48.1 / 55) * absolute,
  ]);
  return sunrise - Math.floor(adjustment * 60 + 0.5) * 1000;
}

function seasonAdjustedEvening(latitude: number, date: number, sunset: number): number {
  const absolute = Math.abs(latitude);
  const adjustment = seasonalAdjustment(date, latitude, [
    75 + (25.6 / 55) * absolute,
    75 + (2.05 / 55) * absolute,
    75 - (9.21 / 55) * absolute,
    75 + (6.14 / 55) * absolute,
  ]);
  return sunset + Math.floor(adjustment * 60 + 0.5) * 1000;
}

function seasonalAdjustment(date: number, latitude: number, values: number[]): number {
  const year = new Date(date).getUTCFullYear();
  const dayOfYear = Math.round((date - Date.UTC(year, 0, 1)) / DAY_MS) + 1;
  const daysInYear = isLeapYear(year) ? 366 : 365;
  let day: number;
  if (latitude >= 0) {
    const result = dayOfYear + 10;
    day = result >= daysInYear ? result - daysInYear : result;
  } else {
    const result = dayOfYear - (isLeapYear(year) ? 173 : 172);
    day = result < 0 ? result + daysInYear : result;
  }
  const [a, b, c, d] = values;
  if (day < 91) return a + ((b - a) / 91) * day;
  if (day < 137) return b + ((c - b) / 46) * (day - 91);
  if (day < 183) return c + ((d - c) / 46) * (day - 137);
  if (day < 229) return d + ((c - d) / 46) * (day - 183);
  if (day < 275) return c + ((b - c) / 46) * (day - 229);
  return b + ((a - b) / 91) * (day - 275);
}

const isLeapYear = (year: number) => year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
const seconds = (value: number) => Math.round(value * 1_000_000) / 1000;
const normalize = (value: number, bound: number) => value - bound * Math.floor(value / bound);
const unwind = (value: number) => normalize(value, 360);
const closestAngle = (value: number) =>
  value >= -180 && value <= 180 ? value : value - 360 * Math.round(value / 360);
const radians = (value: number) => (value * Math.PI) / 180;
const degrees = (value: number) => (value * 180) / Math.PI;

function dateOnly(value: string): number {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) throw new LocalPrayerCalculationUnavailable("invalid_input");
  return Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3]));
}

function isoDate(value: number): string {
  return new Date(value).toISOString().slice(0, 10);
}

const dateFormatters = new Map<string, Intl.DateTimeFormat>();

/** UTC midnight of the civil date that `instant` falls on in `timezone`. */
function zonedDateMs(instant: number, timezone: string): number {
  let formatter = dateFormatters.get(timezone);
  if (!formatter) {
    try {
      formatter = new Intl.DateTimeFormat("en-US", {
        timeZone: timezone,
        year: "numeric",
        month: "numeric",
        day: "numeric",
      });
    } catch {
      throw new LocalPrayerCalculationUnavailable("timezone_unavailable");
    }
    dateFormatters.set(timezone, formatter);
  }
  const parts = Object.fromEntries(
    formatter.formatToParts(new Date(instant)).map((part) => [part.type, part.value]),
  );
  return Date.UTC(Number(parts.year), Number(parts.month) - 1, Number(parts.day));
}
