/**
 * Step-by-step lessons: the Salah course and the tajweed breakdown turn their
 * steps with the same buttons and keys.
 */

export type StepKey = Pick<
  KeyboardEvent,
  "key" | "altKey" | "ctrlKey" | "metaKey" | "shiftKey" | "defaultPrevented"
> & { target: EventTarget | null };

export function clampStep(index: number, count: number): number {
  return Math.min(Math.max(0, count - 1), Math.max(0, index));
}

/**
 * The step an arrow key moves to: 1 forward, -1 back, 0 for any other key.
 * Forward follows the reading direction, so in Arabic it is the left arrow.
 * Keys typed into a field or sent to a media element are left alone.
 */
export function stepKeyDelta(event: StepKey, direction: "ltr" | "rtl"): -1 | 0 | 1 {
  if (event.defaultPrevented || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return 0;
  if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return 0;
  const target = event.target as { closest?: (selector: string) => unknown } | null;
  if (target?.closest?.("input, textarea, select, audio, video, [contenteditable]")) return 0;
  return event.key === (direction === "rtl" ? "ArrowLeft" : "ArrowRight") ? 1 : -1;
}
