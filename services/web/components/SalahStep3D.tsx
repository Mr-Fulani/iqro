"use client";

import { lazy, type ReactNode, Suspense, useCallback, useEffect, useReducer, useState } from "react";

import {
  nextSalahScenePlayback,
  nextSalahSceneSpeed,
  SALAH_SCENE_PLAYBACK,
  type SalahSceneSpeed,
  type SalahStepScene,
} from "../lib/salah-3d";
import type { Salah3DStageProps } from "./Salah3DStage";

function Salah3DLoadFailed({ onError }: Salah3DStageProps) {
  useEffect(() => onError(), [onError]);
  return null;
}

// three.js stays out of the page load; a failed chunk leaves the still in place. The stage
// renders only in the browser, once the visitor acts on the page. React.lazy rather than
// next/dynamic keeps the lesson's own chunk small enough to carry this import's loader, so
// the page does not pay one more request for it (scripts/lighthouse-budget.mjs).
const Salah3DStage = lazy(() =>
  import("./Salah3DStage").catch(() => ({ default: Salah3DLoadFailed })),
);

function hasWebgl(): boolean {
  try {
    const canvas = document.createElement("canvas");
    const gl = canvas.getContext("webgl2") || canvas.getContext("webgl");
    gl?.getExtension("WEBGL_lose_context")?.loseContext();
    return gl !== null;
  } catch {
    return false;
  }
}

// The first sign of a visitor at the page starts the scene: the page itself loads light.
const ENGAGE_EVENTS = ["pointerdown", "pointermove", "keydown", "touchstart", "wheel", "scroll"] as const;

export type Salah3D = {
  /** The current step shows the running scene over its still. */
  shown: boolean;
  ready: boolean;
  /** The pose is moving: neither paused nor played to its end. */
  playing: boolean;
  /** The pose has played once and holds its last frame. */
  ended: boolean;
  speed: SalahSceneSpeed;
  slot: (element: HTMLDivElement | null) => void;
  /** Pause, play, or replay once the pose has played. */
  togglePlaying: () => void;
  cycleSpeed: () => void;
  /** Render once in the player; it draws into the current step's slot. */
  stage: ReactNode;
};

/**
 * The schematic 3D scene in place of the pose stills: it starts once the visitor acts on the
 * page, needs WebGL and no reduced motion, and any failure leaves the stills for the visit.
 * Each step plays its pose once; play after the end plays it again.
 */
export function useSalah3D(scene: SalahStepScene | null, lessonHasScenes: boolean, stepIndex: number): Salah3D {
  const [capable, setCapable] = useState(false);
  const [engaged, setEngaged] = useState(false);
  const [failed, setFailed] = useState(false);
  const [ready, setReady] = useState(false);
  const [playback, dispatch] = useReducer(nextSalahScenePlayback, SALAH_SCENE_PLAYBACK);
  const [speed, setSpeed] = useState<SalahSceneSpeed>(1);
  const [slot, setSlot] = useState<HTMLDivElement | null>(null);

  // A new step plays its pose once, whether the last one was paused or had ended.
  const [playbackStep, setPlaybackStep] = useState(stepIndex);
  if (playbackStep !== stepIndex) {
    setPlaybackStep(stepIndex);
    dispatch("step");
  }

  useEffect(() => {
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => setCapable("WebGLRenderingContext" in window && !reduced.matches);
    update();
    reduced.addEventListener("change", update);
    return () => reduced.removeEventListener("change", update);
  }, []);

  const wanted = capable && lessonHasScenes && !failed;
  useEffect(() => {
    if (!wanted || engaged) return;
    const engage = () => {
      if (hasWebgl()) setEngaged(true);
      else setFailed(true);
    };
    for (const name of ENGAGE_EVENTS) window.addEventListener(name, engage, { once: true, passive: true });
    return () => {
      for (const name of ENGAGE_EVENTS) window.removeEventListener(name, engage);
    };
  }, [engaged, wanted]);

  const fail = useCallback(() => {
    setFailed(true);
    setReady(false);
  }, []);
  const markReady = useCallback(() => setReady(true), []);
  const markEnded = useCallback(() => dispatch("ended"), []);

  const active = wanted && engaged;
  const view = scene?.view ?? "full";
  const playing = playback.playing && !playback.ended;
  return {
    shown: active && scene !== null,
    ready,
    playing,
    ended: playback.ended,
    speed,
    slot: setSlot,
    togglePlaying: () => dispatch("toggle"),
    cycleSpeed: () => setSpeed(nextSalahSceneSpeed),
    stage: active ? (
      <Suspense fallback={null}>
        <Salah3DStage
          // A view is chosen when the scene mounts.
          key={view}
          slot={slot}
          view={view}
          step={scene && scene.view === "full" ? scene.pose : null}
          playing={playing}
          run={playback.run}
          speed={speed}
          onReady={markReady}
          onEnded={markEnded}
          onError={fail}
        />
      </Suspense>
    ) : null,
  };
}
