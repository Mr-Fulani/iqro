"use client";

import { useMemo, useSyncExternalStore } from "react";

import {
  parseSalahProgress,
  SALAH_COURSE_SLUG,
  SALAH_PROGRESS_EVENT,
  salahProgressStorageKey,
  type SalahProgress,
} from "./salah";

function subscribe(onChange: () => void): () => void {
  window.addEventListener("storage", onChange);
  window.addEventListener(SALAH_PROGRESS_EVENT, onChange);
  return () => {
    window.removeEventListener("storage", onChange);
    window.removeEventListener(SALAH_PROGRESS_EVENT, onChange);
  };
}

/** Local course progress; `null` in server HTML and during hydration. */
export function useSalahProgress(courseSlug: string = SALAH_COURSE_SLUG): SalahProgress | null {
  const raw = useSyncExternalStore(
    subscribe,
    () => {
      try {
        return window.localStorage.getItem(salahProgressStorageKey(courseSlug)) ?? "";
      } catch {
        return "";
      }
    },
    () => null,
  );
  return useMemo(() => (raw === null ? null : parseSalahProgress(raw)), [raw]);
}
