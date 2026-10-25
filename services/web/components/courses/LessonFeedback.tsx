"use client";

import { lazy, useState } from "react";

import { parseVotes, recordVote, trackCourseEvent, voteStorageKey, type LessonVote } from "../../lib/course-feedback";
import { useI18n } from "../../lib/i18n-context";
import { ShareDialogBoundary } from "../ShareDialogBoundary";
import { announceStoredValue, useStoredValue } from "./useStoredValue";

// The form loads only when the student opens it.
const LessonReportDialog = lazy(() => import("./LessonReportDialog"));

export type ReportedLesson = {
  courseSlug: string;
  courseTitle: string;
  courseVersion: string;
  language: string;
  lessonSlug: string;
  lessonNumber: number;
  lessonTitle: string;
};

/** «Тема была полезной?» and «Сообщить об ошибке» under the notes of a lesson. */
export function LessonFeedback(lesson: ReportedLesson) {
  const { t } = useI18n();
  const raw = useStoredValue(voteStorageKey(lesson.courseSlug));
  const vote = raw === null ? undefined : parseVotes(raw)[lesson.lessonSlug];
  const [reporting, setReporting] = useState(false);

  function choose(choice: LessonVote) {
    if (!recordVote(lesson.courseSlug, lesson.lessonSlug, choice)) return;
    trackCourseEvent({
      course: lesson.courseSlug,
      lesson: lesson.lessonSlug,
      event: choice === "helpful" ? "lesson_helpful" : "lesson_not_helpful",
    });
    announceStoredValue();
  }

  return (
    <div className="course-lesson-feedback" data-testid="lesson-feedback">
      <div className="course-lesson-vote" aria-live="polite">
        {vote ? (
          <p className="course-lesson-vote-thanks"><span aria-hidden="true">✓</span> {t("courses.voteThanks")}</p>
        ) : (
          <>
            <p id={`vote-${lesson.lessonSlug}`}>{t("courses.helpfulQuestion")}</p>
            <div className="course-lesson-vote-buttons" role="group" aria-labelledby={`vote-${lesson.lessonSlug}`}>
              <button type="button" className="btn btn-secondary" onClick={() => choose("helpful")} disabled={raw === null}>
                <span aria-hidden="true">👍</span> {t("courses.helpful")}
              </button>
              <button type="button" className="btn btn-secondary" onClick={() => choose("not_helpful")} disabled={raw === null}>
                <span aria-hidden="true">👎</span> {t("courses.notHelpful")}
              </button>
            </div>
          </>
        )}
      </div>
      <button type="button" className="course-lesson-report" onClick={() => setReporting(true)}>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"
          strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <path d="M5 21V4m0 0h11l-2 4 2 4H5" />
        </svg>
        {t("courses.report")}
      </button>
      {reporting ? (
        <ShareDialogBoundary onFailure={() => setReporting(false)}>
          <LessonReportDialog lesson={lesson} onClose={() => setReporting(false)} />
        </ShareDialogBoundary>
      ) : null}
    </div>
  );
}
