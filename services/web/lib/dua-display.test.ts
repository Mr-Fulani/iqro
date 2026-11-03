import assert from "node:assert/strict";
import test from "node:test";

import { DEFAULT_DUA_DISPLAY, parseDuaDisplay } from "./dua-display.ts";

test("du'a cards show transliteration and translation until switched off", () => {
  assert.deepEqual(parseDuaDisplay(null), DEFAULT_DUA_DISPLAY);
  assert.deepEqual(parseDuaDisplay(""), DEFAULT_DUA_DISPLAY);
  assert.deepEqual(parseDuaDisplay("{"), DEFAULT_DUA_DISPLAY);
  assert.deepEqual(parseDuaDisplay("null"), DEFAULT_DUA_DISPLAY);
  assert.deepEqual(parseDuaDisplay("{}"), DEFAULT_DUA_DISPLAY);
});

test("each switch is read on its own", () => {
  assert.deepEqual(
    parseDuaDisplay(JSON.stringify({ transliteration: false })),
    { transliteration: false, translation: true },
  );
  assert.deepEqual(
    parseDuaDisplay(JSON.stringify({ transliteration: true, translation: false })),
    { transliteration: true, translation: false },
  );
});
