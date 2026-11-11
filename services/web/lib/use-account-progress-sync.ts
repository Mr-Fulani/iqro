"use client";

import { useCallback, useEffect } from "react";

import { api } from "./api";
import { useAuth } from "./auth-context";
import {
  mergeCourseProgress,
  progressFromJson,
  progressToSend,
  sameCourseProgress,
  type CourseProgress,
} from "./course-progress";

/**
 * Keeps the progress of the prayer course or a thematic course with the account:
 * sends the local copy on mount and whenever the returned function is called,
 * and keeps the merged answer locally. Only for a signed-in account: a guest's
 * progress stays on the device. Offline, it stays local until the next time.
 *
 * `read`, `write` and `isLessonSlug` must keep their identity between renders.
 */
export function useAccountProgressSync(
  kind: "salah" | "courses",
  courseSlug: string,
  read: (courseSlug: string) => CourseProgress,
  write: (progress: CourseProgress, courseSlug: string) => void,
  isLessonSlug: (slug: string) => boolean,
): () => Promise<void> {
  const { session, isLoading } = useAuth();
  const enabled = !isLoading && Boolean(session?.access_token) && session?.user.status === "active";
  const userId = session?.user.id;
  const sync = useCallback(async () => {
    if (!enabled || !userId) return;
    try {
      const answer = await api.mergeCourseProgress(kind, courseSlug, progressToSend(read(courseSlug)));
      const local = read(courseSlug);
      const merged = mergeCourseProgress(local, progressFromJson(answer, isLessonSlug), {
        keepCompleted: kind === "salah",
      });
      if (!sameCourseProgress(merged, local)) write(merged, courseSlug);
    } catch {
      return;
    }
  }, [courseSlug, enabled, isLessonSlug, kind, read, userId, write]);
  useEffect(() => {
    void sync();
  }, [sync]);
  return sync;
}
