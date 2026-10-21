import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

import { APP_ASSETS_DIRECTORY, salah3dAppAssets } from "../scripts/salah3d-app-assets.ts";
import type { SalahStep } from "./salah.ts";
import { nextSalahSceneSpeed, SALAH_SCENE_BY_POSITION, salahSceneSteps } from "./salah-3d.ts";
import { MAIN, SEGMENTS, STEPS } from "./salah3d/salah-scene.js";

// The picture defaults to the position's own; null leaves the step without one.
function step(slug: string, position?: string, media: string | null = position ? `position-${position}` : null): SalahStep {
  return { slug: `lesson.${slug}`, kind: "action", position, media: media ?? undefined, title: slug, instruction: "", formulas: [] };
}

test("course positions map onto the scene's poses and nothing else gets 3D", () => {
  const steps = [
    step("intention", "qiyam"),
    step("takbir", "takbir"),
    step("ruku", "ruku"),
    step("itidal", "itidal"),
    step("sujud-1", "sujud"),
    step("jalsa", "jalsa"),
    step("sujud-2", "sujud"),
    step("tashahhud", "tashahhud"),
    step("qunut", "qunut"),
    step("taslim", "taslim"),
    step("wudu-face", undefined, "wudu-face"),
    step("intro"),
  ];
  assert.deepEqual(salahSceneSteps(steps), [
    "qiyam", "takbir", "ruku", "itidal", "sujud", "jalsa", "sujud2", "tashahhud", null, "salam", null, null,
  ]);
});

test("a step without a picture has no 3D, and the greeting after tawarruk has none either", () => {
  assert.deepEqual(salahSceneSteps([step("ruku", "ruku", null)]), [null]);
  assert.deepEqual(
    salahSceneSteps([step("first", "tashahhud"), step("last", "tawarruk"), step("salawat", "tawarruk"), step("taslim", "taslim")]),
    ["tashahhud", null, null, null],
  );
  // A position named like an Object member is not a pose.
  assert.deepEqual(salahSceneSteps([step("odd", "constructor")]), [null]);
});

test("the speed button cycles through the scene's speeds", () => {
  assert.equal(nextSalahSceneSpeed(1), 0.75);
  assert.equal(nextSalahSceneSpeed(0.75), 0.5);
  assert.equal(nextSalahSceneSpeed(0.5), 1);
});

test("every mapped pose has a segment of the cycle made of that pose's keys", () => {
  const ids = STEPS.map((item) => item.id);
  for (const scene of Object.values(SALAH_SCENE_BY_POSITION).concat("sujud2")) {
    assert.ok(ids.includes(scene), scene);
  }
  for (const [id, [first, last, paused = last]] of Object.entries(SEGMENTS)) {
    assert.ok(first <= paused && paused <= last && last < MAIN.length, id);
    for (let key = first; key <= last; key++) assert.equal(MAIN[key]![3], ids.indexOf(id as never), `${id} key ${key}`);
  }
});

test("the app's offline copy of the scene is generated from this module and the pinned three", async () => {
  for (const [name, content] of await salah3dAppAssets()) {
    const committed = await readFile(new URL(name, APP_ASSETS_DIRECTORY)).catch(() => null);
    assert.ok(committed?.equals(content), `clients/iqro_mobile/assets/salah3d/${name} is stale: node scripts/salah3d-app-assets.ts`);
  }
});
