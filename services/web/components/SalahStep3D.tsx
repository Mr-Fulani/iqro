"use client";

import dynamic from "next/dynamic";
import { type ReactNode, useCallback, useEffect, useState } from "react";

import { nextSalahSceneSpeed, type SalahSceneSpeed, type SalahStepScene } from "../lib/salah-3d";
import type { Salah3DStageProps } from "./Salah3DStage";

function Salah3DLoadFailed({ onError }: Salah3DStageProps) {
  useEffect(() => onError(), [onError]);
  return null;
}

// three.js stays out of the page load; a failed chunk leaves the still in place.
const Salah3DStage = dynamic(
  () => import("./Salah3DStage").catch(() => ({ default: Salah3DLoadFailed })),
  { ssr: false },
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
  playing: boolean;
  speed: SalahSceneSpeed;
  slot: (element: HTMLDivElement | null) => void;
  togglePlaying: () => void;
  cycleSpeed: () => void;
  resetView: () => void;
  /** Render once in the player; it draws into the current step's slot. */
  stage: ReactNode;
};

/**
 * The schematic 3D scene in place of the pose stills: it starts once the visitor acts on the
 * page, needs WebGL and no reduced motion, and any failure leaves the stills for the visit.
 */
export function useSalah3D(scene: SalahStepScene | null, lessonHasScenes: boolean): Salah3D {
  const [capable, setCapable] = useState(false);
  const [engaged, setEngaged] = useState(false);
  const [failed, setFailed] = useState(false);
  const [ready, setReady] = useState(false);
  const [playing, setPlaying] = useState(true);
  const [speed, setSpeed] = useState<SalahSceneSpeed>(1);
  const [resetKey, setResetKey] = useState(0);
  const [slot, setSlot] = useState<HTMLDivElement | null>(null);

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

  const active = wanted && engaged;
  const view = scene?.view ?? "full";
  return {
    shown: active && scene !== null,
    ready,
    playing,
    speed,
    slot: setSlot,
    togglePlaying: () => setPlaying((value) => !value),
    cycleSpeed: () => setSpeed(nextSalahSceneSpeed),
    resetView: () => setResetKey((value) => value + 1),
    stage: active ? (
      <Salah3DStage
        // A view is chosen when the scene mounts.
        key={view}
        slot={slot}
        view={view}
        step={scene && scene.view === "full" ? scene.pose : null}
        playing={playing}
        speed={speed}
        resetKey={resetKey}
        onReady={markReady}
        onError={fail}
      />
    ) : null,
  };
}
