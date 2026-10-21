"use client";

import dynamic from "next/dynamic";
import { type ReactNode, useCallback, useEffect, useState } from "react";

import { nextSalahSceneSpeed, type SalahSceneSpeed, type SalahSceneStepId } from "../lib/salah-3d";
import type { Salah3DStageProps } from "./Salah3DStage";

function Salah3DLoadFailed({ onError }: Salah3DStageProps) {
  useEffect(() => onError(), [onError]);
  return null;
}

// three.js reaches the browser only after the visitor picks «3D»; a failed chunk
// leaves the picture in place.
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

export type Salah3D = {
  /** The current step offers «Picture / 3D». */
  offered: boolean;
  /** The current step shows the 3D scene instead of its picture. */
  shown: boolean;
  ready: boolean;
  playing: boolean;
  speed: SalahSceneSpeed;
  /** 3D has just failed on this step: the picture stays. */
  notice: boolean;
  slot: (element: HTMLDivElement | null) => void;
  choose: (threeD: boolean) => void;
  togglePlaying: () => void;
  cycleSpeed: () => void;
  resetView: () => void;
  /** Render once in the player; it draws into the current step's slot. */
  stage: ReactNode;
};

/**
 * The schematic 3D scene as an addition to the course pictures: off until chosen,
 * offered only with WebGL and without reduced motion, and the choice lasts while the
 * lesson stays open. Any failure brings the picture back for the rest of the visit.
 */
export function useSalah3D(sceneStep: SalahSceneStepId | null, stepSlug: string): Salah3D {
  const [capable, setCapable] = useState(false);
  const [failed, setFailed] = useState(false);
  const [chosen, setChosen] = useState(false);
  const [ready, setReady] = useState(false);
  const [playing, setPlaying] = useState(true);
  const [speed, setSpeed] = useState<SalahSceneSpeed>(1);
  const [resetKey, setResetKey] = useState(0);
  const [notice, setNotice] = useState(false);
  const [slot, setSlot] = useState<HTMLDivElement | null>(null);

  useEffect(() => {
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => setCapable("WebGLRenderingContext" in window && !reduced.matches);
    update();
    reduced.addEventListener("change", update);
    return () => reduced.removeEventListener("change", update);
  }, []);

  useEffect(() => setNotice(false), [stepSlug]);

  const fail = useCallback(() => {
    setFailed(true);
    setNotice(true);
    setReady(false);
  }, []);
  const markReady = useCallback(() => setReady(true), []);

  const active = chosen && capable && !failed;
  const choose = (threeD: boolean) => {
    if (threeD && !hasWebgl()) {
      fail();
      return;
    }
    setChosen(threeD);
    if (!threeD) setReady(false);
  };

  return {
    offered: capable && !failed && sceneStep !== null,
    shown: active && sceneStep !== null,
    ready,
    playing,
    speed,
    notice,
    slot: setSlot,
    choose,
    togglePlaying: () => setPlaying((value) => !value),
    cycleSpeed: () => setSpeed(nextSalahSceneSpeed),
    resetView: () => setResetKey((value) => value + 1),
    stage: active ? (
      <Salah3DStage
        slot={slot}
        step={sceneStep}
        playing={playing}
        speed={speed}
        resetKey={resetKey}
        onReady={markReady}
        onError={fail}
      />
    ) : null,
  };
}
