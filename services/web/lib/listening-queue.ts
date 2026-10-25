/**
 * The Audio tab's queue, as docs/audio-listening-queue.md sets it out and the
 * app follows (clients/iqro_mobile/lib/features/audio/listening_queue.dart):
 * which surah plays after, before and instead of the current one, and the
 * snapshot that brings the player back after a reload. Pure rules, unit-tested
 * apart from the player.
 */

export type QueueMode = "stop" | "next" | "loop";

export const QUEUE_MODES: readonly QueueMode[] = ["stop", "next", "loop"];
export const DEFAULT_QUEUE_MODE: QueueMode = "next";
export const SURAH_COUNT = 114;

/** One recording of the reciter the player can switch to. */
export type ListeningVariant = {
  id: string;
  /** "<style> · <riwayah>", already translated. */
  label: string;
  editionCode: string;
  /** The held surahs in order; empty means all 114 (catalogs from before the list). */
  surahNumbers: number[];
};

/** What the player plays from: one reciter and his recordings. */
export type ListeningQueue = {
  reciterId: string;
  artist: string;
  artworkUrl: string | null;
  variantId: string;
  variants: ListeningVariant[];
};

const ALL_SURAHS = Array.from({ length: SURAH_COUNT }, (_, index) => index + 1);

export function isQueueMode(value: unknown): value is QueueMode {
  return typeof value === "string" && (QUEUE_MODES as readonly string[]).includes(value);
}

export function currentVariant(queue: ListeningQueue): ListeningVariant | undefined {
  return queue.variants.find((variant) => variant.id === queue.variantId);
}

/** The surahs a recording holds, in order; an empty list stands for the whole Quran. */
export function heldSurahs(surahNumbers: readonly number[] | undefined): number[] {
  const held = [...new Set(surahNumbers ?? [])]
    .filter((surah) => Number.isInteger(surah) && surah >= 1 && surah <= SURAH_COUNT)
    .sort((left, right) => left - right);
  return held.length > 0 ? held : ALL_SURAHS;
}

/** The nearest held surah in a direction; with wrap, past either end to the other. */
export function stepSurah(
  held: readonly number[],
  current: number,
  direction: -1 | 1,
  wrap: boolean,
): number | null {
  if (held.length === 0) return null;
  const candidate = direction > 0
    ? held.find((surah) => surah > current)
    : held.findLast((surah) => surah < current);
  if (candidate !== undefined) return candidate;
  return wrap ? (direction > 0 ? held[0] : held[held.length - 1]) : null;
}

/** What plays once the current surah ends by itself; null ends playback. */
export function surahAfter(held: readonly number[], current: number, mode: QueueMode): number | null {
  if (mode === "stop") return null;
  return stepSurah(held, current, 1, mode === "loop");
}

/** The prev/next buttons: they cross the ends only in the loop mode. */
export function adjacentQueueSurah(
  held: readonly number[],
  current: number | null | undefined,
  direction: -1 | 1,
  mode: QueueMode,
): number | null {
  if (!current) return null;
  return stepSurah(held, current, direction, mode === "loop");
}

/** Where a switch to another recording lands: the same surah, the next held one, or the last. */
export function nearestHeldSurah(held: readonly number[], wanted: number): number | null {
  if (held.length === 0) return null;
  if (held.includes(wanted)) return wanted;
  return held.find((surah) => surah > wanted) ?? held[held.length - 1];
}

export type QueueRow =
  | { kind: "surah"; surah: number }
  | { kind: "gap"; from: number; to: number };

/** The queue list: held surahs, with each run of missing ones folded into one row. */
export function queueRows(held: readonly number[]): QueueRow[] {
  const rows: QueueRow[] = [];
  let expected = 1;
  for (const surah of held) {
    if (surah > expected) rows.push({ kind: "gap", from: expected, to: surah - 1 });
    rows.push({ kind: "surah", surah });
    expected = surah + 1;
  }
  if (held.length > 0 && expected <= SURAH_COUNT) {
    rows.push({ kind: "gap", from: expected, to: SURAH_COUNT });
  }
  return rows;
}

/** "Play the whole Quran": the stop mode would end after one surah, so it moves on. */
export function wholeQuranMode(mode: QueueMode): QueueMode {
  return mode === "stop" ? "next" : mode;
}

// ---------------------------------------------------------------------------
// The saved place
// ---------------------------------------------------------------------------

export const LISTENING_SNAPSHOT_KEY = "iqro_listening_v1";

export type ListeningSnapshot = {
  queue: ListeningQueue;
  surah: number;
  positionMs: number;
  mode: QueueMode;
  savedAt: string;
};

function isVariant(value: unknown): value is ListeningVariant {
  if (!value || typeof value !== "object") return false;
  const variant = value as Record<string, unknown>;
  return typeof variant.id === "string" && variant.id !== ""
    && typeof variant.label === "string"
    && typeof variant.editionCode === "string"
    && Array.isArray(variant.surahNumbers)
    && variant.surahNumbers.every((surah) => Number.isInteger(surah));
}

/** The saved place, or null when there is none or it cannot be read. */
export function parseListeningSnapshot(raw: string | null): ListeningSnapshot | null {
  if (!raw) return null;
  let data: unknown;
  try {
    data = JSON.parse(raw);
  } catch {
    return null;
  }
  if (!data || typeof data !== "object") return null;
  const value = data as Record<string, unknown>;
  const queue = value.queue as Record<string, unknown> | undefined;
  if (value.v !== 1 || !queue || typeof queue !== "object") return null;
  const variants = Array.isArray(queue.variants) ? queue.variants.filter(isVariant) : [];
  if (
    typeof queue.reciterId !== "string" ||
    typeof queue.artist !== "string" ||
    typeof queue.variantId !== "string" ||
    !variants.some((variant) => variant.id === queue.variantId)
  ) {
    return null;
  }
  const surah = Number(value.surah);
  const positionMs = Number(value.positionMs);
  if (!Number.isInteger(surah) || surah < 1 || surah > SURAH_COUNT) return null;
  return {
    queue: {
      reciterId: queue.reciterId,
      artist: queue.artist,
      artworkUrl: typeof queue.artworkUrl === "string" ? queue.artworkUrl : null,
      variantId: queue.variantId,
      variants,
    },
    surah,
    positionMs: Number.isFinite(positionMs) && positionMs > 0 ? Math.round(positionMs) : 0,
    mode: isQueueMode(value.mode) ? value.mode : DEFAULT_QUEUE_MODE,
    savedAt: typeof value.savedAt === "string" ? value.savedAt : "",
  };
}

export function serializeListeningSnapshot(snapshot: ListeningSnapshot): string {
  return JSON.stringify({ v: 1, ...snapshot });
}

// Storage can be missing or throw (private windows, blocked site data): the
// player then simply starts empty.
export function loadListeningSnapshot(): ListeningSnapshot | null {
  try {
    return parseListeningSnapshot(window.localStorage.getItem(LISTENING_SNAPSHOT_KEY));
  } catch {
    return null;
  }
}

export function saveListeningSnapshot(snapshot: ListeningSnapshot): void {
  try {
    window.localStorage.setItem(LISTENING_SNAPSHOT_KEY, serializeListeningSnapshot(snapshot));
  } catch {
    // Nothing to keep the place in.
  }
}

export function clearListeningSnapshot(): void {
  try {
    window.localStorage.removeItem(LISTENING_SNAPSHOT_KEY);
  } catch {
    // Nothing was kept.
  }
}
