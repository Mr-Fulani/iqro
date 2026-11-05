/** A stretch of one surah on a Mushaf page, played as one plan. */
export type MushafPageRun = { surah: number; start: number; end: number };

/**
 * What the Mushaf's play button reads: the page's ayahs (as "2:10" keys, in
 * reading order) from `from` (the first, when it is not on the page) to the
 * last, one run per surah, since a page may end one surah and begin the next.
 * The app reads its pages the same way (mushafPageRuns).
 */
export function mushafPageRuns(ayahKeys: readonly string[], from?: string | null): MushafPageRun[] {
  const first = from ? ayahKeys.indexOf(from) : 0;
  const runs: MushafPageRun[] = [];
  for (const key of ayahKeys.slice(Math.max(first, 0))) {
    const [surah, ayah] = key.split(":").map(Number);
    if (!Number.isInteger(surah) || !Number.isInteger(ayah)) continue;
    const last = runs.at(-1);
    if (last && last.surah === surah && ayah > last.end) last.end = ayah;
    else runs.push({ surah, start: ayah, end: ayah });
  }
  return runs;
}

/** The Audio player's speeds, in the order the Mushaf player's button steps through them, as in the app. */
export const PLAYER_SPEEDS = [1, 1.25, 1.5, 2, 0.75];

export function nextPlayerSpeed(speed: number): number {
  return PLAYER_SPEEDS[(PLAYER_SPEEDS.indexOf(speed) + 1) % PLAYER_SPEEDS.length];
}
