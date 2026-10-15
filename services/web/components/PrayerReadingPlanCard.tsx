"use client";

import Link from "next/link";
import { FormEvent, useCallback, useEffect, useState } from "react";
import { api, PrayerReadingDay, PrayerReadingPrayer, ReadingGoalMetric } from "../lib/api";
import { useAuth } from "../lib/auth-context";
import { MessageKey } from "../lib/i18n";
import { useI18n } from "../lib/i18n-context";
import { localizedPath } from "../lib/routing";

const PRAYERS: Array<{ code: PrayerReadingPrayer; label: MessageKey }> = [
  { code: "fajr", label: "prayer.fajr" },
  { code: "dhuhr", label: "prayer.dhuhr" },
  { code: "asr", label: "prayer.asr" },
  { code: "maghrib", label: "prayer.maghrib" },
  { code: "isha", label: "prayer.isha" },
];
const LIMITS = { pages: 604, minutes: 1440, ayahs: 6236 };

export function PrayerReadingPlanCard() {
  const { session, isLoading: authLoading } = useAuth();
  const { formatNumber, locale, t } = useI18n();
  const [day, setDay] = useState<PrayerReadingDay | null>(null);
  const [editingPrayer, setEditingPrayer] = useState<PrayerReadingPrayer | null>(null);
  const [actualAmount, setActualAmount] = useState(1);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [timezoneName] = useState(() => Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC");
  const loadDay = useCallback(async () => {
    if (!api.getSession()) return;
    try {
      setDay(await api.getPrayerReadingDay(timezoneName));
      setError(null);
    } catch (reason) {
      setError(api.normalizeError(reason));
    }
  }, [timezoneName]);

  useEffect(() => {
    if (!authLoading && session) void loadDay();
  }, [authLoading, session, loadDay]);
  useEffect(() => {
    const refresh = () => void loadDay();
    window.addEventListener("quran-reading-progress-changed", refresh);
    return () => window.removeEventListener("quran-reading-progress-changed", refresh);
  }, [loadDay]);

  const metric = day?.goal?.metric || "pages";
  const unit = (value: ReadingGoalMetric) => t(`reading.unit.${value}`);
  const checkIn = day?.check_ins.find((item) => item.prayer === editingPrayer);
  const editMetric = checkIn?.metric || metric;
  const changed = async () => {
    setEditingPrayer(null);
    await loadDay();
    window.dispatchEvent(new Event("quran-reading-progress-changed"));
  };
  const saveProgress = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!day?.goal || !editingPrayer || !Number.isFinite(actualAmount) || actualAmount <= 0) return;
    setBusy(true);
    setError(null);
    try {
      if (checkIn) {
        await api.updatePrayerReadingCheckIn(checkIn.id, {
          metric: editMetric, amount: actualAmount, base_revision: checkIn.revision,
        });
      } else {
        await api.createPrayerReadingCheckIn({
          prayer: editingPrayer, local_date: day.local_date,
          timezone_name: day.timezone_name, metric, amount: actualAmount,
        });
      }
      await changed();
    } catch (reason) {
      setError(api.normalizeError(reason));
    } finally {
      setBusy(false);
    }
  };
  const removeProgress = async () => {
    if (!checkIn) return;
    setBusy(true);
    try {
      await api.deletePrayerReadingCheckIn(checkIn.id, checkIn.revision);
      await changed();
    } catch (reason) {
      setError(api.normalizeError(reason));
    } finally {
      setBusy(false);
    }
  };
  const toggleNotifications = async () => {
    if (!day?.goal) return;
    setBusy(true);
    try {
      await api.setPrayerReadingPlan({
        pages_per_prayer: day.plan?.pages_per_prayer || 1,
        notifications_enabled: !day.plan?.notifications_enabled,
        timezone_name: day.timezone_name,
        base_revision: day.plan?.revision || 0,
      });
      await loadDay();
    } catch (reason) {
      setError(api.normalizeError(reason));
    } finally {
      setBusy(false);
    }
  };

  return (
    <section id="prayer-reading-plan" className="surface prayer-reading-plan" data-testid="prayer-reading-plan">
      <div className="surface-head prayer-reading-plan-head">
        <div>
          <h2 className="surface-title">{t("prayerReading.title")}</h2>
          <p className="surface-subtitle">{t("prayerReading.unifiedDescription")}</p>
        </div>
        <a href="#reading-goal" className="btn btn-outline-primary btn-sm">{t("reading.changeGoal")}</a>
      </div>
      {error && <div className="alert alert-error" role="alert">{error}</div>}
      {!day?.goal ? <p>{t("prayerReading.setDailyGoal")}</p> : <>
        <div className="prayer-reading-progress-copy">
          <strong>{t("planner.dailyGoal")}</strong>
          <span>{formatNumber(Number(day.achieved_amount))} / {formatNumber(Number(day.target_amount))} {unit(metric)}</span>
        </div>
        <div className="prayer-reading-notification-row">
          <div>
            <strong>{t("prayerReading.notificationsTitle")}</strong>
            <p className="kpi-desc">{t("prayerReading.notificationsDescription")}</p>
          </div>
          <button type="button" role="switch" aria-checked={Boolean(day.plan?.notifications_enabled)}
            aria-label={t("prayerReading.notificationsToggleLabel")}
            className={`reminder-switch ${day.plan?.notifications_enabled ? "is-on" : ""}`}
            disabled={busy} onClick={() => void toggleNotifications()}>
            <span aria-hidden="true" /><span className="sr-only">{t(day.plan?.notifications_enabled ? "reminder.disable" : "reminder.enable")}</span>
          </button>
        </div>
        <div className="prayer-reading-slots">
          {PRAYERS.map(({ code, label }) => {
            const entry = day.check_ins.find((item) => item.prayer === code);
            const target = Number(day.targets[code]);
            const amount = Number(entry?.amount || 0);
            const entryMetric = entry?.metric || metric;
            const complete = target > 0 && entryMetric === metric && amount >= target;
            const readerHref = {
              pathname: localizedPath(locale, "/quran"),
              query: { mode: "after-prayer", prayer: code, prayer_date: day.local_date,
                prayer_timezone: day.timezone_name, prayer_target: String(target),
                prayer_metric: metric, prayer_credited: String(entryMetric === metric ? amount : 0),
                ...(entry && entryMetric === metric ? { check_in_id: entry.id, check_in_revision: String(entry.revision) } : {}),
              },
            };
            return <article key={code} className={`prayer-reading-slot${complete ? " is-complete" : ""}`}>
              <span className="prayer-reading-check" aria-hidden="true">{complete ? "✓" : "+"}</span>
              <div className="prayer-reading-slot-copy">
                <strong>{t(label)}</strong>
                <small>{formatNumber(amount)} {unit(entryMetric)} · {t("prayerReading.slotTarget")} {formatNumber(target)} {unit(metric)}</small>
              </div>
              <div className="prayer-reading-slot-actions">
                {target > 0 && (!entry || entryMetric === metric) && <Link href={readerHref} className="btn btn-primary btn-sm"
                  aria-label={t("prayerReading.readForPrayer", { prayer: t(label) })}>{t("prayerReading.readNow")}</Link>}
                <button type="button" className="btn btn-secondary btn-sm" disabled={busy || (!entry && target === 0)}
                  onClick={() => { setEditingPrayer(code); setActualAmount(entry ? amount : target); setError(null); }}>
                  {t(entry ? "prayerReading.editActual" : "prayerReading.recordActual")}
                </button>
              </div>
            </article>;
          })}
        </div>
        {editingPrayer && <form className="prayer-reading-manual-form" onSubmit={saveProgress}>
          <label className="form-label" htmlFor="prayer-reading-manual-amount">
            {t("prayerReading.actualFor", { prayer: t(PRAYERS.find((item) => item.code === editingPrayer)!.label) })} — {unit(editMetric)}
          </label>
          <input id="prayer-reading-manual-amount" type="number" min={editMetric === "minutes" ? 0.01 : 1}
            max={LIMITS[editMetric]} step={editMetric === "minutes" ? 0.01 : 1} value={actualAmount}
            onChange={(event) => setActualAmount(Number(event.target.value))} disabled={busy} required />
          <p>{t("prayerReading.actualHint")}</p>
          <div className="today-reading-actions">
            <button type="submit" className="btn btn-primary" disabled={busy}>{t("common.save")}</button>
            {checkIn && <button type="button" className="btn btn-danger" disabled={busy} onClick={() => void removeProgress()}>{t("prayerReading.deleteActual")}</button>}
            <button type="button" className="btn btn-secondary" disabled={busy} onClick={() => setEditingPrayer(null)}>{t("common.cancel")}</button>
          </div>
        </form>}
      </>}
    </section>
  );
}
