// Types for the owner's scene module (salah-scene.js, plain JavaScript on three r149).

export type SalahSceneStepId =
  | "qiyam"
  | "takbir"
  | "ruku"
  | "itidal"
  | "sujud"
  | "jalsa"
  | "sujud2"
  | "tashahhud"
  | "salam"
  | "qunut"
  | "tawarruk"
  | "wudu-start"
  | "wudu-hands"
  | "wudu-mouth-nose"
  | "wudu-face"
  | "wudu-arms"
  | "wudu-head"
  | "wudu-ears"
  | "wudu-feet"
  | "wudu-finish";

export type SalahSceneStep = { id: SalahSceneStepId; title: string };

export type SalahSceneOptions = {
  view?: "full" | "main" | "hand" | "back";
  /** Play only this step's movement, once, instead of looping the whole cycle. */
  step?: SalahSceneStepId | null;
  speed?: number;
  /** The canvas sits in a scrolling page: vertical swipes and the wheel scroll it. */
  pageScroll?: boolean;
  onStep?: (index: number, step: SalahSceneStep | undefined) => void;
  /** The step's movement has played and holds its last frame. */
  onEnd?: () => void;
};

export type SalahScene = {
  steps: SalahSceneStep[];
  duration: number;
  setStep(id: SalahSceneStepId | null): void;
  /** Resumes a paused movement; an ended one waits for replay(). */
  play(): void;
  pause(): void;
  /** Plays the step's movement again from its start; a turned camera glides back. */
  replay(): void;
  setSpeed(speed: number): void;
  resetCamera(): void;
  /** Turns the camera around the figure by an angle in radians, as a sideways drag does. */
  turn(angle: number): void;
  dispose(): void;
};

export const VERSION: string;
export const STEPS: SalahSceneStep[];
/** [first key, last key, key shown when paused (default: last)] of MAIN. */
export const SEGMENTS: Record<SalahSceneStepId, [number, number, number?]>;
/** The full cycle: [pose, transition s, hold s, STEPS index, blend options?]. */
export const MAIN: [string, number, number, number, object?][];
/** Throws when the browser cannot create a WebGL context. */
export function mount(canvas: HTMLCanvasElement, options?: SalahSceneOptions): SalahScene;
