"use client";

import { useCallback, useEffect } from "react";

import { api } from "./api";
import { useAuth } from "./auth-context";
import { mergeCourseProgress, progressFromJson, sameCourseProgress, type CourseProgress } from "./course-progress";
import {
  isTajweedLessonSlug,
  readTajweedProgress,
  TAJWEED_COURSE_SLUG,
  TAJWEED_PROGRESS_EVENT,
  tajweedProgressStorageKey,
  writeTajweedProgress,
} from "./tajweed-course";
import { useCourseProgress } from "./use-course-progress";

/** Local course progress; `null` in server HTML and during hydration. */
export function useTajweedProgress(courseSlug: string = TAJWEED_COURSE_SLUG): CourseProgress | null {
  return useCourseProgress(tajweedProgressStorageKey(courseSlug), TAJWEED_PROGRESS_EVENT, isTajweedLessonSlug);
}

/**
 * For a signed-in visitor (a guest too): sends the local progress to the account
 * on mount and whenever the returned function is called, and keeps the merged
 * answer locally. Offline, progress stays local until the next time.
 */
export function useTajweedProgressSync(courseSlug: string = TAJWEED_COURSE_SLUG): () => Promise<void> {
  const { session, isLoading } = useAuth();
  const enabled = !isLoading && Boolean(session?.access_token) && session?.user.status !== "pending_deletion";
  const userId = session?.user.id;
  const sync = useCallback(async () => {
    if (!enabled || !userId) return;
    try {
      const answer = await api.mergeTajweedProgress(courseSlug, readTajweedProgress(courseSlug));
      const local = readTajweedProgress(courseSlug);
      const merged = mergeCourseProgress(local, progressFromJson(answer, isTajweedLessonSlug));
      if (!sameCourseProgress(merged, local)) writeTajweedProgress(merged, courseSlug);
    } catch {
      return;
    }
  }, [courseSlug, enabled, userId]);
  useEffect(() => {
    void sync();
  }, [sync]);
  return sync;
}
