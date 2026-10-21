"use client";

// Loaded with next/dynamic only after the visitor picks «3D»: this module pulls in three.js.
import { useEffect, useEffectEvent, useState } from "react";

import { mount, type SalahScene, type SalahSceneStepId } from "../lib/salah3d/salah-scene.js";

export type Salah3DStageProps = {
  /** The current step's place for the canvas; null when the step has no 3D. */
  slot: HTMLElement | null;
  step: SalahSceneStepId | null;
  playing: boolean;
  speed: number;
  /** Changes when the visitor asks for the starting view again. */
  resetKey: number;
  onReady: () => void;
  onError: () => void;
};

type Stage = { canvas: HTMLCanvasElement; scene: SalahScene };

/**
 * One canvas and scene for the whole lesson: the canvas moves into the current step's
 * slot, so stepping on keeps the WebGL context instead of building a new one per step.
 */
export default function Salah3DStage({ slot, step, playing, speed, resetKey, onReady, onError }: Salah3DStageProps) {
  const [stage, setStage] = useState<Stage | null>(null);
  const ready = useEffectEvent(onReady);
  const failed = useEffectEvent(onError);
  const initial = useEffectEvent(() => ({ step, speed }));

  useEffect(() => {
    const canvas = document.createElement("canvas");
    canvas.className = "salah-3d-canvas";
    // The picture underneath keeps describing the step to assistive technology.
    canvas.setAttribute("aria-hidden", "true");
    let scene: SalahScene;
    try {
      scene = mount(canvas, { view: "full", pageScroll: true, ...initial() });
    } catch {
      failed();
      return;
    }
    const lost = (event: Event) => {
      event.preventDefault();
      failed();
    };
    canvas.addEventListener("webglcontextlost", lost);
    setStage({ canvas, scene });
    return () => {
      canvas.removeEventListener("webglcontextlost", lost);
      scene.dispose();
      canvas.remove();
      setStage(null);
    };
  }, []);

  useEffect(() => {
    if (!stage || !slot) return;
    slot.append(stage.canvas);
    const frame = requestAnimationFrame(() => ready());
    return () => {
      cancelAnimationFrame(frame);
      stage.canvas.remove();
    };
  }, [slot, stage]);

  useEffect(() => {
    if (stage && step) stage.scene.setStep(step);
  }, [stage, step]);

  useEffect(() => {
    stage?.scene.setSpeed(speed);
  }, [speed, stage]);

  useEffect(() => {
    if (resetKey) stage?.scene.resetCamera();
  }, [resetKey, stage]);

  // Runs only while chosen, shown in a step and the tab is visible.
  useEffect(() => {
    if (!stage) return;
    const sync = () => {
      const running = playing && slot !== null && !document.hidden;
      if (running) stage.scene.play();
      else stage.scene.pause();
      stage.canvas.dataset.running = String(running);
    };
    sync();
    document.addEventListener("visibilitychange", sync);
    return () => document.removeEventListener("visibilitychange", sync);
  }, [playing, slot, stage]);

  return null;
}
