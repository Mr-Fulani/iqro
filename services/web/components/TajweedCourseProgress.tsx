"use client";

import Link from "next/link";

import type { LessonOutline } from "../lib/course-progress";
import { summarizeCourseProgress } from "../lib/course-progress";
import { useI18n } from "../lib/i18n-context";
import { localizedPath } from "../lib/routing";
import { useTajweedProgress, useTajweedProgressSync } from "../lib/use-tajweed-progress";

/** Course summary and the «Continue» link from local progress, synced for a signed-in visitor. */
export function TajweedCourseProgress({ lessons }: { lessons: LessonOutline[] }) {
  const { formatNumber, locale, t } = useI18n();
  const progress = useTajweedProgress();
  useTajweedProgressSync();
  const summary = summarizeCourseProgress(lessons, progress ?? { lessons: {} });
  const started = Boolean(progress && Object.keys(progress.lessons).length);
  const target = summary.continueLesson;
  const href = target
    ? localizedPath(locale, `/tajweed/${target.slug}${target.stepSlug ? `#${target.stepSlug}` : ""}`)
    : null;

  return (
    <div className="tajweed-course-progress" data-testid="tajweed-course-progress">
      <div className="tajweed-course-progress-copy">
        <p>
          {t("tajweedCourse.progress", {
            completed: formatNumber(summary.completed),
            total: formatNumber(summary.total),
          })}
        </p>
        <progress max={summary.total || 1} value={summary.completed} aria-label={t("tajweedCourse.progressAria")} />
      </div>
      {href ? (
        <Link href={href} className="btn btn-primary">
          {started ? t("tajweedCourse.continue") : t("tajweedCourse.start")}
        </Link>
      ) : (
        <span className="status-chip ok">{t("tajweedCourse.allCompleted")}</span>
      )}
    </div>
  );
}

export function TajweedLessonStatusBadge({ slug }: { slug: string }) {
  const { t } = useI18n();
  const status = useTajweedProgress()?.lessons[slug]?.status;
  if (!status) return null;
  return (
    <span className={`status-chip tajweed-course-status${status === "completed" ? " ok" : ""}`}>
      {status === "completed" ? t("tajweedCourse.statusCompleted") : t("tajweedCourse.statusInProgress")}
    </span>
  );
}
