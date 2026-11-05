"use client";

import { useRef } from "react";
import type { MouseEvent as ReactMouseEvent, PointerEvent as ReactPointerEvent } from "react";
import { SWIPE_TAP_SLOP, swipeCollapses } from "./mini-player";

/**
 * As in the app: a swipe on a player bar in any direction folds it. The
 * pointer is captured only once it moves, so a tap still reaches its button,
 * and a drag that falls short is not taken for a tap. Spread the handlers on
 * the bar; with `onSwipe` null the bar does not fold.
 */
export function useBarSwipe(onSwipe: (() => void) | null) {
  const barSwipe = useRef<{ pointerId: number; startX: number; startY: number; startedAt: number; moved: boolean } | null>(null);
  const dragWasSwipe = useRef(false);
  if (!onSwipe) return {};
  return {
    onPointerDown: (event: ReactPointerEvent<HTMLElement>) => {
      if (event.button !== 0) return;
      dragWasSwipe.current = false;
      barSwipe.current = {
        pointerId: event.pointerId,
        startX: event.clientX,
        startY: event.clientY,
        startedAt: performance.now(),
        moved: false,
      };
    },
    onPointerMove: (event: ReactPointerEvent<HTMLElement>) => {
      const swipe = barSwipe.current;
      if (!swipe || swipe.moved || event.pointerId !== swipe.pointerId) return;
      if (Math.hypot(event.clientX - swipe.startX, event.clientY - swipe.startY) < SWIPE_TAP_SLOP) return;
      swipe.moved = true;
      try {
        event.currentTarget.setPointerCapture(event.pointerId);
      } catch {
        // Synthetic pointers have no capture.
      }
    },
    onPointerUp: (event: ReactPointerEvent<HTMLElement>) => {
      const swipe = barSwipe.current;
      barSwipe.current = null;
      if (!swipe || event.pointerId !== swipe.pointerId) return;
      // The click that follows this pointerup, if any, comes before the next task.
      dragWasSwipe.current = swipe.moved;
      if (swipe.moved) setTimeout(() => {
        dragWasSwipe.current = false;
      }, 0);
      const sample = {
        deltaX: event.clientX - swipe.startX,
        deltaY: event.clientY - swipe.startY,
        durationMs: performance.now() - swipe.startedAt,
      };
      if (swipeCollapses(sample)) onSwipe();
    },
    onPointerCancel: () => {
      barSwipe.current = null;
    },
    onClickCapture: (event: ReactMouseEvent<HTMLElement>) => {
      if (!dragWasSwipe.current) return;
      dragWasSwipe.current = false;
      event.preventDefault();
      event.stopPropagation();
    },
  };
}
