/**
 * The phone player, as in the app (clients/iqro_mobile/lib/features/audio/mini_player.dart):
 * a 66 px bar above the bottom navigation that collapses to a 60 px round button
 * and opens a full-screen player on tap. Pure rules, so they are unit-tested
 * apart from the components.
 */

export type MiniPlayerView = "collapsed" | "bar" | "full";

export type MiniPlayerAction =
  | { type: "collapse" }
  | { type: "expand" }
  | { type: "open-full" }
  | { type: "close-full" }
  | { type: "route-change" }
  | { type: "request-change"; hasRequest: boolean };

export const MINI_PLAYER_BAR_HEIGHT = 66;
export const MINI_PLAYER_BUTTON_SIZE = 60;
export const MINI_PLAYER_BAR_RADIUS = 17;
export const MINI_PLAYER_BUTTON_RADIUS = 26;
/** The gap between the bar and the navigation, as the app's top padding. */
export const MINI_PLAYER_GAP = 6;
/** Content keeps this much room above the navigation while the player is shown. */
export const MINI_PLAYER_SPACER_HEIGHT = MINI_PLAYER_BAR_HEIGHT + MINI_PLAYER_GAP;
/** The site's bottom navigation shows up to this width (app/mobile.css). */
export const MOBILE_PLAYER_MEDIA_QUERY = "(max-width: 768px)";

export function miniPlayerReducer(view: MiniPlayerView, action: MiniPlayerAction): MiniPlayerView {
  switch (action.type) {
    case "collapse":
      return view === "full" ? view : "collapsed";
    case "expand":
      return view === "collapsed" ? "bar" : view;
    case "open-full":
      return "full";
    case "close-full":
      return view === "full" ? "bar" : view;
    case "route-change":
      // The app's player is a pushed route: leaving the screen closes it.
      return view === "full" ? "bar" : view;
    case "request-change":
      // The full player has nothing to show once playback is cleared.
      return !action.hasRequest && view === "full" ? "bar" : view;
  }
}

/** How far down the sheet follows the finger: it never moves up past its place. */
export function sheetDragOffset(deltaY: number): number {
  return deltaY > 0 ? deltaY : 0;
}

export type SwipeSample = { deltaY: number; durationMs: number };

export const SWIPE_DISMISS_DISTANCE = 96;
export const SWIPE_DISMISS_VELOCITY = 0.6;

/** A downward swipe closes the sheet when it is long enough or fast enough. */
export function swipeDismisses({ deltaY, durationMs }: SwipeSample): boolean {
  if (deltaY <= 0) return false;
  if (deltaY >= SWIPE_DISMISS_DISTANCE) return true;
  const velocity = durationMs > 0 ? deltaY / durationMs : 0;
  return deltaY >= 24 && velocity >= SWIPE_DISMISS_VELOCITY;
}

/** The surah the previous/next buttons move to, or null at either end of the Quran. */
export function adjacentSurah(current: number | null | undefined, direction: -1 | 1): number | null {
  if (!current || !Number.isInteger(current)) return null;
  const target = current + direction;
  return target >= 1 && target <= 114 ? target : null;
}

/** Where a slider value lands on the timeline, within the active range. */
export function seekPositionMs(value: number, startMs: number, endMs: number): number {
  const low = Math.min(startMs, endMs);
  const high = Math.max(startMs, endMs);
  if (!Number.isFinite(value)) return low;
  return Math.min(high, Math.max(low, value));
}
