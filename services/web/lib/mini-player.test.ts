import assert from "node:assert/strict";
import test from "node:test";
import {
  MINI_PLAYER_SPACER_HEIGHT,
  adjacentSurah,
  miniPlayerReducer,
  seekPositionMs,
  sheetDragOffset,
  swipeDismisses,
} from "./mini-player.ts";

test("the bar collapses to the round button and expands back", () => {
  assert.equal(miniPlayerReducer("bar", { type: "collapse" }), "collapsed");
  assert.equal(miniPlayerReducer("collapsed", { type: "expand" }), "bar");
  assert.equal(miniPlayerReducer("bar", { type: "expand" }), "bar");
  assert.equal(miniPlayerReducer("collapsed", { type: "collapse" }), "collapsed");
});

test("the full player opens from either state and closes back to the bar", () => {
  assert.equal(miniPlayerReducer("bar", { type: "open-full" }), "full");
  assert.equal(miniPlayerReducer("collapsed", { type: "open-full" }), "full");
  assert.equal(miniPlayerReducer("full", { type: "close-full" }), "bar");
  assert.equal(miniPlayerReducer("bar", { type: "close-full" }), "bar");
  assert.equal(miniPlayerReducer("collapsed", { type: "close-full" }), "collapsed");
  // Collapsing is a bar gesture; it does not reach through the open sheet.
  assert.equal(miniPlayerReducer("full", { type: "collapse" }), "full");
});

test("leaving the page or clearing playback closes the full player only", () => {
  assert.equal(miniPlayerReducer("full", { type: "route-change" }), "bar");
  assert.equal(miniPlayerReducer("collapsed", { type: "route-change" }), "collapsed");
  assert.equal(miniPlayerReducer("full", { type: "request-change", hasRequest: false }), "bar");
  assert.equal(miniPlayerReducer("full", { type: "request-change", hasRequest: true }), "full");
  assert.equal(miniPlayerReducer("bar", { type: "request-change", hasRequest: false }), "bar");
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

test("previous and next stay inside the 114 surahs", () => {
  assert.equal(adjacentSurah(1, -1), null);
  assert.equal(adjacentSurah(1, 1), 2);
  assert.equal(adjacentSurah(114, 1), null);
  assert.equal(adjacentSurah(114, -1), 113);
  assert.equal(adjacentSurah(null, 1), null);
  assert.equal(adjacentSurah(undefined, -1), null);
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
