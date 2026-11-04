"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";

export type ReaderSwipeDirection = "right" | "left";

/** The strip along each side where a swipe is the browser's back gesture. */
export const READER_SWIPE_EDGE = 30;

/** Swipes are for touch screens, phones and tablets: a mouse drag selects text. */
function touchReader() {
  return typeof window !== "undefined" && window.matchMedia("(pointer: coarse)").matches;
}

function selectingText() {
  if (document.documentElement.dataset.wordSelecting === "true") return true;
  const selection = window.getSelection();
  return Boolean(selection && !selection.isCollapsed);
}

/**
 * A horizontal swipe across the Quran text on a touch screen. The text slides
 * with the finger, a little behind; far enough (a third of the width) or
 * flicked, it calls `onSwipe` with the direction and the element first
 * touched. A swipe from the very edge, a finger pulling word handles or a text
 * selection are left alone, and so is a gesture that starts up or down: that
 * is the page's own scroll.
 */
export function useReaderSwipe(
  element: HTMLElement | null,
  {
    enabled,
    right,
    left,
    onSwipe,
  }: {
    enabled: boolean;
    right: boolean;
    left: boolean;
    onSwipe: (direction: ReaderSwipeDirection, target: EventTarget | null) => void;
  },
) {
  const [offset, setOffset] = useState(0);
  const latest = useRef({ enabled, right, left, onSwipe });
  useEffect(() => { latest.current = { enabled, right, left, onSwipe }; });

  useEffect(() => {
    if (!element) return;
    let start: { x: number; y: number; time: number; target: EventTarget | null } | null = null;
    let horizontal: boolean | null = null;
    let pulled = 0;

    const reset = () => {
      start = null;
      horizontal = null;
      pulled = 0;
      setOffset(0);
    };
    const touchStart = (event: TouchEvent) => {
      reset();
      const touch = event.touches[0];
      if (event.touches.length !== 1 || !touch || !latest.current.enabled || !touchReader()) return;
      if (touch.clientX < READER_SWIPE_EDGE || touch.clientX > window.innerWidth - READER_SWIPE_EDGE) return;
      if (selectingText()) return;
      start = { x: touch.clientX, y: touch.clientY, time: event.timeStamp, target: event.target };
    };
    const touchMove = (event: TouchEvent) => {
      const touch = event.touches[0];
      if (!start || !touch) return;
      const dx = touch.clientX - start.x;
      const dy = touch.clientY - start.y;
      if (horizontal === null) {
        if (Math.hypot(dx, dy) < 10) return;
        horizontal = Math.abs(dx) > Math.abs(dy) * 1.5;
      }
      // A word held for selection, or up and down first: not a swipe.
      if (!horizontal || selectingText()) {
        if (horizontal) reset();
        return;
      }
      if (event.cancelable) event.preventDefault();
      pulled = dx;
      if (!latest.current.right) pulled = Math.min(0, pulled);
      if (!latest.current.left) pulled = Math.max(0, pulled);
      setOffset(Math.sign(pulled) * Math.min(Math.abs(pulled) * 0.6, window.innerWidth * 0.4));
    };
    const touchEnd = (event: TouchEvent) => {
      const began = start;
      const distance = pulled;
      reset();
      if (!began || distance === 0) return;
      const velocity = Math.abs(distance) / Math.max(1, event.timeStamp - began.time);
      if (Math.abs(distance) > window.innerWidth / 3 || velocity > 0.8) {
        latest.current.onSwipe(distance > 0 ? "right" : "left", began.target);
      }
    };

    element.addEventListener("touchstart", touchStart, { passive: true });
    element.addEventListener("touchmove", touchMove, { passive: false });
    element.addEventListener("touchend", touchEnd, { passive: true });
    element.addEventListener("touchcancel", reset, { passive: true });
    return () => {
      element.removeEventListener("touchstart", touchStart);
      element.removeEventListener("touchmove", touchMove);
      element.removeEventListener("touchend", touchEnd);
      element.removeEventListener("touchcancel", reset);
    };
  }, [element]);

  return offset;
}

/** What lies the way the finger pulls the text: shown in the strip it uncovers. */
export function ReaderSwipeReveal({
  offset,
  right,
  left,
}: {
  offset: number;
  right?: { icon: ReactNode; label: string };
  left?: { icon: ReactNode; label: string };
}) {
  const target = offset > 0 ? right : offset < 0 ? left : undefined;
  if (!target) return null;
  return (
    <div
      className={`reader-swipe-reveal is-${offset > 0 ? "right" : "left"}`}
      style={{ width: Math.abs(offset) }}
      aria-hidden="true"
    >
      <span className="reader-swipe-reveal-icon">{target.icon}</span>
      <span>{target.label}</span>
    </div>
  );
}
