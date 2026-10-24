"use client";

import Link from "next/link";
import { useMemo, useSyncExternalStore } from "react";

import { formatClock } from "../../lib/audio-content";
import { parseCourseProgress, type CourseProgress } from "../../lib/course-progress";
import { useI18n } from "../../lib/i18n-context";
import { localizedPath } from "../../lib/routing";
import {
  continueTarget,
  COURSES_POSITION_EVENT,
  COURSES_PROGRESS_EVENT,
  courseProgressStorageKey,
  isLessonSlug,
  parseVideoPositions,
  summarizeThematicProgress,
  videoPositionStorageKey,
  type CourseOutline,
} from "../../lib/thematic-courses";
import { useCourseProgress } from "../../lib/use-course-progress";

/** Local progress of a thematic course; `null` in server HTML and during hydration. */
export function useThematicProgress(courseSlug: string): CourseProgress | null {
  return useCourseProgress(courseProgressStorageKey(courseSlug), COURSES_PROGRESS_EVENT, isLessonSlug);
}

function subscribePositions(onChange: () => void) {
  window.addEventListener("storage", onChange);
  window.addEventListener(COURSES_POSITION_EVENT, onChange);
  return () => {
    window.removeEventListener("storage", onChange);
    window.removeEventListener(COURSES_POSITION_EVENT, onChange);
  };
}

/** Where the lesson's video stopped, in ms; `null` if nowhere, in server HTML and during hydration. */
export function useVideoPosition(courseSlug: string, lessonSlug: string): number | null {
  const raw = useSyncExternalStore(
    subscribePositions,
    () => {
      try {
        return window.localStorage.getItem(videoPositionStorageKey(courseSlug));
      } catch {
        return null;
      }
    },
    () => null,
  );
  return useMemo(() => parseVideoPositions(raw)[lessonSlug]?.ms ?? null, [lessonSlug, raw]);
}

function subscribe(onChange: () => void) {
  window.addEventListener("storage", onChange);
  window.addEventListener(COURSES_PROGRESS_EVENT, onChange);
  return () => {
    window.removeEventListener("storage", onChange);
    window.removeEventListener(COURSES_PROGRESS_EVENT, onChange);
  };
}

/** Progress of several courses at once, for the catalog; `null` until hydrated. */
function useThematicProgressOf(courseSlugs: string[]): Map<string, CourseProgress> | null {
  const raw = useSyncExternalStore(
    subscribe,
    () => {
      try {
        return JSON.stringify(courseSlugs.map((slug) => window.localStorage.getItem(courseProgressStorageKey(slug))));
      } catch {
        return "[]";
      }
    },
    () => null,
  );
  return useMemo(() => {
    if (raw === null) return null;
    const values = JSON.parse(raw) as (string | null)[];
    return new Map(courseSlugs.map((slug, index) => [slug, parseCourseProgress(values[index] ?? null, isLessonSlug)]));
  }, [courseSlugs, raw]);
}

const NO_PROGRESS: CourseProgress = { lessons: {} };

/** «Continue: course · lesson» above the catalog, once a course has been opened here. */
export function CourseContinueStrip({ courses }: { courses: CourseOutline[] }) {
  const { formatNumber, locale, t } = useI18n();
  const slugs = useMemo(() => courses.map((course) => course.slug), [courses]);
  const progress = useThematicProgressOf(slugs);
  const target = progress ? continueTarget(courses, (slug) => progress.get(slug) ?? NO_PROGRESS) : null;
  const position = useVideoPosition(target?.course.slug ?? "", target?.lesson.slug ?? "");
  if (!target) return null;
  const href = localizedPath(locale, `/courses/${target.course.slug}/${target.lesson.slug}`);
  return (
    <section className="surface courses-continue" aria-labelledby="courses-continue-title" data-testid="courses-continue">
      <div>
        <h2 id="courses-continue-title" className="eyebrow">{t("courses.continueTitle")}</h2>
        <p>
          {t("courses.continueLesson", {
            course: target.course.title,
            number: formatNumber(target.lesson.number),
            lesson: target.lesson.title,
          })}
          {position ? ` · ${t("courses.continueFrom", { position: formatClock(position, (value) => formatNumber(value)) })}` : null}
        </p>
      </div>
      <Link href={href} className="btn btn-primary">{t("courses.continue")}</Link>
    </section>
  );
}

/** «Started · 2 of 8» or «Completed» on a catalog card. */
export function CourseCardProgress({ course }: { course: CourseOutline }) {
  const { formatNumber, t } = useI18n();
  const progress = useThematicProgress(course.slug);
  if (!progress) return null;
  const summary = summarizeThematicProgress(course, progress);
  if (!summary.started) return null;
  const done = summary.completed === summary.total;
  return (
    <div className="courses-card-progress">
      <progress max={summary.total || 1} value={summary.completed} aria-label={t("courses.progressAria")} />
      <span className={`status-chip${done ? " ok" : ""}`}>
        {done
          ? t("courses.cardCompleted")
          : t("courses.cardStarted", { completed: formatNumber(summary.completed), total: formatNumber(summary.total) })}
      </span>
    </div>
  );
}

/** «2 of 8 lessons» and the «Start» / «Continue» link on the course page. */
export function CourseProgressSummary({ course }: { course: CourseOutline }) {
  const { formatNumber, locale, t } = useI18n();
  const progress = useThematicProgress(course.slug);
  const summary = summarizeThematicProgress(course, progress ?? NO_PROGRESS);
  const next = summary.nextLesson;
  return (
    <div className="course-progress" data-testid="course-progress">
      <div className="course-progress-copy">
        <p>{t("courses.progress", { completed: formatNumber(summary.completed), total: formatNumber(summary.total) })}</p>
        <progress max={summary.total || 1} value={summary.completed} aria-label={t("courses.progressAria")} />
      </div>
      {next ? (
        <Link href={localizedPath(locale, `/courses/${course.slug}/${next.slug}`)} className="btn btn-primary">
          {summary.started ? t("courses.continue") : t("courses.start")}
        </Link>
      ) : (
        <span className="status-chip ok">{t("courses.courseCompleted")}</span>
      )}
    </div>
  );
}

export function LessonStatusBadge({ courseSlug, lessonSlug }: { courseSlug: string; lessonSlug: string }) {
  const { t } = useI18n();
  const status = useThematicProgress(courseSlug)?.lessons[lessonSlug]?.status;
  if (!status) return null;
  return (
    <span className={`status-chip course-lesson-status${status === "completed" ? " ok" : ""}`}>
      {status === "completed" ? t("courses.lessonCompleted") : t("courses.lessonInProgress")}
    </span>
  );
}
