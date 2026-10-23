"use client";

import { useMemo, useSyncExternalStore } from "react";

import { parseCourseProgress, type CourseProgress } from "./course-progress.ts";

/** Local course progress under `storageKey`; `null` in server HTML and during hydration. */
export function useCourseProgress(
  storageKey: string,
  event: string,
  isLessonSlug: (slug: string) => boolean,
): CourseProgress | null {
  const raw = useSyncExternalStore(
    (onChange) => {
      window.addEventListener("storage", onChange);
      window.addEventListener(event, onChange);
      return () => {
        window.removeEventListener("storage", onChange);
        window.removeEventListener(event, onChange);
      };
    },
    () => {
      try {
        return window.localStorage.getItem(storageKey) ?? "";
      } catch {
        return "";
      }
    },
    () => null,
  );
  return useMemo(() => (raw === null ? null : parseCourseProgress(raw, isLessonSlug)), [isLessonSlug, raw]);
}
