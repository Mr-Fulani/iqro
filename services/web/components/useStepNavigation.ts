"use client";

import { useCallback, useState } from "react";
import { clampStep, stepKeyDelta } from "../lib/step-navigation";

/**
 * The current step of a lesson and the ways to turn it: buttons call `go`,
 * the arrow keys reach `onKeyDown` from wherever the lesson listens for them.
 */
export function useStepNavigation(count: number, direction: "ltr" | "rtl") {
  const [index, setIndex] = useState(0);
  const go = useCallback((delta: number) => {
    setIndex((current) => clampStep(current + delta, count));
  }, [count]);
  /** Turns the step on an arrow key; true when the key was used. */
  const onKeyDown = useCallback((event: KeyboardEvent) => {
    const delta = stepKeyDelta(event, direction);
    if (!delta) return false;
    event.preventDefault();
    go(delta);
    return true;
  }, [direction, go]);
  return { index: clampStep(index, count), setIndex, go, onKeyDown };
}
