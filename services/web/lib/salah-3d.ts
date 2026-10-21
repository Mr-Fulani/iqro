// Which course steps get the owner's schematic 3D scene (lib/salah3d, docs/salah/salah-3d.md)
// as an alternative to their picture. The app mirrors this in salah_3d.dart.

import type { SalahStep } from "./salah.ts";
import type { SalahSceneStepId } from "./salah3d/salah-scene.js";

export type { SalahSceneStepId };

/** Course `position` → the scene pose that shows it. */
export const SALAH_SCENE_BY_POSITION: Readonly<Record<string, SalahSceneStepId>> = {
  qiyam: "qiyam",
  takbir: "takbir",
  ruku: "ruku",
  itidal: "itidal",
  sujud: "sujud",
  jalsa: "jalsa",
  tashahhud: "tashahhud",
  taslim: "salam",
};

/**
 * The scene step for each course step, or null where the scene has no such pose
 * (qunut, tawarruk, wudu) or the step has no picture to switch from.
 */
export function salahSceneSteps(steps: readonly SalahStep[]): (SalahSceneStepId | null)[] {
  let sitting: string | undefined;
  return steps.map((step, index) => {
    const position = step.position;
    if (position === "tashahhud" || position === "tawarruk") sitting = position;
    if (!step.media || !position || !Object.hasOwn(SALAH_SCENE_BY_POSITION, position)) return null;
    const scene = SALAH_SCENE_BY_POSITION[position]!;
    // The second prostration comes from the sitting between the two.
    if (scene === "sujud" && steps[index - 1]?.position === "jalsa") return "sujud2";
    // The scene greets from iftirash; after a tawarruk sitting its pose would be wrong.
    if (scene === "salam" && sitting === "tawarruk") return null;
    return scene;
  });
}

export const SALAH_SCENE_SPEEDS = [1, 0.75, 0.5] as const;
export type SalahSceneSpeed = (typeof SALAH_SCENE_SPEEDS)[number];

export function nextSalahSceneSpeed(speed: SalahSceneSpeed): SalahSceneSpeed {
  return SALAH_SCENE_SPEEDS[(SALAH_SCENE_SPEEDS.indexOf(speed) + 1) % SALAH_SCENE_SPEEDS.length]!;
}
