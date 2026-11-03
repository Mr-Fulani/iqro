"use client";

import { useEffect, useRef } from "react";
import { useI18n } from "../lib/i18n-context";
import {
  compareWords,
  parseWordKey,
  sameWord,
  sameWordRange,
  wordRangeBetween,
  type QuranWord,
  type QuranWordRange,
} from "../lib/word-range";

const LONG_PRESS_MS = 450;

function setSelectingFlag(on: boolean) {
  // MushafGestureSurface reads it: a finger pulling a selection turns no page.
  if (on) document.documentElement.dataset.wordSelecting = "true";
  else delete document.documentElement.dataset.wordSelecting;
}

function wordOfTarget(target: EventTarget | null, container: HTMLElement): QuranWord | null {
  if (!(target instanceof Element)) return null;
  const element = target.closest<HTMLElement>("[data-word-key]");
  return element && container.contains(element) ? parseWordKey(element.dataset.wordKey) : null;
}

/**
 * Word selection inside `element`, whose words carry `data-word-key`.
 * Touch: hold a word, then move the finger on. Mouse: double-click a word,
 * Shift+click another. Both: drag a `.word-range-handle`. A click beside a
 * selection clears it, as with selected text.
 */
export function useWordSelection(
  element: HTMLElement | null,
  range: QuranWordRange | null,
  onRange: (range: QuranWordRange) => void,
  onClear: () => void,
) {
  const latest = useRef({ range, onRange, onClear });
  useEffect(() => { latest.current = { range, onRange, onClear }; });

  useEffect(() => {
    if (!element) return;
    let timer = 0;
    let anchor: QuranWord | null = null;
    let start = { x: 0, y: 0 };
    let suppressClickUntil = 0;
    let handle: { id: number; anchor: QuranWord; grabY: number } | null = null;

    const wordAt = (x: number, y: number) => wordOfTarget(document.elementFromPoint(x, y), element);
    const extend = (from: QuranWord, to: QuranWord) => {
      const next = wordRangeBetween(from, to);
      if (next && !sameWordRange(next, latest.current.range)) latest.current.onRange(next);
    };
    const clearTimer = () => {
      window.clearTimeout(timer);
      timer = 0;
    };

    const touchStart = (event: TouchEvent) => {
      clearTimer();
      if (event.touches.length !== 1 || handle) return;
      if (event.target instanceof Element && event.target.closest(".word-range-handle")) return;
      const word = wordOfTarget(event.target, element);
      if (!word) return;
      const touch = event.touches[0];
      start = { x: touch.clientX, y: touch.clientY };
      timer = window.setTimeout(() => {
        timer = 0;
        anchor = word;
        setSelectingFlag(true);
        navigator.vibrate?.(10);
        window.getSelection()?.removeAllRanges();
        latest.current.onRange({ start: word, end: word });
      }, LONG_PRESS_MS);
    };
    const touchMove = (event: TouchEvent) => {
      const touch = event.touches[0];
      if (!touch) return;
      if (!anchor) {
        if (timer && Math.hypot(touch.clientX - start.x, touch.clientY - start.y) > 10) clearTimer();
        return;
      }
      if (event.cancelable) event.preventDefault();
      const word = wordAt(touch.clientX, touch.clientY);
      if (word) extend(anchor, word);
    };
    const touchEnd = () => {
      clearTimer();
      if (!anchor) return;
      anchor = null;
      suppressClickUntil = Date.now() + 600;
      window.setTimeout(() => setSelectingFlag(false));
    };
    const contextMenu = (event: Event) => {
      if (anchor || timer || Date.now() < suppressClickUntil) event.preventDefault();
    };
    const click = (event: MouseEvent) => {
      if (Date.now() < suppressClickUntil) {
        event.preventDefault();
        event.stopPropagation();
        return;
      }
      const current = latest.current.range;
      const word = wordOfTarget(event.target, element);
      if (event.shiftKey && word && current) {
        event.preventDefault();
        event.stopPropagation();
        window.getSelection()?.removeAllRanges();
        extend(compareWords(word, current.start) < 0 ? current.end : current.start, word);
        return;
      }
      // Controls beside the text (an ayah card's buttons) keep the selection and their click.
      const onText = event.target instanceof Element
        && Boolean(event.target.closest("[data-word-key], [data-ayah-key], .quran-arabic-text, .qf-mushaf-view"));
      if (current && onText && event.detail <= 1) {
        event.preventDefault();
        event.stopPropagation();
        latest.current.onClear();
      }
    };
    const doubleClick = (event: MouseEvent) => {
      const word = wordOfTarget(event.target, element);
      if (!word) return;
      event.preventDefault();
      window.getSelection()?.removeAllRanges();
      latest.current.onRange({ start: word, end: word });
    };
    const pointerDown = (event: PointerEvent) => {
      const target = event.target instanceof Element ? event.target.closest<HTMLElement>(".word-range-handle") : null;
      const current = latest.current.range;
      if (!target || !current) return;
      event.preventDefault();
      event.stopPropagation();
      clearTimer();
      const word = target.closest<HTMLElement>("[data-word-key]")?.getBoundingClientRect();
      handle = {
        id: event.pointerId,
        anchor: target.dataset.handle === "start" ? current.end : current.start,
        grabY: word ? event.clientY - (word.top + word.height / 2) : 0,
      };
      try { target.setPointerCapture(event.pointerId); } catch { /* A synthetic pointer has no capture. */ }
      setSelectingFlag(true);
    };
    const pointerMove = (event: PointerEvent) => {
      if (!handle || event.pointerId !== handle.id) return;
      event.preventDefault();
      const word = wordAt(event.clientX, event.clientY - handle.grabY);
      if (word) extend(handle.anchor, word);
    };
    const pointerUp = (event: PointerEvent) => {
      if (!handle || event.pointerId !== handle.id) return;
      handle = null;
      suppressClickUntil = Date.now() + 300;
      setSelectingFlag(false);
    };

    const passive = { passive: true };
    const active = { passive: false };
    element.addEventListener("touchstart", touchStart, passive);
    element.addEventListener("touchmove", touchMove, active);
    element.addEventListener("touchend", touchEnd, passive);
    element.addEventListener("touchcancel", touchEnd, passive);
    element.addEventListener("contextmenu", contextMenu);
    element.addEventListener("click", click, true);
    element.addEventListener("dblclick", doubleClick);
    element.addEventListener("pointerdown", pointerDown, true);
    element.addEventListener("pointermove", pointerMove, active);
    element.addEventListener("pointerup", pointerUp);
    element.addEventListener("pointercancel", pointerUp);
    return () => {
      clearTimer();
      setSelectingFlag(false);
      element.removeEventListener("touchstart", touchStart);
      element.removeEventListener("touchmove", touchMove);
      element.removeEventListener("touchend", touchEnd);
      element.removeEventListener("touchcancel", touchEnd);
      element.removeEventListener("contextmenu", contextMenu);
      element.removeEventListener("click", click, true);
      element.removeEventListener("dblclick", doubleClick);
      element.removeEventListener("pointerdown", pointerDown, true);
      element.removeEventListener("pointermove", pointerMove);
      element.removeEventListener("pointerup", pointerUp);
      element.removeEventListener("pointercancel", pointerUp);
    };
  }, [element]);
}

/** The handles of `range` that belong inside the element of `word`. */
export function WordRangeHandles({ range, word }: { range: QuranWordRange | null; word: QuranWord }) {
  const { t } = useI18n();
  if (!range) return null;
  return (
    <>
      {sameWord(range.start, word) && (
        <span className="word-range-handle is-start" data-handle="start" aria-label={t("wordRange.handleStart")} />
      )}
      {sameWord(range.end, word) && (
        <span className="word-range-handle is-end" data-handle="end" aria-label={t("wordRange.handleEnd")} />
      )}
    </>
  );
}

