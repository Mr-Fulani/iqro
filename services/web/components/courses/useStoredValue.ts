"use client";

import { useSyncExternalStore } from "react";

/** Sent after this tab writes a vote or a rating; other tabs hear `storage`. */
export const COURSES_FEEDBACK_EVENT = "iqro:courses-feedback";

function subscribe(onChange: () => void) {
  window.addEventListener("storage", onChange);
  window.addEventListener(COURSES_FEEDBACK_EVENT, onChange);
  return () => {
    window.removeEventListener("storage", onChange);
    window.removeEventListener(COURSES_FEEDBACK_EVENT, onChange);
  };
}

/** The raw localStorage value; `null` in server HTML and during hydration, "" when absent. */
export function useStoredValue(key: string): string | null {
  return useSyncExternalStore(
    subscribe,
    () => {
      try {
        return window.localStorage.getItem(key) ?? "";
      } catch {
        return "";
      }
    },
    () => null,
  );
}

export function announceStoredValue(): void {
  window.dispatchEvent(new Event(COURSES_FEEDBACK_EVENT));
}
