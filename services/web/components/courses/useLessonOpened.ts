"use client";

import { useEffect, useRef } from "react";

import { trackCourseEvent } from "../../lib/course-feedback";

/** Counts «lesson_opened» of a built-in course once per page view (docs/courses/README.md). */
export function useLessonOpened(courseSlug: string, lessonSlug: string): void {
  const counted = useRef("");
  useEffect(() => {
    // Once per page view, also when development mode runs the effect twice.
    const lesson = `${courseSlug}/${lessonSlug}`;
    if (counted.current === lesson) return;
    counted.current = lesson;
    trackCourseEvent({ course: courseSlug, lesson: lessonSlug, event: "lesson_opened" });
  }, [courseSlug, lessonSlug]);
}
