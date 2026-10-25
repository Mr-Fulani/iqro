import assert from "node:assert/strict";
import test from "node:test";
import {
  INITIAL_MINI_PLAYER_STATE,
  MINI_PLAYER_SPACER_HEIGHT,
  miniPlayerReducer,
  rolledUp,
  seekPositionMs,
  sheetDragOffset,
  sheetShown,
  swipeDismisses,
} from "./mini-player.ts";
import type { MiniPlayerAction, MiniPlayerState, MiniPlayerView } from "./mini-player.ts";

const at = (view: MiniPlayerView, controlsHidden = false): MiniPlayerState => ({ view, controlsHidden });
const run = (state: MiniPlayerState, ...actions: MiniPlayerAction[]) =>
  actions.reduce(miniPlayerReducer, state);

test("the bar rolls up into the round button and unrolls back, each settling at its animation's end", () => {
  assert.equal(miniPlayerReducer(at("bar"), { type: "collapse" }).view, "collapsing");
  assert.equal(run(at("bar"), { type: "collapse" }, { type: "settled" }).view, "collapsed");
  assert.equal(miniPlayerReducer(at("collapsed"), { type: "expand" }).view, "expanding");
  assert.equal(run(at("collapsed"), { type: "expand" }, { type: "settled" }).view, "bar");
  assert.equal(miniPlayerReducer(at("bar"), { type: "expand" }).view, "bar");
  assert.equal(miniPlayerReducer(at("collapsed"), { type: "collapse" }).view, "collapsed");
  assert.equal(miniPlayerReducer(at("collapsing"), { type: "collapse" }).view, "collapsing");
  assert.equal(miniPlayerReducer(at("expanding"), { type: "expand" }).view, "expanding");
});

test("a tap during a roll turns it back, and the late end of the cancelled roll changes nothing", () => {
  assert.equal(run(at("bar"), { type: "collapse" }, { type: "expand" }).view, "expanding");
  assert.equal(run(at("collapsed"), { type: "expand" }, { type: "collapse" }).view, "collapsing");
  // Quick taps always end in the state of the last tap.
  assert.equal(run(at("bar"), { type: "collapse" }, { type: "expand" }, { type: "collapse" }, { type: "settled" }).view, "collapsed");
  assert.equal(run(at("bar"), { type: "collapse" }, { type: "expand" }, { type: "settled" }, { type: "settled" }).view, "bar");
  // Only a rolling bar settles; the sheet ends with "closed".
  for (const view of ["bar", "collapsed", "full", "closing"] as const) {
    assert.equal(miniPlayerReducer(at(view), { type: "settled" }).view, view);
  }
  assert.equal(miniPlayerReducer(at("collapsing"), { type: "closed" }).view, "collapsing");
  assert.equal(rolledUp("collapsing"), true);
  assert.equal(rolledUp("collapsed"), true);
  assert.equal(rolledUp("expanding"), false);
  assert.equal(rolledUp("bar"), false);
});

test("the full player opens from either state and closes through the sinking state", () => {
  assert.equal(miniPlayerReducer(at("bar"), { type: "open-full" }).view, "full");
  assert.equal(miniPlayerReducer(at("collapsed"), { type: "open-full" }).view, "full");
  assert.deepEqual(run(at("full"), { type: "close-full" }), at("closing"));
  assert.deepEqual(run(at("full"), { type: "close-full" }, { type: "closed" }), at("bar"));
  // Only a sinking sheet can finish closing; nothing else reacts to the animation's end.
  assert.deepEqual(miniPlayerReducer(at("bar"), { type: "closed" }), at("bar"));
  assert.deepEqual(miniPlayerReducer(at("full"), { type: "closed" }), at("full"));
  assert.deepEqual(miniPlayerReducer(at("bar"), { type: "close-full" }), at("bar"));
  assert.deepEqual(miniPlayerReducer(at("collapsed"), { type: "close-full" }), at("collapsed"));
  // Collapsing is a bar gesture; it does not reach through the open sheet.
  assert.equal(miniPlayerReducer(at("full"), { type: "collapse" }).view, "full");
  assert.equal(miniPlayerReducer(at("closing"), { type: "collapse" }).view, "closing");
});

