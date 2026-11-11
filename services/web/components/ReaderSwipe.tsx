"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";

import {
  READER_SWIPE_HINT_DELAY_MS,
  READER_SWIPE_HINT_LIMIT,
  READER_SWIPE_HINT_MS,
  READER_SWIPE_HINT_STILL_MS,
  READER_SWIPE_HINT_STORAGE_KEY,
  parseReaderSwipeHint,
  readerSwipeHintOpacity,
  readerSwipeHintPull,
} from "../lib/reader-swipe-hint";

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

function readSwipeHint() {
  try {
    return parseReaderSwipeHint(window.localStorage.getItem(READER_SWIPE_HINT_STORAGE_KEY));
  } catch {
    // Storage blocked: nothing is remembered, so the hint is not shown at all.
    return READER_SWIPE_HINT_LIMIT;
  }
}

function writeSwipeHint(shown: number) {
  try {
    window.localStorage.setItem(READER_SWIPE_HINT_STORAGE_KEY, String(shown));
  } catch {
    // Storage blocked: nothing to remember.
  }
}

/** The reader swiped the text: the hint has nothing left to teach. */
export function markReaderSwipeHintLearned() {
  writeSwipeHint(READER_SWIPE_HINT_LIMIT);
}

export type ReaderSwipeHintState = { offset: number; opacity: number };

/**
 * Shows on a touch screen that the text can be swiped: a moment after it is
 * `ready` and lies across the middle of the screen, once a visit and `READER_SWIPE_HINT_LIMIT` times in all, the text
 * moves by the returned offset to the right, then to the left. Any touch ends
 * it at once. With reduced motion the offset stays 0 and the hint only stands
 * for a while.
 */
export function useReaderSwipeHint(element: HTMLElement | null, ready: boolean): ReaderSwipeHintState | null {
  const [hint, setHint] = useState<ReaderSwipeHintState | null>(null);
  const offered = useRef(false);

  useEffect(() => {
    if (!element || !ready || offered.current || !touchReader()) return;
    let frame = 0;
    let timer: ReturnType<typeof setTimeout> | undefined;
    let still: ReturnType<typeof setTimeout> | undefined;
    const end = () => {
      cancelAnimationFrame(frame);
      clearTimeout(still);
      window.removeEventListener("pointerdown", end, true);
      window.removeEventListener("touchstart", end, true);
      setHint(null);
    };
    const offer = () => {
      const shown = readSwipeHint();
      if (shown >= READER_SWIPE_HINT_LIMIT) return;
      // The settings above the text, or another tab: wait for the text itself.
      const { top, bottom } = element.getBoundingClientRect();
      const middle = window.innerHeight / 2;
      if (document.visibilityState !== "visible" || top > middle || bottom < middle) {
        timer = setTimeout(offer, READER_SWIPE_HINT_DELAY_MS);
        return;
      }
      offered.current = true;
      writeSwipeHint(shown + 1);
      window.addEventListener("pointerdown", end, true);
      window.addEventListener("touchstart", end, true);
      if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
        setHint({ offset: 0, opacity: 1 });
        still = setTimeout(end, READER_SWIPE_HINT_STILL_MS);
        return;
      }
      // Far enough for the strip under the text to name where it leads.
      const distance = Math.min(window.innerWidth * 0.36, 150);
      const began = performance.now();
      const step = (now: number) => {
        const progress = (now - began) / READER_SWIPE_HINT_MS;
        if (progress >= 1) {
          end();
          return;
        }
        setHint({ offset: readerSwipeHintPull(progress) * distance, opacity: readerSwipeHintOpacity(progress) });
        frame = requestAnimationFrame(step);
      };
      frame = requestAnimationFrame(step);
    };
    timer = setTimeout(offer, READER_SWIPE_HINT_DELAY_MS);
    return () => {
      clearTimeout(timer);
      end();
    };
  }, [element, ready]);

  return hint;
}

/**
 * A hand with its forefinger out, moving with the text it pulls, and under it
 * the words on what a swipe opens. The outline is the app's
 * (_SwipeHandPainter in reader_page_turn.dart).
 */
export function ReaderSwipeHint({ hint, caption }: { hint: ReaderSwipeHintState | null; caption: string }) {
  if (!hint) return null;
  return (
    <div className="reader-swipe-hint" style={{ opacity: hint.opacity }} data-testid="reader-swipe-hint">
      <svg
        className="reader-swipe-hint-hand"
        viewBox="0 0 48 56"
        aria-hidden="true"
        // The finger leads the text a little, as a real one does.
        style={{ transform: `translateX(${hint.offset * 1.15}px)` }}
      >
        <circle cx="21.5" cy="8" r="7.5" />
        <path d="M18 7a3.5 3.5 0 0 1 7 0v14a3.2 3.2 0 0 1 6.4 0v2a3 3 0 0 1 6 0v2a2.8 2.8 0 0 1 5.6 0v12c0 9-6 15-14 15h-3c-5 0-8-3-11-8l-7-10c-1.5-2.5 0-5 2.5-5.5 2-.4 3.5.5 5 2l2.5 2.5z" />
      </svg>
      <p className="reader-swipe-hint-caption" role="status">{caption}</p>
    </div>
  );
}
