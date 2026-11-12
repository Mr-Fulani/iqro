"use client";

import { useI18n } from "@/lib/i18n-context";
import {
  isNameSlug,
  learnedCount,
  NAMES_COLLECTION_SLUG,
  NAMES_PROGRESS_EVENT,
  namesProgressStorageKey,
  readNamesProgress,
  writeNamesProgress,
} from "@/lib/names";
import { useAccountProgressSync } from "@/lib/use-account-progress-sync";
import { useCourseProgress } from "@/lib/use-course-progress";

/**
 * «Выучено 12 из 99» on the card of the course catalog, once a name was seen or learned.
 * A guest's marks are the device's; a signed-in reader's are merged with the account first.
 */
export function NamesCardProgress({ total }: { total: number }) {
  const { formatNumber, t } = useI18n();
  const progress = useCourseProgress(namesProgressStorageKey(), NAMES_PROGRESS_EVENT, isNameSlug);
  useAccountProgressSync("names", NAMES_COLLECTION_SLUG, readNamesProgress, writeNamesProgress, isNameSlug);
  if (!progress || Object.keys(progress.lessons).length === 0) return null;
  // A name removed from the list may still be marked on the device.
  const learned = Math.min(total, learnedCount(progress));
  return (
    <div className="courses-card-progress" data-testid="courses-names-progress">
      <progress max={total} value={learned} aria-label={t("courses.progressAria")} />
      <span className={`status-chip${learned === total ? " ok" : ""}`}>
        {t("courses.namesLearned", { learned: formatNumber(learned), total: formatNumber(total) })}
      </span>
    </div>
  );
}
