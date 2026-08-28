"use client";

import Link from "next/link";
import { FormEvent, useEffect, useMemo, useRef, useState } from "react";
import { api, PrayerReadingPrayer } from "../lib/api";
import { useAuth } from "../lib/auth-context";
import { MessageKey } from "../lib/i18n";
import { useI18n } from "../lib/i18n-context";
import { localizedPath } from "../lib/routing";

export type PrayerReadingSessionConfig = {
  prayer: PrayerReadingPrayer;
  localDate: string;
  timezoneName: string;
  targetPages: number;
  creditedPages: number;
  checkInId: string | null;
  checkInRevision: number | null;
};

type PrayerReadingSessionBarProps = {
  config: PrayerReadingSessionConfig;
  currentPage: number;
  edition: string;
  surah: number;
  activeSeconds: number;
  onFinished: () => void;
};

const PRAYER_LABELS: Record<PrayerReadingPrayer, MessageKey> = {
  fajr: "prayer.fajr",
  dhuhr: "prayer.dhuhr",
  asr: "prayer.asr",
  maghrib: "prayer.maghrib",
  isha: "prayer.isha",
};

function boundedPages(value: number): number {
  return Math.min(604, Math.max(1, Math.round(value)));
}

export function PrayerReadingSessionBar({
  config,
  currentPage,
  edition,
  surah,
  activeSeconds,
  onFinished,
}: PrayerReadingSessionBarProps) {
  const { loginGuest } = useAuth();
  const { formatNumber, locale, t } = useI18n();
  const visitedPages = useRef(new Set<number>());
  const userEditedAmount = useRef(false);
  const [actualPages, setActualPages] = useState(() => boundedPages(config.creditedPages + 1));
  const [saving, setSaving] = useState(false);
  const [savedPages, setSavedPages] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const prayerLabel = t(PRAYER_LABELS[config.prayer]);
  const activeTime = useMemo(() => {
    const minutes = Math.floor(activeSeconds / 60);
    const seconds = activeSeconds % 60;
    return `${formatNumber(minutes)}:${formatNumber(seconds, {
      minimumIntegerDigits: 2,
      useGrouping: false,
    })}`;
  }, [activeSeconds, formatNumber]);

  useEffect(() => {
    visitedPages.current.add(currentPage);
    if (!userEditedAmount.current) {
      setActualPages(boundedPages(config.creditedPages + visitedPages.current.size));
    }
  }, [config.creditedPages, currentPage]);

  const progressPercent = useMemo(
    () => Math.min(100, Math.round((actualPages / config.targetPages) * 100)),
    [actualPages, config.targetPages],
  );

  const saveProgress = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const pages = boundedPages(actualPages);
    setSaving(true);
    setError(null);
    try {
      if (!api.getSession() && !(await loginGuest())) {
        throw new Error(t("reading.sessionUnavailable"));
      }
      const checkIn = config.checkInId && config.checkInRevision
        ? await api.updatePrayerReadingCheckIn(config.checkInId, {
            pages,
            base_revision: config.checkInRevision,
          })
        : await api.createPrayerReadingCheckIn({
            prayer: config.prayer,
            local_date: config.localDate,
            timezone_name: config.timezoneName,
            pages,
          });
      try {
        await api.saveReadingPosition(edition, {
          page_number: currentPage,
          surah_number: surah,
          ayah_number: 1,
          progress_percent: ((currentPage / 604) * 100).toFixed(2),
          base_revision: 0,
        });
      } catch {
        // The after-prayer progress is already saved; position sync is best-effort.
      }
      setSavedPages(checkIn.pages);
      onFinished();
      window.dispatchEvent(new Event("quran-reading-progress-changed"));
    } catch (reason) {
      setError(api.normalizeError(reason));
    } finally {
      setSaving(false);
    }
  };

  return (
    <section className="surface prayer-reading-session" data-testid="prayer-reading-session">
      <div className="prayer-reading-session-copy">
        <p className="eyebrow">{t("prayerReading.readerEyebrow")}</p>
        <h2>{t("prayerReading.readerTitle", { prayer: prayerLabel })}</h2>
        <p>{t("prayerReading.readerDescription")}</p>
      </div>

      <div className="prayer-reading-session-progress">
        <div>
          <strong>
            {formatNumber(actualPages)} / {formatNumber(config.targetPages)} {t("reading.unit.pages")}
          </strong>
          <span>{t("prayerReading.readerActualProgress")}</span>
        </div>
        <div
          className="today-progress-track"
          role="progressbar"
          aria-valuemin={0}
          aria-valuemax={100}
          aria-valuenow={progressPercent}
          aria-label={t("prayerReading.readerActualProgress")}
        >
          <span style={{ width: `${progressPercent}%` }} />
        </div>
        <div className="prayer-reading-session-time" data-testid="prayer-reading-active-time">
          <strong>{activeTime}</strong>
          <span>{t("prayerReading.readerActiveTime")}</span>
        </div>
      </div>

      {savedPages === null ? (
        <form className="prayer-reading-session-form" onSubmit={saveProgress}>
          <label className="form-label" htmlFor="prayer-reading-actual-pages">
            {t("prayerReading.actualPages")}
          </label>
          <input
            id="prayer-reading-actual-pages"
            type="number"
            min={1}
            max={604}
            step={1}
            value={actualPages}
            onChange={(event) => {
              userEditedAmount.current = true;
              setActualPages(Number(event.target.value));
            }}
            disabled={saving}
            required
          />
          <button className="btn btn-primary" type="submit" disabled={saving}>
            {saving ? t("common.saving") : t("prayerReading.finishReading")}
          </button>
          <small>{t("prayerReading.actualHint")}</small>
          <small>{t("prayerReading.readerTimeHint")}</small>
        </form>
      ) : (
        <div className="alert alert-success prayer-reading-session-success" role="status">
          <span>{t("prayerReading.savedActual", { pages: formatNumber(savedPages), prayer: prayerLabel })}</span>
          <Link href={`${localizedPath(locale, "/")}#prayer-reading-plan`} className="btn btn-primary btn-sm">
            {t("prayerReading.returnToPlan")}
          </Link>
        </div>
      )}

      {error && <div className="alert alert-error" role="alert">{error}</div>}
    </section>
  );
}
