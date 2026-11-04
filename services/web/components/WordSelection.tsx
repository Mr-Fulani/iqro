"use client";

import { useEffect, useRef } from "react";
import { useI18n } from "../lib/i18n-context";
import {
  compareWords,
  parseWordKey,
  sameWord,
  sameWordRange,
  wordKey,
  wordRangeBetween,
  type QuranWord,
  type QuranWordRange,
} from "../lib/word-range";

const LONG_PRESS_MS = 300;

/** How far, in screen pixels, a finger may land beside a handle's line and under its knob. */
const HANDLE_REACH_X = 24;
const HANDLE_REACH_BELOW = 32;

/**
 * The selection handle near a point. Found by its box, not by the touch's
 * target: a Mushaf line is scaled into a layer of its own, so the next line
 * covers the knob hanging under this one, and the touch lands on its word.
 */
function handleNear(element: HTMLElement, x: number, y: number): HTMLElement | null {
  let best: HTMLElement | null = null;
  let distance = Infinity;
  for (const handle of element.querySelectorAll<HTMLElement>(".word-range-handle")) {
    const box = handle.getBoundingClientRect();
    if (x < box.left - HANDLE_REACH_X || x > box.right + HANDLE_REACH_X) continue;
    if (y < box.top || y > box.bottom + HANDLE_REACH_BELOW) continue;
    const away = Math.abs(x - (box.left + box.right) / 2);
    if (away < distance) {
      best = handle;
      distance = away;
    }
  }
  return best;
}

function setSelectingFlag(on: boolean) {
  // MushafGestureSurface reads it: a finger pulling a selection turns no page.
  if (on) document.documentElement.dataset.wordSelecting = "true";
  else delete document.documentElement.dataset.wordSelecting;
}

/**
 * The word under a finger that pulls a selection, larger, above the finger:
 * a phone's text loupe. It shows a copy of the word in its own font.
 */
function createLoupe() {
  let loupe: HTMLElement | null = null;
  return {
    show(container: HTMLElement, word: QuranWord, x: number, y: number) {
      const key = wordKey(word);
      const source = container.querySelector<HTMLElement>(`[data-word-key="${key}"]`);
      if (!source) return;
      if (!loupe) {
        loupe = document.createElement("div");
        loupe.className = "word-range-loupe";
        loupe.dataset.testid = "word-range-loupe";
        loupe.setAttribute("aria-hidden", "true");
        document.body.append(loupe);
      }
      if (loupe.dataset.word !== key) {
        const copy = source.cloneNode(true) as HTMLElement;
        copy.classList.remove("is-word-selected", "is-word-playing");
        loupe.replaceChildren(copy);
        loupe.dataset.word = key;
        loupe.style.fontFamily = getComputedStyle(source).fontFamily;
      }
      loupe.style.left = `${x}px`;
      loupe.style.top = `${y - 48}px`;
    },
    hide() {
      loupe?.remove();
      loupe = null;
    },
  };
}

function wordOfTarget(target: EventTarget | null, container: HTMLElement): QuranWord | null {
  if (!(target instanceof Element)) return null;
  const element = target.closest<HTMLElement>("[data-word-key]");
  return element && container.contains(element) ? parseWordKey(element.dataset.wordKey) : null;
}

/**
 * Word selection inside `element`, whose words carry `data-word-key`.
 * Touch: hold a word 0.3 s, then move the finger on, with a loupe over it.
 * Mouse: double-click a word, Shift+click another. Both: drag a
 * `.word-range-handle`. A click beside a selection clears it, as with
 * selected text; one on a Mushaf ayah number still opens the ayah.
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
    let handle: { id: number; anchor: QuranWord; grabY: number; touch: boolean } | null = null;
    const loupe = createLoupe();

    // The word under the finger, even under the selection bar or a handle above it.
    const wordAt = (x: number, y: number) => {
      for (const target of document.elementsFromPoint(x, y)) {
        const word = wordOfTarget(target, element);
        if (word) return word;
      }
      return null;
    };
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
      const touch = event.touches[0];
      if (latest.current.range && handleNear(element, touch.clientX, touch.clientY)) return;
      const word = wordOfTarget(event.target, element);
      if (!word) return;
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
      // A finger on a handle pulls it: the page neither scrolls nor turns.
      if (handle) {
        if (event.cancelable) event.preventDefault();
        return;
      }
      if (!anchor) {
        if (timer && Math.hypot(touch.clientX - start.x, touch.clientY - start.y) > 10) clearTimer();
        return;
      }
      if (event.cancelable) event.preventDefault();
      const word = wordAt(touch.clientX, touch.clientY);
      if (!word) return;
      extend(anchor, word);
      loupe.show(element, word, touch.clientX, touch.clientY);
    };
    const touchEnd = () => {
      clearTimer();
      loupe.hide();
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
      // An ayah number in the Mushaf opens its ayah, selection or not.
      if (event.target instanceof Element && event.target.closest(".qf-mushaf-word.is-ayah-end")) return;
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
      const current = latest.current.range;
      if (!current) return;
      const target = (event.target instanceof Element ? event.target.closest<HTMLElement>(".word-range-handle") : null)
        ?? handleNear(element, event.clientX, event.clientY);
      if (!target) return;
      event.preventDefault();
      event.stopPropagation();
      clearTimer();
      const word = target.closest<HTMLElement>("[data-word-key]")?.getBoundingClientRect();
      handle = {
        id: event.pointerId,
        anchor: target.dataset.handle === "start" ? current.end : current.start,
        grabY: word ? event.clientY - (word.top + word.height / 2) : 0,
        touch: event.pointerType === "touch",
      };
      try { target.setPointerCapture(event.pointerId); } catch { /* A synthetic pointer has no capture. */ }
      setSelectingFlag(true);
    };
    const pointerMove = (event: PointerEvent) => {
      if (!handle || event.pointerId !== handle.id) return;
      event.preventDefault();
      const word = wordAt(event.clientX, event.clientY - handle.grabY);
      if (!word) return;
      extend(handle.anchor, word);
      if (handle.touch) loupe.show(element, word, event.clientX, event.clientY - handle.grabY);
    };
    const pointerUp = (event: PointerEvent) => {
      if (!handle || event.pointerId !== handle.id) return;
      handle = null;
      loupe.hide();
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
      loupe.hide();
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

