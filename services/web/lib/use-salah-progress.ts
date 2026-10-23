"use client";

import {
  isSalahSlug,
  SALAH_COURSE_SLUG,
  SALAH_PROGRESS_EVENT,
  salahProgressStorageKey,
  type SalahProgress,
} from "./salah";
import { useCourseProgress } from "./use-course-progress";

/** Local course progress; `null` in server HTML and during hydration. */
export function useSalahProgress(courseSlug: string = SALAH_COURSE_SLUG): SalahProgress | null {
  return useCourseProgress(salahProgressStorageKey(courseSlug), SALAH_PROGRESS_EVENT, isSalahSlug);
}
