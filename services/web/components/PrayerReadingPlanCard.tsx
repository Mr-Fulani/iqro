"use client";

import Link from "next/link";
import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import {
  api,
  PrayerReadingDay,
  PrayerReadingPrayer,
} from "../lib/api";
import { useAuth } from "../lib/auth-context";
import { MessageKey } from "../lib/i18n";
import { useI18n } from "../lib/i18n-context";
import { loadPrayerLocationPreference } from "../lib/prayer-location";
import { localizedPath } from "../lib/routing";

const MUSHAF_PAGES = 604;
const PRAYERS: Array<{ code: PrayerReadingPrayer; label: MessageKey }> = [
  { code: "fajr", label: "prayer.fajr" },
  { code: "dhuhr", label: "prayer.dhuhr" },
  { code: "asr", label: "prayer.asr" },
  { code: "maghrib", label: "prayer.maghrib" },
  { code: "isha", label: "prayer.isha" },
];

function browserTimezone(): string {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
  } catch {
    return "UTC";
  }
}

export function PrayerReadingPlanCard() {
  const { session, isLoading: authLoading, loginGuest } = useAuth();
  const { formatNumber, locale, t } = useI18n();
  const [day, setDay] = useState<PrayerReadingDay | null>(null);
  const [pagesPerPrayer, setPagesPerPrayer] = useState(2);
  const [timezoneName, setTimezoneName] = useState(() => browserTimezone());
  const [editing, setEditing] = useState(false);
  const [loading, setLoading] = useState(false);
  const [busyPrayer, setBusyPrayer] = useState<PrayerReadingPrayer | "plan" | null>(null);
  const [error, setError] = useState<string | null>(null);

  const loadDay = useCallback(async (preferredTimezone = timezoneName) => {
    if (!api.getSession()) return;
    setLoading(true);
    setError(null);
    try {
      const result = await api.getPrayerReadingDay(preferredTimezone);
      setDay(result);
      setTimezoneName(result.timezone_name);
      if (result.plan) setPagesPerPrayer(result.plan.pages_per_prayer);
    } catch (reason) {
      setError(api.normalizeError(reason));
    } finally {
      setLoading(false);
    }
  }, [timezoneName]);

  useEffect(() => {
    if (authLoading) return;
    const savedTimezone =
      loadPrayerLocationPreference(session?.user.id)?.timezone || browserTimezone();
    setTimezoneName(savedTimezone);
    if (session) void loadDay(savedTimezone);
  }, [authLoading, loadDay, session]);

  const dailyPages = pagesPerPrayer * PRAYERS.length;
  const completionDays = Math.ceil(MUSHAF_PAGES / Math.max(dailyPages, 1));
  const completed = day?.check_ins.length || 0;
  const progressPercent = day?.target_pages
    ? Math.min(100, Math.round((day.achieved_pages / day.target_pages) * 100))
    : 0;
  const checkIns = useMemo(
    () => new Map(day?.check_ins.map((item) => [item.prayer, item]) || []),
    [day?.check_ins],
  );

  const savePlan = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!Number.isInteger(pagesPerPrayer) || pagesPerPrayer < 1 || pagesPerPrayer > 20) return;
    setBusyPrayer("plan");
    setError(null);
    try {
      if (!api.getSession() && !(await loginGuest())) {
        throw new Error(t("reading.sessionUnavailable"));
      }
      await api.setPrayerReadingPlan({
        pages_per_prayer: pagesPerPrayer,
        timezone_name: timezoneName,
        base_revision: day?.plan?.revision || 0,
      });
      setEditing(false);
      await loadDay(timezoneName);
    } catch (reason) {
      setError(api.normalizeError(reason));
    } finally {
      setBusyPrayer(null);
    }
  };

  const togglePrayer = async (prayer: PrayerReadingPrayer) => {
    if (!day?.plan) return;
    const existing = checkIns.get(prayer);
    setBusyPrayer(prayer);
    setError(null);
    try {
      if (existing) {
        await api.deletePrayerReadingCheckIn(existing.id, existing.revision);
      } else {
        await api.createPrayerReadingCheckIn({
          prayer,
          local_date: day.local_date,
          timezone_name: day.timezone_name,
        });
      }
      await loadDay(day.timezone_name);
      window.dispatchEvent(new Event("quran-reading-progress-changed"));
    } catch (reason) {
      setError(api.normalizeError(reason));
    } finally {
      setBusyPrayer(null);
    }
  };

  const showForm = !day?.plan || editing;

  return (
    <section id="prayer-reading-plan" className="surface prayer-reading-plan" data-testid="prayer-reading-plan">
      <div className="surface-head prayer-reading-plan-head">
        <div>
          <p className="eyebrow">{t("prayerReading.eyebrow")}</p>
          <h2 className="surface-title">{t("prayerReading.title")}</h2>
          <p className="surface-subtitle">{t("prayerReading.description")}</p>
        </div>
        {day?.plan && !editing && (
          <button
            type="button"
            className="btn btn-outline-primary btn-sm"
            onClick={() => setEditing(true)}
          >
            {t("prayerReading.changePlan")}
          </button>
        )}
      </div>

      {error && <div className="alert alert-error" role="alert">{error}</div>}

      <div className="prayer-reading-math" aria-label={t("prayerReading.forecastLabel")}>
        <div>
          <strong data-testid="pages-per-prayer-value">{formatNumber(pagesPerPrayer)}</strong>
          <span>{t("prayerReading.pagesAfterEach")}</span>
        </div>
        <div>
          <strong>{formatNumber(dailyPages)}</strong>
          <span>{t("prayerReading.pagesPerDay")}</span>
        </div>
        <div>
          <strong>≈ {formatNumber(completionDays)}</strong>
          <span>{t("prayerReading.daysForMushaf")}</span>
        </div>
      </div>

      {showForm ? (
        <form className="prayer-reading-form" onSubmit={savePlan}>
          <div className="form-group">
            <label className="form-label" htmlFor="pages-after-prayer">
              {t("prayerReading.pagesChoice")}
            </label>
            <input
              id="pages-after-prayer"
              type="number"
              min={1}
              max={20}
              step={1}
              value={pagesPerPrayer}
              onChange={(event) => setPagesPerPrayer(Number(event.target.value))}
              disabled={busyPrayer === "plan"}
              required
            />
          </div>
          <div className="prayer-reading-form-copy">
            <strong>
              {t("prayerReading.forecast", {
                pages: formatNumber(dailyPages),
                days: formatNumber(completionDays),
              })}
            </strong>
            <span>{t("prayerReading.mushafBasis")}</span>
          </div>
          <div className="today-reading-actions">
            <button type="submit" className="btn btn-primary" disabled={busyPrayer === "plan"}>
              {busyPrayer === "plan" ? t("common.saving") : t("prayerReading.savePlan")}
            </button>
            {day?.plan && (
              <button type="button" className="btn btn-secondary" onClick={() => setEditing(false)}>
                {t("common.cancel")}
              </button>
            )}
          </div>
        </form>
      ) : day?.plan ? (
        <>
          <div className="prayer-reading-progress-copy">
            <strong>{t("prayerReading.todayProgress", { completed: formatNumber(completed) })}</strong>
            <span>
              {formatNumber(day.achieved_pages)} / {formatNumber(day.target_pages)} {t("reading.unit.pages")}
            </span>
          </div>
          <div
            className="today-progress-track"
            role="progressbar"
            aria-valuemin={0}
            aria-valuemax={100}
            aria-valuenow={progressPercent}
            aria-label={t("prayerReading.todayProgress", { completed: formatNumber(completed) })}
          >
            <span style={{ width: `${progressPercent}%` }} />
          </div>
          <div className="prayer-reading-slots">
            {PRAYERS.map(({ code, label }) => {
              const checkIn = checkIns.get(code);
              return (
                <button
                  key={code}
                  type="button"
                  className={`prayer-reading-slot ${checkIn ? "is-complete" : ""}`}
                  onClick={() => void togglePrayer(code)}
                  disabled={busyPrayer !== null || loading}
                  aria-pressed={Boolean(checkIn)}
                  aria-label={
                    checkIn
                      ? t("prayerReading.undoPrayer", { prayer: t(label) })
                      : t("prayerReading.markPrayer", { prayer: t(label), pages: formatNumber(day.plan!.pages_per_prayer) })
                  }
                >
                  <span className="prayer-reading-check" aria-hidden="true">{checkIn ? "✓" : "+"}</span>
                  <strong>{t(label)}</strong>
                  <small>
                    {checkIn
                      ? t("prayerReading.readPages", { pages: formatNumber(checkIn.pages) })
                      : t("prayerReading.addPages", { pages: formatNumber(day.plan!.pages_per_prayer) })}
                  </small>
                </button>
              );
            })}
          </div>
          <div className="prayer-reading-footer">
            <p>{t("prayerReading.calmMotivation")}</p>
            <Link href={localizedPath(locale, "/quran")} className="btn btn-primary">
              {t("prayerReading.openQuran")}
            </Link>
          </div>
        </>
      ) : authLoading || loading ? (
        <p aria-live="polite">{t("common.loading")}</p>
      ) : null}
    </section>
  );
}
