// Input rules shared by the prayer form and the month engine. They mirror the
// backend serializers: a real date in 1900–2100 and whole-minute adjustments in ±120.

export const PRAYER_ADJUSTMENT_LIMIT = 120;

export function isValidPrayerDate(value: string): boolean {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return false;
  const [year, month, day] = [Number(match[1]), Number(match[2]), Number(match[3])];
  const date = new Date(Date.UTC(year, month - 1, day));
  return (
    year >= 1900 &&
    year <= 2100 &&
    date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day
  );
}

export function isValidPrayerAdjustment(value: unknown): value is number {
  return (
    typeof value === "number" &&
    Number.isInteger(value) &&
    Math.abs(value) <= PRAYER_ADJUSTMENT_LIMIT
  );
}

// The method a new visitor starts with, as in the app.
export const DEFAULT_PRAYER_METHOD_CODE = "muslim-world-league";

export function defaultPrayerMethod<T extends { code: string; available: boolean }>(
  methods: readonly T[],
): T | undefined {
  const available = methods.filter((method) => method.available);
  return (
    available.find((method) => method.code === DEFAULT_PRAYER_METHOD_CODE) ||
    available[0] ||
    methods[0]
  );
}
