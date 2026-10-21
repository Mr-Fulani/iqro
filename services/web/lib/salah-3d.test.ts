import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { readFile } from "node:fs/promises";
import test from "node:test";

import { APP_ASSETS_DIRECTORY, salah3dAppAssets } from "../scripts/salah3d-app-assets.ts";
import { parseSalahCourseDocument, type SalahMedia, type SalahStep } from "./salah.ts";
import {
  nextSalahScenePlayback,
  nextSalahSceneSpeed,
  SALAH_SCENE_PLAYBACK,
  SALAH_SCENE_POSES,
  salahStepScenes,
} from "./salah-3d.ts";
import { MAIN, SEGMENTS, type SalahSceneStepId, STEPS } from "./salah3d/salah-scene.js";

const picture = { url: "https://media.example/p.webp", width: 720, height: 720, bytes: 1, sha256: "0", alt: "" };
const still = (pose: string, view: "full" | "hand" | "back" = "full"): SalahMedia => ({ ...picture, scene: { pose, view } });

function step(slug: string, media?: string): SalahStep {
  return { slug: `lesson.${slug}`, kind: "action", media, title: slug, instruction: "", formulas: [] };
}

test("a step shows the scene pose its illustration is a still of", () => {
  const media = {
    "position-qiyam": still("qiyam"),
    "position-ruku": still("ruku"),
    "position-sujud": still("sujud"),
    "position-jalsa": still("jalsa"),
    "position-taslim": still("salam"),
    "position-qunut": picture,
    "position-hand": still("tashahhud", "hand"),
    "position-newer": still("prostration-on-a-chair"),
  };
  const steps = [
    step("intention", "position-qiyam"),
    step("ruku", "position-ruku"),
    step("sujud-1", "position-sujud"),
    step("jalsa", "position-jalsa"),
    step("sujud-2", "position-sujud"),
    step("qunut", "position-qunut"),
    step("pointing", "position-hand"),
    step("newer", "position-newer"),
    step("taslim", "position-taslim"),
    step("intro"),
  ];
  assert.deepEqual(salahStepScenes(steps, media), [
    { pose: "qiyam", view: "full" },
    { pose: "ruku", view: "full" },
    { pose: "sujud", view: "full" },
    { pose: "jalsa", view: "full" },
    // the second prostration rises from the sitting between the two
    { pose: "sujud2", view: "full" },
    null,
    { pose: "tashahhud", view: "hand" },
    // a pose this build does not know stays a picture
    null,
    { pose: "salam", view: "full" },
    null,
  ]);
});

test("the document keeps a well-formed scene and drops a malformed one", () => {
  const example = JSON.parse(
    readFileSync(new URL("../../../docs/salah/course-document.example.json", import.meta.url), "utf8"),
  ) as { media: Record<string, Record<string, unknown>> };
  example.media["position-ruku"]!.scene = { pose: "ruku" };
  example.media["position-qiyam"]!.scene = { pose: "qiyam", view: "aerial" };
  const media = parseSalahCourseDocument(example).media;
  assert.deepEqual(media["position-takbir"]!.scene, { pose: "takbir", view: "full" });
  assert.equal(media["position-ruku"]!.scene, undefined);
  assert.equal(media["position-qiyam"]!.scene, undefined);
  assert.equal(media["wudu-face"]!.scene, undefined);
});

test("this build knows every pose of the scene and every pose the course asks for", () => {
  assert.deepEqual([...SALAH_SCENE_POSES].sort(), STEPS.map((item) => item.id).sort());
  const snapshot = JSON.parse(
    readFileSync(
      new URL("../../backend/src/quran_backend/modules/salah/data/hanbali-umdah-v1.json", import.meta.url),
      "utf8",
    ),
  ) as { media: { key: string; scene?: { pose: string } }[] };
  const asked = snapshot.media.flatMap((asset) => (asset.scene ? [asset.scene.pose] : []));
  assert.ok(asked.length >= 8);
  for (const pose of asked) assert.ok(SALAH_SCENE_POSES.includes(pose as never), pose);
});

test("the speed button cycles through the scene's speeds", () => {
  assert.equal(nextSalahSceneSpeed(1), 0.75);
  assert.equal(nextSalahSceneSpeed(0.75), 0.5);
  assert.equal(nextSalahSceneSpeed(0.5), 1);
});

test("a step plays its pose once; replay and every new step play it from the start", () => {
  // the same cases as clients/iqro_mobile/test/features/salah_3d_test.dart
  let state = SALAH_SCENE_PLAYBACK;
  assert.deepEqual(state, { playing: true, ended: false, run: 0 });
  state = nextSalahScenePlayback(state, "ended");
  assert.deepEqual(state, { playing: true, ended: true, run: 0 });
  // play after the end is a replay
  assert.deepEqual(nextSalahScenePlayback(state, "toggle"), { playing: true, ended: false, run: 1 });
  state = nextSalahScenePlayback(state, "replay");
  assert.deepEqual(state, { playing: true, ended: false, run: 1 });
  // a pause holds the movement where it is, play goes on from there
  state = nextSalahScenePlayback(state, "toggle");
  assert.deepEqual(state, { playing: false, ended: false, run: 1 });
  assert.deepEqual(nextSalahScenePlayback(state, "toggle"), { playing: true, ended: false, run: 1 });
  // the next step plays its own pose, paused or ended before
  assert.deepEqual(nextSalahScenePlayback(state, "step"), { playing: true, ended: false, run: 2 });
  assert.deepEqual(nextSalahScenePlayback(nextSalahScenePlayback(state, "ended"), "step"), {
    playing: true,
    ended: false,
    run: 2,
  });
});

test("every pose has a segment of the cycle made of that pose's keys", () => {
  const ids = STEPS.map((item) => item.id);
  assert.deepEqual(Object.keys(SEGMENTS).sort(), [...ids].sort());
  for (const [id, [first, last, paused = last]] of Object.entries(SEGMENTS)) {
    assert.ok(first <= paused && paused <= last && last < MAIN.length, id);
    for (let key = first; key <= last; key++) assert.equal(MAIN[key]![3], ids.indexOf(id as SalahSceneStepId), `${id} key ${key}`);
  }
});

test("the app's offline copy of the scene is generated from this module and the pinned three", async () => {
  for (const [name, content] of await salah3dAppAssets()) {
    const committed = await readFile(new URL(name, APP_ASSETS_DIRECTORY)).catch(() => null);
    assert.ok(committed?.equals(content), `clients/iqro_mobile/assets/salah3d/${name} is stale: node scripts/salah3d-app-assets.ts`);
  }
});
