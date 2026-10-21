// Which course steps show the owner's schematic 3D scene (lib/salah3d, docs/salah/salah-3d.md):
// those whose illustration is a still of a scene pose (`media.scene`). The app mirrors this
// in salah_3d.dart.

import type { SalahMedia, SalahSceneView, SalahStep } from "./salah.ts";
import type { SalahSceneStepId } from "./salah3d/salah-scene.js";

export type { SalahSceneStepId };

/** The poses this build's scene can show; a newer course may name others (they stay pictures). */
export const SALAH_SCENE_POSES: readonly SalahSceneStepId[] = [
  "qiyam",
  "takbir",
  "ruku",
  "itidal",
  "sujud",
  "jalsa",
  "sujud2",
  "tashahhud",
  "salam",
];

export type SalahStepScene = { pose: SalahSceneStepId; view: SalahSceneView };

function sceneOf(step: SalahStep | undefined, media: Readonly<Record<string, SalahMedia>>) {
  return step?.media ? media[step.media]?.scene : undefined;
}

/** The scene of each step, or null where its picture is all there is. */
export function salahStepScenes(
  steps: readonly SalahStep[],
  media: Readonly<Record<string, SalahMedia>>,
): (SalahStepScene | null)[] {
  return steps.map((step, index) => {
    const scene = sceneOf(step, media);
    if (!scene || !SALAH_SCENE_POSES.includes(scene.pose as SalahSceneStepId)) return null;
    // One picture serves both prostrations; the second rises from the sitting between them.
    if (scene.pose === "sujud" && scene.view === "full" && sceneOf(steps[index - 1], media)?.pose === "jalsa") {
      return { pose: "sujud2", view: "full" };
    }
    return { pose: scene.pose as SalahSceneStepId, view: scene.view };
  });
}

export const SALAH_SCENE_SPEEDS = [1, 0.75, 0.5] as const;
export type SalahSceneSpeed = (typeof SALAH_SCENE_SPEEDS)[number];

export function nextSalahSceneSpeed(speed: SalahSceneSpeed): SalahSceneSpeed {
  return SALAH_SCENE_SPEEDS[(SALAH_SCENE_SPEEDS.indexOf(speed) + 1) % SALAH_SCENE_SPEEDS.length]!;
}

/**
 * The scene on the current step plays its pose once and holds the last frame. `run` changes
 * whenever the pose should play from its start: on every new step and on «Replay».
 */
export type SalahScenePlayback = { playing: boolean; ended: boolean; run: number };
export type SalahScenePlaybackEvent = "step" | "replay" | "toggle" | "ended";

export const SALAH_SCENE_PLAYBACK: SalahScenePlayback = { playing: true, ended: false, run: 0 };

export function nextSalahScenePlayback(state: SalahScenePlayback, event: SalahScenePlaybackEvent): SalahScenePlayback {
  switch (event) {
    case "step":
    case "replay":
      return { playing: true, ended: false, run: state.run + 1 };
    case "toggle":
      // Play after the end plays the pose again.
      return state.ended ? nextSalahScenePlayback(state, "replay") : { ...state, playing: !state.playing };
    case "ended":
      return { ...state, ended: true };
  }
}