test("a tap while the sheet sinks brings it back; a second close request changes nothing", () => {
  assert.deepEqual(run(at("full"), { type: "close-full" }, { type: "open-full" }), at("full"));
  assert.deepEqual(run(at("full"), { type: "close-full" }, { type: "close-full" }), at("closing"));
  // The late "closed" of the cancelled close never shuts the reopened player.
  assert.deepEqual(run(at("full"), { type: "close-full" }, { type: "open-full" }, { type: "closed" }), at("full"));
});

test("leaving the page or clearing playback closes an open or sinking player only", () => {
  assert.deepEqual(miniPlayerReducer(at("full"), { type: "route-change" }), at("bar"));
  assert.deepEqual(miniPlayerReducer(at("closing"), { type: "route-change" }), at("bar"));
  assert.equal(miniPlayerReducer(at("collapsed"), { type: "route-change" }).view, "collapsed");
  assert.deepEqual(miniPlayerReducer(at("full"), { type: "request-change", hasRequest: false }), at("bar"));
  assert.deepEqual(miniPlayerReducer(at("closing"), { type: "request-change", hasRequest: false }), at("bar"));
  assert.equal(miniPlayerReducer(at("full"), { type: "request-change", hasRequest: true }).view, "full");
  assert.equal(miniPlayerReducer(at("bar"), { type: "request-change", hasRequest: false }).view, "bar");
});

test("the sheet is on screen while open and while it sinks", () => {
  assert.equal(sheetShown("full"), true);
  assert.equal(sheetShown("closing"), true);
  assert.equal(sheetShown("bar"), false);
  assert.equal(sheetShown("collapsed"), false);
  assert.deepEqual(INITIAL_MINI_PLAYER_STATE, at("bar"));
});

test("a tap on the body hides the controls and the next one shows them; closing or reopening resets", () => {
  assert.deepEqual(miniPlayerReducer(at("full"), { type: "toggle-controls" }), at("full", true));
  assert.deepEqual(run(at("full"), { type: "toggle-controls" }, { type: "toggle-controls" }), at("full"));
  assert.deepEqual(miniPlayerReducer(at("bar"), { type: "toggle-controls" }), at("bar"));
  assert.deepEqual(run(at("full", true), { type: "close-full" }, { type: "closed" }), at("bar"));
  assert.deepEqual(run(at("full", true), { type: "close-full" }, { type: "open-full" }), at("full"));
  assert.deepEqual(miniPlayerReducer(at("full", true), { type: "route-change" }), at("bar"));
});

test("the sheet follows the finger down but never up", () => {
  assert.equal(sheetDragOffset(48), 48);
  assert.equal(sheetDragOffset(0), 0);
  assert.equal(sheetDragOffset(-30), 0);
});

test("a long or fast downward swipe dismisses, a short slow one or an upward one does not", () => {
  assert.equal(swipeDismisses({ deltaY: 120, durationMs: 900 }), true);
  assert.equal(swipeDismisses({ deltaY: 40, durationMs: 40 }), true);
  assert.equal(swipeDismisses({ deltaY: 40, durationMs: 400 }), false);
  assert.equal(swipeDismisses({ deltaY: 10, durationMs: 5 }), false);
  assert.equal(swipeDismisses({ deltaY: -200, durationMs: 100 }), false);
  assert.equal(swipeDismisses({ deltaY: 30, durationMs: 0 }), false);
});

test("a seek stays within the active range", () => {
  assert.equal(seekPositionMs(5_000, 1_000, 9_000), 5_000);
  assert.equal(seekPositionMs(12_000, 1_000, 9_000), 9_000);
  assert.equal(seekPositionMs(-5, 1_000, 9_000), 1_000);
  assert.equal(seekPositionMs(Number.NaN, 1_000, 9_000), 1_000);
});

test("content keeps the bar's height plus its gap above the navigation", () => {
  assert.equal(MINI_PLAYER_SPACER_HEIGHT, 72);
});
