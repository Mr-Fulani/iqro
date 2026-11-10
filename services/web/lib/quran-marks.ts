import type { MessageKey } from "./i18n";

/** The parts of a rub al-hizb quarter the reader's mark needs. */
export type QuarterStart = {
  number: number;
  hizb_number: number;
  quarter_number: number;
  start_ayah: { surah: number; number: number };
};

/** The quarter whose first ayah is among `verseKeys` ("surah:ayah"), if any. */
export function quarterStartingIn<T extends QuarterStart>(
  quarters: readonly T[],
  verseKeys: readonly string[],
): T | null {
  if (quarters.length === 0 || verseKeys.length === 0) return null;
  const keys = new Set(verseKeys);
  return quarters.find((quarter) => keys.has(quarterStartKey(quarter))) ?? null;
}

export function quarterStartKey(quarter: QuarterStart): string {
  return `${quarter.start_ayah.surah}:${quarter.start_ayah.number}`;
}

/**
 * The label of a quarter's start: a new juz on the first quarter of an odd
 * hizb, a new hizb on any other first quarter, else ¼, ½ or ¾ of the hizb.
 */
export function quarterMarkMessage(quarter: QuarterStart): {
  key: MessageKey;
  variables: Record<string, number>;
} {
  const hizb = quarter.hizb_number;
  if (quarter.quarter_number <= 1) {
    return hizb % 2 === 1
      ? { key: "quran.markJuz", variables: { juz: (hizb + 1) / 2 } }
      : { key: "quran.markHizb", variables: { hizb } };
  }
  const key = (
    {
      2: "quran.markQuarter",
      3: "quran.markHalf",
      4: "quran.markThreeQuarters",
    } as const
  )[quarter.quarter_number as 2 | 3 | 4] ?? "quran.markQuarter";
  return { key, variables: { hizb } };
}
