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
  const [notificationsEnabled, setNotificationsEnabled] = useState(true);
  const [timezoneName, setTimezoneName] = useState(() => browserTimezone());
  const [editing, setEditing] = useState(false);
  const [editingPrayer, setEditingPrayer] = useState<PrayerReadingPrayer | null>(null);
  const [actualPages, setActualPages] = useState(2);
  const [loading, setLoading] = useState(false);
  const [busyPrayer, setBusyPrayer] = useState<
    PrayerReadingPrayer | "plan" | "notifications" | null
  >(null);
  const [error, setError] = useState<string | null>(null);

  const loadDay = useCallback(async (preferredTimezone = timezoneName) => {
    if (!api.getSession()) return;
    setLoading(true);
    setError(null);
    try {
      const result = await api.getPrayerReadingDay(preferredTimezone);
      setDay(result);
      setTimezoneName(result.timezone_name);
      if (result.plan) {
        setPagesPerPrayer(result.plan.pages_per_prayer);
        setNotificationsEnabled(result.plan.notifications_enabled);
      }
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
  const completed = day?.plan
    ? day.check_ins.filter((item) => item.pages >= day.plan!.pages_per_prayer).length
    : 0;
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
        notifications_enabled: notificationsEnabled,
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

  const toggleReadingNotifications = async () => {
    const nextValue = !notificationsEnabled;
    if (!day?.plan) {
      setNotificationsEnabled(nextValue);
      return;
    }
    setBusyPrayer("notifications");
    setError(null);
    try {
      const updated = await api.setPrayerReadingPlan({
        pages_per_prayer: day.plan.pages_per_prayer,
        notifications_enabled: nextValue,
        timezone_name: day.plan.timezone_name,
        base_revision: day.plan.revision,
      });
      setNotificationsEnabled(updated.notifications_enabled);
      setDay((current) => (current ? { ...current, plan: updated } : current));
    } catch (reason) {
      setError(api.normalizeError(reason));
    } finally {
      setBusyPrayer(null);
    }
  };

  const openManualEditor = (prayer: PrayerReadingPrayer) => {
    if (!day?.plan) return;
    const existing = checkIns.get(prayer);
    setActualPages(existing?.pages || day.plan.pages_per_prayer);
    setEditingPrayer(prayer);
    setError(null);
  };

  const savePrayerProgress = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!day?.plan || editingPrayer === null || !Number.isInteger(actualPages)
      || actualPages < 1 || actualPages > MUSHAF_PAGES) return;
    const existing = checkIns.get(editingPrayer);
    setBusyPrayer(editingPrayer);
    setError(null);
    try {
      if (existing) {
        await api.updatePrayerReadingCheckIn(existing.id, {
          pages: actualPages,
          base_revision: existing.revision,
        });
      } else {
        await api.createPrayerReadingCheckIn({
          prayer: editingPrayer,
          local_date: day.local_date,
          timezone_name: day.timezone_name,
          pages: actualPages,
        });
      }
      setEditingPrayer(null);
      await loadDay(day.timezone_name);
      window.dispatchEvent(new Event("quran-reading-progress-changed"));
    } catch (reason) {
      setError(api.normalizeError(reason));
    } finally {
      setBusyPrayer(null);
    }
  };

  const removePrayerProgress = async (prayer: PrayerReadingPrayer) => {
    if (!day?.plan) return;
    const existing = checkIns.get(prayer);
    if (!existing) return;
    setBusyPrayer(prayer);
    setError(null);
    try {
      await api.deletePrayerReadingCheckIn(existing.id, existing.revision);
      setEditingPrayer(null);
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

      <div className="prayer-reading-notification-row">
        <div>
          <strong>{t("prayerReading.notificationsTitle")}</strong>
          <p className="kpi-desc">{t("prayerReading.notificationsDescription")}</p>
        </div>
        <button
          aria-checked={notificationsEnabled}
          aria-label={t("prayerReading.notificationsToggleLabel")}
          className={`reminder-switch ${notificationsEnabled ? "is-on" : ""}`}
          disabled={busyPrayer !== null}
          onClick={() => void toggleReadingNotifications()}
          role="switch"
          type="button"
        >
          <span aria-hidden="true" />
          <span className="sr-only">
            {t(notificationsEnabled ? "reminder.disable" : "reminder.enable")}
          </span>
        </button>
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
              const isComplete = Boolean(
                checkIn && checkIn.pages >= day.plan!.pages_per_prayer,
              );
              const isPartial = Boolean(checkIn && !isComplete);
              const readerHref = {
                pathname: localizedPath(locale, "/quran"),
                query: {
                  mode: "after-prayer",
                  prayer: code,
                  prayer_date: day.local_date,
                  prayer_timezone: day.timezone_name,
                  prayer_target: String(day.plan!.pages_per_prayer),
                  prayer_credited: String(checkIn?.pages || 0),
                  ...(checkIn
                    ? {
                        check_in_id: checkIn.id,
                        check_in_revision: String(checkIn.revision),
                      }
                    : {}),
                },
              };
              return (
                <article
                  key={code}
                  className={`prayer-reading-slot${isComplete ? " is-complete" : ""}${isPartial ? " is-partial" : ""}`}
                >
                  <span className="prayer-reading-check" aria-hidden="true">
                    {isComplete ? "✓" : isPartial ? "◐" : "+"}
                  </span>
                  <div className="prayer-reading-slot-copy">
                    <strong>{t(label)}</strong>
                    <small>
                      {t("prayerReading.slotProgress", {
                        pages: formatNumber(checkIn?.pages || 0),
                        target: formatNumber(day.plan!.pages_per_prayer),
                      })}
                    </small>
                  </div>
                  <div className="prayer-reading-slot-actions">
                    <Link
                      href={readerHref}
                      className="btn btn-primary btn-sm"
                      aria-label={t("prayerReading.readForPrayer", { prayer: t(label) })}
                    >
                      {isComplete
                        ? t("prayerReading.readMore")
                        : checkIn
                          ? t("prayerReading.continueSlot")
                          : t("prayerReading.readNow")}
                    </Link>
                    <button
                      type="button"
                      className="btn btn-secondary btn-sm"
                      onClick={() => openManualEditor(code)}
                      disabled={busyPrayer !== null || loading}
                    >
                      {checkIn ? t("prayerReading.editActual") : t("prayerReading.recordActual")}
                    </button>
                  </div>
                </article>
              );
            })}
          </div>
          {editingPrayer && (
            <form className="prayer-reading-manual-form" onSubmit={savePrayerProgress}>
              <div className="form-group">
                <label className="form-label" htmlFor="prayer-reading-manual-pages">
                  {t("prayerReading.actualFor", {
                    prayer: t(PRAYERS.find((item) => item.code === editingPrayer)!.label),
                  })}
                </label>
                <input
                  id="prayer-reading-manual-pages"
                  type="number"
                  min={1}
                  max={MUSHAF_PAGES}
                  step={1}
                  value={actualPages}
                  onChange={(event) => setActualPages(Number(event.target.value))}
                  disabled={busyPrayer !== null}
                  required
                />
              </div>
              <div className="prayer-reading-manual-copy">
                <span>{t("prayerReading.actualHint")}</span>
              </div>
              <div className="today-reading-actions">
                <button type="submit" className="btn btn-primary" disabled={busyPrayer !== null}>
                  {busyPrayer ? t("common.saving") : t("prayerReading.saveActual")}
                </button>
                {checkIns.has(editingPrayer) && (
                  <button
                    type="button"
                    className="btn btn-danger"
                    onClick={() => void removePrayerProgress(editingPrayer)}
                    disabled={busyPrayer !== null}
                  >
                    {t("prayerReading.deleteActual")}
                  </button>
                )}
                <button
                  type="button"
                  className="btn btn-secondary"
                  onClick={() => setEditingPrayer(null)}
                  disabled={busyPrayer !== null}
                >
                  {t("common.cancel")}
                </button>
              </div>
            </form>
          )}
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
