"use client";

import { type ReactNode, useEffect, useLayoutEffect, useRef } from "react";

type Gesture = {
  source: "pointer" | "touch";
  id: number;
  x: number;
  y: number;
  time: number;
  axis: "pending" | "horizontal" | "vertical";
  moved: boolean;
};

/** Own the gesture on the stationary viewport, not on moving ayah hitboxes.
 * Touch events complete phone gestures even when the browser cancels its
 * parallel pointer stream. Only horizontal touch movement prevents scrolling. */
export function MushafGestureSurface({ children, label, onTurnPage }: {
  children: ReactNode;
  label: string;
  onTurnPage: (direction: "next" | "previous") => void;
}) {
  const surface = useRef<HTMLDivElement>(null);
  const turnPage = useRef(onTurnPage);
  useLayoutEffect(() => { turnPage.current = onTurnPage; }, [onTurnPage]);

  useEffect(() => {
    const element = surface.current;
    if (!element) return;
    let gesture: Gesture | null = null;
    let suppressClick = false;

    const resetDrag = () => {
      delete element.dataset.dragging;
      element.style.removeProperty("--reader-drag-x");
    };
    const cancel = () => {
      gesture = null;
      suppressClick = true;
      resetDrag();
    };
    const begin = (source: Gesture["source"], id: number, x: number, y: number, time: number, target: EventTarget | null) => {
      gesture = null;
      resetDrag();
      if ((window.visualViewport?.scale ?? 1) > 1.05 || !(target instanceof Element)) {
        suppressClick = true;
        return;
      }
      // Ayahs support both a tap and a drag. Other controls keep their own input.
      if (target.closest("button, a, input, select, [role='button']") && !target.closest("[data-ayah-key]")) return;
      suppressClick = false;
      gesture = { source, id, x, y, time, axis: "pending", moved: false };
    };
    const move = (x: number, y: number, event: Event) => {
      if (!gesture) return;
      const dx = x - gesture.x;
      const dy = y - gesture.y;
      if (Math.max(Math.abs(dx), Math.abs(dy)) >= 8) {
        gesture.moved = true;
        suppressClick = true;
      }
      if (gesture.axis === "pending") {
        if (Math.abs(dx) >= 8 && Math.abs(dx) >= Math.abs(dy) * 1.15) gesture.axis = "horizontal";
        else if (Math.abs(dy) >= 12 && Math.abs(dy) > Math.abs(dx) * 1.15) gesture.axis = "vertical";
      }
      if (gesture.axis !== "horizontal") return;
      if (event.cancelable) event.preventDefault();
      if (gesture.source === "pointer" && !element.hasPointerCapture(gesture.id)) {
        try { element.setPointerCapture(gesture.id); } catch { /* A synthetic pointer has no capture. */ }
      }
      element.dataset.dragging = "true";
      element.style.setProperty("--reader-drag-x", `${Math.max(-64, Math.min(64, dx * .45))}px`);
    };
    const end = (x: number, y: number, event: Event) => {
      const finished = gesture;
      if (!finished) return;
      move(x, y, event);
      gesture = null;
      resetDrag();
      if (finished.source === "pointer" && element.hasPointerCapture(finished.id)) element.releasePointerCapture(finished.id);
      if (finished.moved && event.cancelable) event.preventDefault();
      const dx = x - finished.x;
      const threshold = Math.max(24, Math.min(40, element.clientWidth * .06));
      const flick = Math.abs(dx) >= 16 && event.timeStamp - finished.time <= 250;
      if (finished.axis !== "horizontal" || (!flick && Math.abs(dx) < threshold)) return;
      suppressClick = true;
      turnPage.current(dx > 0 ? "next" : "previous");
    };

    const pointerDown = (event: PointerEvent) => {
      if (!event.isPrimary) { cancel(); return; }
      if (event.button !== 0) return;
      begin("pointer", event.pointerId, event.clientX, event.clientY, event.timeStamp, event.target);
    };
    const pointerMove = (event: PointerEvent) => {
      if (gesture?.source === "pointer" && gesture.id === event.pointerId) move(event.clientX, event.clientY, event);
    };
    const pointerUp = (event: PointerEvent) => {
      if (gesture?.source === "pointer" && gesture.id === event.pointerId) end(event.clientX, event.clientY, event);
    };
    const pointerCancel = () => {
      if (gesture?.source === "pointer") cancel();
    };
    const touchStart = (event: TouchEvent) => {
      if (event.touches.length !== 1) { cancel(); return; }
      const touch = event.touches[0];
      begin("touch", touch.identifier, touch.clientX, touch.clientY, event.timeStamp, event.target);
    };
    const touchMove = (event: TouchEvent) => {
      if (event.touches.length !== 1) { cancel(); return; }
      if (gesture?.source !== "touch") return;
      const touch = [...event.touches].find((point) => point.identifier === gesture?.id);
      if (touch) move(touch.clientX, touch.clientY, event);
    };
    const touchEnd = (event: TouchEvent) => {
      if (gesture?.source !== "touch") return;
      const touch = [...event.changedTouches].find((point) => point.identifier === gesture?.id);
      if (touch) end(touch.clientX, touch.clientY, event);
    };
    const click = (event: MouseEvent) => {
      // Keep rejecting compatibility clicks until a fresh press. Some mobile
      // browsers report detail=0, so keyboard activation resets this explicitly.
      if (!suppressClick) return;
      event.preventDefault();
      event.stopPropagation();
    };
    const keyDown = (event: KeyboardEvent) => {
      suppressClick = false;
      if (event.key === "ArrowRight" || event.key === "ArrowLeft") {
        event.preventDefault();
        turnPage.current(event.key === "ArrowRight" ? "next" : "previous");
      }
    };
    const dragStart = (event: DragEvent) => { event.preventDefault(); };
    const passive = { capture: true, passive: true };
    const active = { capture: true, passive: false };
    const orientation = window.matchMedia("(orientation: landscape)");
    element.addEventListener("pointerdown", pointerDown, passive);
    element.addEventListener("pointermove", pointerMove, active);
    element.addEventListener("pointerup", pointerUp, active);
    element.addEventListener("pointercancel", pointerCancel, passive);
    element.addEventListener("lostpointercapture", pointerCancel, passive);
    element.addEventListener("touchstart", touchStart, passive);
    element.addEventListener("touchmove", touchMove, active);
    element.addEventListener("touchend", touchEnd, active);
    element.addEventListener("touchcancel", cancel, passive);
    element.addEventListener("click", click, true);
    element.addEventListener("keydown", keyDown, true);
    element.addEventListener("dragstart", dragStart, true);
    window.addEventListener("blur", cancel);
    // Mobile browser bars can resize the viewport during a valid gesture.
    // Cancel only an actual rotation, not those height-only changes.
    orientation.addEventListener("change", cancel);
    return () => {
      element.removeEventListener("pointerdown", pointerDown, true);
      element.removeEventListener("pointermove", pointerMove, true);
      element.removeEventListener("pointerup", pointerUp, true);
      element.removeEventListener("pointercancel", pointerCancel, true);
      element.removeEventListener("lostpointercapture", pointerCancel, true);
      element.removeEventListener("touchstart", touchStart, true);
      element.removeEventListener("touchmove", touchMove, true);
      element.removeEventListener("touchend", touchEnd, true);
      element.removeEventListener("touchcancel", cancel, true);
      element.removeEventListener("click", click, true);
      element.removeEventListener("keydown", keyDown, true);
      element.removeEventListener("dragstart", dragStart, true);
      window.removeEventListener("blur", cancel);
      orientation.removeEventListener("change", cancel);
    };
  }, []);

  return <div ref={surface} className="mushaf-page-container" data-swipe-next="right" tabIndex={0} aria-label={label}>{children}</div>;
}
