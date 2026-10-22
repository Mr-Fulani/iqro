import assert from "node:assert/strict";
import test from "node:test";
import { clampStep, stepKeyDelta, type StepKey } from "./step-navigation.ts";

const key = (name: string, extra: Partial<StepKey> = {}): StepKey => ({
  key: name,
  altKey: false,
  ctrlKey: false,
  metaKey: false,
  shiftKey: false,
  defaultPrevented: false,
  target: null,
  ...extra,
});

test("arrow keys turn steps along the reading direction", () => {
  assert.equal(stepKeyDelta(key("ArrowRight"), "ltr"), 1);
  assert.equal(stepKeyDelta(key("ArrowLeft"), "ltr"), -1);
  assert.equal(stepKeyDelta(key("ArrowLeft"), "rtl"), 1);
  assert.equal(stepKeyDelta(key("ArrowRight"), "rtl"), -1);
});

test("other keys, shortcuts and keys typed into fields are left alone", () => {
  assert.equal(stepKeyDelta(key("Enter"), "ltr"), 0);
  assert.equal(stepKeyDelta(key("ArrowRight", { altKey: true }), "ltr"), 0);
  assert.equal(stepKeyDelta(key("ArrowRight", { defaultPrevented: true }), "ltr"), 0);
  const field = { closest: (selector: string) => (selector.includes("input") ? {} : null) } as unknown as EventTarget;
  assert.equal(stepKeyDelta(key("ArrowRight", { target: field }), "ltr"), 0);
});

test("steps stay within the lesson", () => {
  assert.equal(clampStep(-1, 5), 0);
  assert.equal(clampStep(7, 5), 4);
  assert.equal(clampStep(2, 5), 2);
  assert.equal(clampStep(3, 0), 0);
});
