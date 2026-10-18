"use client";

import Link from "next/link";

import { useI18n } from "../lib/i18n-context";
import { localizedPath } from "../lib/routing";
import { summarizeSalahProgress, type SalahLessonOutline } from "../lib/salah";
import { useSalahProgress } from "../lib/use-salah-progress";

/** Course summary and the «Continue» link, drawn from local progress after hydration. */
export function SalahCourseProgress({ lessons }: { lessons: SalahLessonOutline[] }) {
  const { formatNumber, locale, t } = useI18n();
  const progress = useSalahProgress();
  const summary = summarizeSalahProgress(lessons, progress ?? { lessons: {} });
  const started = Boolean(progress && Object.keys(progress.lessons).length);
  const target = summary.continueLesson;
  const href = target
    ? localizedPath(locale, `/salah/${target.slug}${target.stepSlug ? `#${target.stepSlug}` : ""}`)
    : null;

  return (
    <div className="salah-course-progress" data-testid="salah-course-progress">
      <div className="salah-progress-copy">
        <p>
          {t("salah.progress", {
            completed: formatNumber(summary.completed),
            total: formatNumber(summary.total),
          })}
        </p>
        <progress
          max={summary.total || 1}
          value={summary.completed}
          aria-label={t("salah.progressAria")}
        />
      </div>
      {href ? (
        <Link href={href} className="btn btn-primary">
          {started ? t("salah.continue") : t("salah.start")}
        </Link>
      ) : (
        <span className="status-chip ok">{t("salah.allCompleted")}</span>
      )}
    </div>
  );
}

export function SalahLessonStatusBadge({ slug }: { slug: string }) {
  const { t } = useI18n();
  const status = useSalahProgress()?.lessons[slug]?.status;
  if (!status) return null;
  return (
    <span className={`status-chip salah-lesson-status${status === "completed" ? " ok" : ""}`}>
      {status === "completed" ? t("salah.statusCompleted") : t("salah.statusInProgress")}
    </span>
  );
}
