/**
 * The hint that the Quran text can be swiped, as the app's
 * (clients/iqro_mobile/lib/features/quran/reader_page_turn.dart): a moment
 * after the text opens a hand pulls it a little to the right, then to the
 * left, uncovering what lies each way. Pure rules, unit-tested apart from the
 * components.
 */
export const READER_SWIPE_HINT_LIMIT = 3;
export const READER_SWIPE_HINT_DELAY_MS = 1200;
export const READER_SWIPE_HINT_MS = 3600;
/** How long the still hint stands when motion is reduced. */
export const READER_SWIPE_HINT_STILL_MS = 4000;
export const READER_SWIPE_HINT_STORAGE_KEY = "iqro_reader_swipe_hint_v1";

/** How many times the hint was shown; the limit once the reader swiped. Zero when missing or malformed. */
export function parseReaderSwipeHint(raw: string | null): number {
  const shown = Number(raw);
  return raw !== null && Number.isInteger(shown) && shown > 0 ? shown : 0;
}

const ease = (t: number) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);

/** A pause, to the right, a pause, back, to the left, a pause, back, a pause: [share of the time, from, to]. */
const PATH: ReadonlyArray<readonly [number, number, number]> = [
  [3, 0, 0], [6, 0, 1], [5, 1, 1], [4, 1, 0], [6, 0, -1], [5, -1, -1], [4, -1, 0], [3, 0, 0],
];
const PATH_TOTAL = PATH.reduce((sum, [weight]) => sum + weight, 0);

/** The text's place at `progress` (0..1) of the hint, as a share of the pull: 1 is fully right, -1 left. */
export function readerSwipeHintPull(progress: number): number {
  let left = Math.min(1, Math.max(0, progress)) * PATH_TOTAL;
  for (const [weight, from, to] of PATH) {
    if (left <= weight) return from + (to - from) * ease(left / weight);
    left -= weight;
  }
  return 0;
}

/** The hand and the caption fade in at the start and out at the end. */
export function readerSwipeHintOpacity(progress: number): number {
  return Math.min(1, Math.max(0, Math.min(progress, 1 - progress) * 14));
}
