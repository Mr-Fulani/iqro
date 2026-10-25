/**
 * The phone player, as in the app (clients/iqro_mobile/lib/features/audio/mini_player.dart):
 * a 66 px bar above the bottom navigation that collapses to a 60 px round button
 * and opens a full-screen player on tap. Pure rules, so they are unit-tested
 * apart from the components.
 */

/**
 * "closing" is the full player sinking out of view; it ends in "bar".
 * "collapsing" rolls the bar up into the round button and ends in "collapsed",
 * "expanding" unrolls it and ends in "bar".
 */
export type MiniPlayerView = "collapsed" | "collapsing" | "expanding" | "bar" | "full" | "closing";

export type MiniPlayerState = {
  view: MiniPlayerView;
  /** The full player's controls are hidden by a tap on its body, as in the app. */
  controlsHidden: boolean;
};

export type MiniPlayerAction =
  | { type: "collapse" }
  | { type: "expand" }
  | { type: "settled" }
  | { type: "open-full" }
  | { type: "close-full" }
  | { type: "closed" }
  | { type: "toggle-controls" }
  | { type: "route-change" }
  | { type: "request-change"; hasRequest: boolean };

export const INITIAL_MINI_PLAYER_STATE: MiniPlayerState = { view: "bar", controlsHidden: false };

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
/** The sink animation in app/mobile.css; "closed" follows its animationend, or this fallback. */
export const SHEET_CLOSE_MS = 260;
export const SHEET_CLOSE_FALLBACK_MS = SHEET_CLOSE_MS + 200;
/** The roll-up and unroll animations in app/mobile.css; "settled" follows their animationend, or this fallback. */
export const BAR_ROLL_MS = 420;
export const BAR_ROLL_FALLBACK_MS = BAR_ROLL_MS + 200;

/** The bar is the round button, or on its way to or from it. */
export function rolledUp(view: MiniPlayerView): boolean {
  return view === "collapsed" || view === "collapsing";
}

/** The full player is on screen while open and while it sinks away. */
export function sheetShown(view: MiniPlayerView): boolean {
  return view === "full" || view === "closing";
}

export function miniPlayerReducer(state: MiniPlayerState, action: MiniPlayerAction): MiniPlayerState {
  const { view } = state;
  switch (action.type) {
    case "collapse":
      // A tap while the bar still unrolls rolls it straight back up.
      return view === "bar" || view === "expanding" ? { ...state, view: "collapsing" } : state;
    case "expand":
      return view === "collapsed" || view === "collapsing" ? { ...state, view: "expanding" } : state;
    case "settled":
      if (view === "collapsing") return { ...state, view: "collapsed" };
      return view === "expanding" ? { ...state, view: "bar" } : state;
    case "open-full":
      // A tap while the sheet still sinks brings it straight back.
      return view === "full" ? state : { view: "full", controlsHidden: false };
    case "close-full":
      return view === "full" ? { ...state, view: "closing" } : state;
    case "closed":
      return view === "closing" ? { view: "bar", controlsHidden: false } : state;
    case "toggle-controls":
      return view === "full" ? { ...state, controlsHidden: !state.controlsHidden } : state;
    case "route-change":
      // The app's player is a pushed route: leaving the screen closes it.
      return sheetShown(view) ? { view: "bar", controlsHidden: false } : state;
    case "request-change":
      // The full player has nothing to show once playback is cleared.
      return !action.hasRequest && sheetShown(view) ? { view: "bar", controlsHidden: false } : state;
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

/** A tap on the full player's body hides its controls; taps on controls do not. */
export const PLAYER_CONTROL_SELECTOR =
  "button, a, input, select, textarea, label, [role='slider'], .player-background-options";

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
