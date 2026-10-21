// Ports of dua_presentation.dart, iqro_repetition_counter.dart and
// playback_speed.dart: how many times a du'a is said and how its audio plays.

const MAX_PRACTICE_STAGE = 1000;
const MAX_PRACTICE_TOTAL = 10000;

/** «33 · 33 · 34» as [33, 33, 34]; anything else falls back to [fallback]. */
export function duaRepetitionStages(label: string, fallback: number): number[] {
  const safeFallback = Math.min(Math.max(Math.trunc(fallback), 1), MAX_PRACTICE_STAGE);
  const normalized = label.trim();
  if (!normalized || !/^\d{1,4}(?:\s*[·•,;/+]\s*\d{1,4})+$/u.test(normalized)) {
    return [safeFallback];
  }
  const stages = (normalized.match(/\d+/gu) ?? []).map(Number);
  if (
    stages.length === 0
    || stages.some((stage) => stage < 1 || stage > MAX_PRACTICE_STAGE)
    || stages.reduce((sum, stage) => sum + stage, 0) > MAX_PRACTICE_TOTAL
  ) {
    return [safeFallback];
  }
  return stages;
}

/** Repetitions to count for a du'a: the sum of its stages. */
export function duaRepetitionTotal(label: string, fallback: number): number {
  return duaRepetitionStages(label, fallback).reduce((sum, stage) => sum + stage, 0);
}

/** The count after one more tap; a finished count starts again. */
export function advanceRepetitionCount(completed: number, total: number): number {
  return completed >= total ? 0 : completed + 1;
}

/** Speeds the speed button steps through, in order. */
export const playbackSpeeds = [1, 1.25, 1.5, 0.75] as const;

/** The speed after `speed`; an unknown speed starts the cycle over. */
export function nextPlaybackSpeed(speed: number): number {
  const index = playbackSpeeds.indexOf(speed as (typeof playbackSpeeds)[number]);
  return playbackSpeeds[(index + 1) % playbackSpeeds.length];
}
