"use client";

import {
  isSalahSlug,
  readSalahProgress,
  SALAH_COURSE_SLUG,
  SALAH_PROGRESS_EVENT,
  salahProgressStorageKey,
  writeSalahProgress,
  type SalahProgress,
} from "./salah";
import { useAccountProgressSync } from "./use-account-progress-sync";
import { useCourseProgress } from "./use-course-progress";

/** Local course progress; `null` in server HTML and during hydration. */
export function useSalahProgress(courseSlug: string = SALAH_COURSE_SLUG): SalahProgress | null {
  return useCourseProgress(salahProgressStorageKey(courseSlug), SALAH_PROGRESS_EVENT, isSalahSlug);
}

/** Keeps the progress with a signed-in account; call the result after a lesson is completed. */
export function useSalahProgressSync(courseSlug: string = SALAH_COURSE_SLUG): () => Promise<void> {
  return useAccountProgressSync("salah", courseSlug, readSalahProgress, writeSalahProgress, isSalahSlug);
}
