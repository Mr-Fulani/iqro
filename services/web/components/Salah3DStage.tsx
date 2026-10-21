"use client";

// Loaded with next/dynamic only once the visitor acts on the page: this module pulls in three.js.
import { useEffect, useEffectEvent, useState } from "react";

import type { SalahSceneView } from "../lib/salah";
import { mount, type SalahScene, type SalahSceneStepId } from "../lib/salah3d/salah-scene.js";

export type Salah3DStageProps = {
  /** The current step's place for the canvas; null when the step has no 3D. */
  slot: HTMLElement | null;
  view: SalahSceneView;
  /** The pose whose movement plays once (the full view only). */
  step: SalahSceneStepId | null;
  playing: boolean;
  /** Changes when the pose should play from its start: a new step or a replay. */
  run: number;
  speed: number;
  onReady: () => void;
  /** The pose has played and holds its last frame. */
  onEnded: () => void;
  onError: () => void;
};

type Stage = { canvas: HTMLCanvasElement; scene: SalahScene };

/**
 * One canvas and scene for the whole lesson: the canvas moves into the current step's
 * slot, so stepping on keeps the WebGL context instead of building a new one per step.
 */
export default function Salah3DStage({
  slot,
  view,
  step,
  playing,
  run,
  speed,
  onReady,
  onEnded,
  onError,
}: Salah3DStageProps) {
  const [stage, setStage] = useState<Stage | null>(null);
  const ready = useEffectEvent(onReady);
  const ended = useEffectEvent(onEnded);
  const failed = useEffectEvent(onError);
  const initial = useEffectEvent(() => ({ view, step, speed }));

  useEffect(() => {
    const canvas = document.createElement("canvas");
    canvas.className = "salah-3d-canvas";
    // The picture underneath keeps describing the step to assistive technology.
    canvas.setAttribute("aria-hidden", "true");
    let scene: SalahScene;
    try {
      scene = mount(canvas, { pageScroll: true, ...initial(), onEnd: () => ended() });
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

  // A new pose puts the camera in place at once; replaying the same pose lets it glide back.
  useEffect(() => {
    if (stage && step) stage.scene.setStep(step);
  }, [stage, step]);

  // Every step, and a replay, plays the pose from its start.
  useEffect(() => {
    if (stage && step) stage.scene.replay();
  }, [run, stage, step]);

  useEffect(() => {
    stage?.scene.setSpeed(speed);
  }, [speed, stage]);

  // Runs only while moving, shown in a step and the tab is visible.
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
