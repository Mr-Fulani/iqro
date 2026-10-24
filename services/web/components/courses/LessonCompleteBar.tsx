"use client";

import Link from "next/link";
import { useEffect } from "react";

import { useI18n } from "../../lib/i18n-context";
import { localizedPath } from "../../lib/routing";
import {
  readThematicProgress,
  recordLessonCompleted,
  recordLessonOpened,
  writeThematicProgress,
} from "../../lib/thematic-courses";
import { useThematicProgress } from "./CourseProgress";

type LessonLink = { slug: string; title: string };

function Arrow({ forward }: { forward: boolean }) {
  // Mirrored in RTL by the stylesheet, so «forward» always points along the reading direction.
  return (
    <svg className="course-lesson-bar-arrow" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor"
      strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d={forward ? "M5 12h14m-6-6 6 6-6 6" : "M19 12H5m6-6-6 6 6 6"} />
    </svg>
  );
}

/** «Lesson learned» and the way on; fixed above the tab bar on a phone. */
export function LessonCompleteBar({
  courseSlug,
  courseVersion,
  lessonSlug,
  previous,
  next,
}: {
  courseSlug: string;
  courseVersion: string;
  lessonSlug: string;
  previous: LessonLink | null;
  next: LessonLink | null;
}) {
  const { locale, t } = useI18n();
  const completed = useThematicProgress(courseSlug)?.lessons[lessonSlug]?.status === "completed";
  const lessonHref = (slug: string) => localizedPath(locale, `/courses/${courseSlug}/${slug}`);

  // Opening a lesson starts it; «Continue» then comes back here until it is learned.
  useEffect(() => {
    writeThematicProgress(recordLessonOpened(readThematicProgress(courseSlug), lessonSlug, courseVersion), courseSlug);
  }, [courseSlug, courseVersion, lessonSlug]);

  function markDone() {
    writeThematicProgress(recordLessonCompleted(readThematicProgress(courseSlug), lessonSlug, courseVersion), courseSlug);
  }

  return (
    <div className="course-lesson-bar" data-testid="course-lesson-bar" data-completed={completed ? "true" : "false"}>
      {previous ? (
        <Link
          href={lessonHref(previous.slug)}
          className="btn btn-secondary course-lesson-bar-side"
          aria-label={t("courses.previousLesson", { title: previous.title })}
        >
          <Arrow forward={false} />
          <span className="course-lesson-bar-title">{previous.title}</span>
        </Link>
      ) : null}
      <div className="course-lesson-bar-main" aria-live="polite">
        {completed ? (
          <p className="course-lesson-bar-done">
            <span aria-hidden="true">✓</span> <strong>{t("courses.done")}</strong>
            <span className="course-lesson-bar-saved"> {t("courses.doneSaved")}</span>
          </p>
        ) : (
          <button type="button" className="btn btn-primary" onClick={markDone}>
            {t("courses.markDone")} <span aria-hidden="true">✓</span>
          </button>
        )}
      </div>
      {next ? (
        <Link
          href={lessonHref(next.slug)}
          className={`btn ${completed ? "btn-primary" : "btn-secondary"} course-lesson-bar-side course-lesson-bar-next`}
          aria-label={t("courses.next", { title: next.title })}
        >
          <span className="course-lesson-bar-title">{t("courses.next", { title: next.title })}</span>
          <span className="course-lesson-bar-short">{t("courses.nextShort")}</span>
          <Arrow forward />
        </Link>
      ) : (
        <Link
          href={localizedPath(locale, `/courses/${courseSlug}`)}
          className={`btn ${completed ? "btn-primary" : "btn-secondary"} course-lesson-bar-side course-lesson-bar-next`}
        >
          {t("courses.allLessons")}
        </Link>
      )}
    </div>
  );
}
