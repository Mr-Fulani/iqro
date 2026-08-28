"use client";

import Link from "next/link";
import { FormEvent, useCallback, useEffect, useState } from "react";
import {
  api,
  ReadingGoalMetric,
  ReadingToday,
} from "../lib/api";
import { useAuth } from "../lib/auth-context";
import { useI18n } from "../lib/i18n-context";
import { localizedPath } from "../lib/routing";

const DEFAULT_TARGETS: Record<ReadingGoalMetric, number> = {
  minutes: 5,
  pages: 2,
  ayahs: 5,
};

function browserTimezone(): string {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
  } catch {
    return "UTC";
  }
}

function todayInTimezone(timezoneName: string): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezoneName,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date());
  const value = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${value.year}-${value.month}-${value.day}`;
}

export function TodayReadingCard() {
  const { session, isLoading: authLoading, loginGuest } = useAuth();
  const { formatNumber, locale, t } = useI18n();
  const [today, setToday] = useState<ReadingToday | null>(null);
  const [loading, setLoading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [editingGoal, setEditingGoal] = useState(false);
  const [manualOpen, setManualOpen] = useState(false);
  const [metric, setMetric] = useState<ReadingGoalMetric>("minutes");
  const [target, setTarget] = useState(String(DEFAULT_TARGETS.minutes));
  const [manualAmount, setManualAmount] = useState("1");

  const [timezoneName] = useState(() => browserTimezone());

  const loadToday = useCallback(async () => {
    if (!api.getSession()) return;
    setLoading(true);
    setError(null);
    try {
      const result = await api.getReadingToday(timezoneName);
      setToday(result);
      if (result.goal) {
        setMetric(result.goal.metric);
        setTarget(String(Number(result.goal.target_amount)));
      }
    } catch (err) {
      setError(api.normalizeError(err));
    } finally {
      setLoading(false);
    }
  }, [timezoneName]);

  useEffect(() => {
    if (!authLoading && session) void loadToday();
  }, [authLoading, loadToday, session]);

  const ensureGuestSession = async (): Promise<boolean> => {
    if (api.getSession()) return true;
    return Boolean(await loginGuest());
  };

  const saveGoal = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const numericTarget = Number(target);
    if (!Number.isFinite(numericTarget) || numericTarget <= 0) return;
    if (
      today?.goal &&
      (today.goal.metric !== metric || Number(today.goal.target_amount) !== numericTarget) &&
      !window.confirm(t("reading.goalReplaceConfirm"))
    ) {
      return;
    }

    setBusy(true);
    setError(null);
    try {
      if (!(await ensureGuestSession())) throw new Error(t("reading.sessionUnavailable"));
      await api.setReadingGoal({
        metric,
        target_amount: numericTarget,
        timezone_name: timezoneName,
        base_revision: today?.goal?.revision || 0,
      });
      setEditingGoal(false);
      await loadToday();
    } catch (err) {
      setError(api.normalizeError(err));
    } finally {
      setBusy(false);
    }
  };

  const addManualReading = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const numericAmount = Number(manualAmount);
    if (!today?.goal || !Number.isFinite(numericAmount) || numericAmount <= 0) return;

    setBusy(true);
    setError(null);
    try {
      await api.createManualReadingSession({
        metric: today.goal.metric,
        amount: numericAmount,
        timezone_name: today.timezone_name,
        local_date: todayInTimezone(today.timezone_name),
      });
      setManualOpen(false);
      setManualAmount("1");
      await loadToday();
    } catch (err) {
      setError(api.normalizeError(err));
    } finally {
      setBusy(false);
    }
  };

  const updateMetric = (nextMetric: ReadingGoalMetric) => {
    setMetric(nextMetric);
    if (!today?.goal || nextMetric !== today.goal.metric) {
      setTarget(String(DEFAULT_TARGETS[nextMetric]));
    }
  };

  const progress = today?.progress;
  const achieved = Number(progress?.achieved_amount || 0);
  const goalTarget = Number(progress?.target_amount || today?.goal?.target_amount || 0);
  const percent = goalTarget > 0 ? Math.min(100, Math.round((achieved / goalTarget) * 100)) : 0;
  const unitKey = `reading.unit.${today?.goal?.metric || metric}` as const;
  const continueHref = today?.continue_reading?.ayah
    ? localizedPath(
        locale,
        `/quran?surah=${today.continue_reading.ayah.surah_number}&ayah=${today.continue_reading.ayah.ayah_number}`,
      )
    : localizedPath(locale, "/quran");
  const showGoalForm = !today?.goal || editingGoal;

  return (
    <section className="surface today-reading" data-testid="today-reading">
      <div className="surface-head today-reading-head">
        <div>
          <p className="eyebrow">{t("reading.todayEyebrow")}</p>
          <h2 className="surface-title">{t("reading.todayTitle")}</h2>
          <p className="surface-subtitle">{t("reading.todayDescription")}</p>
        </div>
        {today?.goal && !showGoalForm && (
          <button type="button" className="btn btn-outline-primary btn-sm" onClick={() => setEditingGoal(true)}>
            {t("reading.changeGoal")}
          </button>
        )}
      </div>

      {(authLoading || loading) && !today ? (
        <p className="today-reading-loading" aria-live="polite">{t("common.loading")}</p>
      ) : (
        <>
          {error && (
            <div className="alert alert-error" role="alert">
              <span>{error || t("reading.personalUnavailable")}</span>
              <button type="button" className="btn btn-secondary btn-sm" onClick={() => void loadToday()}>
                {t("common.refresh")}
              </button>
            </div>
          )}

          {showGoalForm ? (
            <form className="today-goal-form" onSubmit={saveGoal}>
              <div className="form-group">
                <label className="form-label" htmlFor="reading-goal-metric">{t("reading.goalMetric")}</label>
                <select
                  id="reading-goal-metric"
                  value={metric}
                  onChange={(event) => updateMetric(event.target.value as ReadingGoalMetric)}
                  disabled={busy}
                >
                  <option value="minutes">{t("reading.metric.minutes")}</option>
                  <option value="pages">{t("reading.metric.pages")}</option>
                  <option value="ayahs">{t("reading.metric.ayahs")}</option>
                </select>
              </div>
              <div className="form-group">
                <label className="form-label" htmlFor="reading-goal-target">{t("reading.dailyTarget")}</label>
                <input
                  id="reading-goal-target"
                  type="number"
                  min={metric === "minutes" ? "0.25" : "1"}
                  max={metric === "minutes" ? "1440" : metric === "pages" ? "604" : "6236"}
                  step={metric === "minutes" ? "0.25" : "1"}
                  value={target}
                  onChange={(event) => setTarget(event.target.value)}
                  required
                  disabled={busy}
                />
              </div>
              <div className="today-reading-actions">
                <button type="submit" className="btn btn-primary" disabled={busy}>
                  {busy ? t("common.saving") : today?.goal ? t("reading.saveGoal") : t("reading.createGoal")}
                </button>
                {today?.goal && (
                  <button type="button" className="btn btn-secondary" onClick={() => setEditingGoal(false)} disabled={busy}>
                    {t("common.cancel")}
                  </button>
                )}
              </div>
              {!session && <p className="kpi-desc">{t("reading.guestGoalHint")}</p>}
            </form>
          ) : today?.goal ? (
            <div className="today-reading-body">
              <div className="today-progress-column">
                <div className="today-progress-copy">
                  <strong>
                    {progress?.is_completed ? t("reading.goalCompleted") : t("reading.goalProgress")}
                  </strong>
                  <span>
                    {formatNumber(achieved, { maximumFractionDigits: 2 })} / {formatNumber(goalTarget, { maximumFractionDigits: 2 })} {t(unitKey)}
                  </span>
                </div>
                <div
                  className="today-progress-track"
                  role="progressbar"
                  aria-valuemin={0}
                  aria-valuemax={100}
                  aria-valuenow={percent}
                  aria-label={t("reading.goalProgress")}
                >
                  <span style={{ width: `${percent}%` }} />
                </div>
                <p className="kpi-desc">
                  {progress?.is_completed
                    ? t("reading.completedCalm")
                    : t("reading.remaining", {
                        amount: formatNumber(Number(progress?.remaining_amount || goalTarget), { maximumFractionDigits: 2 }),
                        unit: t(unitKey),
                      })}
                </p>
              </div>

              <div className="today-streak" aria-label={t("reading.streak") }>
                <span aria-hidden="true">🌱</span>
                <strong>{formatNumber(today.streak.current_count)}</strong>
                <small>{t("reading.streakDays")}</small>
              </div>

              <div className="today-reading-actions">
                <Link href={continueHref} className="btn btn-primary">
                  {today.continue_reading ? t("reading.continue") : t("reading.startReading")}
                </Link>
                <button type="button" className="btn btn-secondary" onClick={() => setManualOpen((open) => !open)}>
                  {t("reading.addManual")}
                </button>
              </div>
            </div>
          ) : null}

          {manualOpen && today?.goal && (
            <form className="today-manual-form" onSubmit={addManualReading}>
              <div className="form-group">
                <label className="form-label" htmlFor="manual-reading-amount">
                  {t("reading.manualAmount", { unit: t(unitKey) })}
                </label>
                <input
                  id="manual-reading-amount"
                  type="number"
                  min={today.goal.metric === "minutes" ? "0.25" : "1"}
                  max={today.goal.metric === "minutes" ? "1440" : today.goal.metric === "pages" ? "604" : "6236"}
                  step={today.goal.metric === "minutes" ? "0.25" : "1"}
                  value={manualAmount}
                  onChange={(event) => setManualAmount(event.target.value)}
                  required
                  autoFocus
                  disabled={busy}
                />
              </div>
              <div className="today-reading-actions">
                <button type="submit" className="btn btn-primary" disabled={busy}>
                  {busy ? t("common.saving") : t("reading.addToToday")}
                </button>
                <button type="button" className="btn btn-secondary" onClick={() => setManualOpen(false)} disabled={busy}>
                  {t("common.cancel")}
                </button>
              </div>
              <p className="kpi-desc">{t("reading.manualHint")}</p>
            </form>
          )}
        </>
      )}
    </section>
  );
}
