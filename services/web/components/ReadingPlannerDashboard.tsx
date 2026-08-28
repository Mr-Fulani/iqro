"use client";

import Link from "next/link";
import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import {
  api,
  ReadingGoalMetric,
  ReadingPlanner,
  ReadingPlannerDay,
  ReadingPlannerDayState,
  ReadingSession,
  ReadingToday,
} from "../lib/api";
import { useAuth } from "../lib/auth-context";
import { MessageKey } from "../lib/i18n";
import { useI18n } from "../lib/i18n-context";
import { localizedPath } from "../lib/routing";

const RANGE_OPTIONS = [7, 30, 90] as const;
const PRAYERS = [
  ["fajr", "prayer.fajr"],
  ["dhuhr", "prayer.dhuhr"],
  ["asr", "prayer.asr"],
  ["maghrib", "prayer.maghrib"],
  ["isha", "prayer.isha"],
] as const;
const STATE_LABELS: Record<ReadingPlannerDayState, MessageKey> = {
  no_goal: "planner.state.noGoal",
  pending: "planner.state.pending",
  missed: "planner.state.missed",
  partial: "planner.state.partial",
  completed: "planner.state.completed",
};

type AutomaticSummary = {
  sessions: number;
  activeSeconds: number;
  pages: number;
  ayahs: number;
};

type HistoryGroup = {
  localDate: string;
  manual: ReadingSession[];
  automatic: AutomaticSummary;
};

type EditDraft = {
  session: ReadingSession;
  metric: ReadingGoalMetric;
  amount: string;
  localDate: string;
};

function browserTimezone(): string {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
  } catch {
    return "UTC";
  }
}

function dateAtNoon(value: string): Date {
  return new Date(`${value}T12:00:00Z`);
}

function differenceInDays(later: string, earlier: string): number {
  return Math.round((dateAtNoon(later).getTime() - dateAtNoon(earlier).getTime()) / 86_400_000);
}

function shiftDate(value: string, days: number): string {
  const date = dateAtNoon(value);
  date.setUTCDate(date.getUTCDate() + days);
  return date.toISOString().slice(0, 10);
}

function metricUnitKey(metric: ReadingGoalMetric): MessageKey {
  return `reading.unit.${metric}` as MessageKey;
}

export function ReadingPlannerDashboard() {
  const { session, isLoading: authLoading } = useAuth();
  const { formatDate, formatNumber, locale, t } = useI18n();
  const [timezoneName] = useState(browserTimezone);
  const [rangeDays, setRangeDays] = useState<(typeof RANGE_OPTIONS)[number]>(30);
  const [planner, setPlanner] = useState<ReadingPlanner | null>(null);
  const [today, setToday] = useState<ReadingToday | null>(null);
  const [sessions, setSessions] = useState<ReadingSession[]>([]);
  const [selectedDate, setSelectedDate] = useState<string | null>(null);
  const [historyDate, setHistoryDate] = useState<string | null>(null);
  const [editDraft, setEditDraft] = useState<EditDraft | null>(null);
  const [loading, setLoading] = useState(true);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const loadPlanner = useCallback(async () => {
    if (!api.getSession()) {
      setLoading(false);
      setError(t("reading.sessionUnavailable"));
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const [plannerResult, sessionResult, todayResult] = await Promise.all([
        api.getReadingPlanner(timezoneName, rangeDays),
        api.getReadingSessions(100, "manual"),
        api.getReadingToday(timezoneName),
      ]);
      setPlanner(plannerResult);
      setSessions(sessionResult.results);
      setToday(todayResult);
      setSelectedDate((current) =>
        current && plannerResult.days.some((day) => day.local_date === current)
          ? current
          : plannerResult.local_date,
      );
    } catch (err) {
      setError(api.normalizeError(err));
    } finally {
      setLoading(false);
    }
  }, [rangeDays, t, timezoneName]);

  useEffect(() => {
    if (!authLoading) void loadPlanner();
  }, [authLoading, loadPlanner, session]);

  useEffect(() => {
    const refresh = () => void loadPlanner();
    window.addEventListener("quran-reading-progress-changed", refresh);
    return () => window.removeEventListener("quran-reading-progress-changed", refresh);
  }, [loadPlanner]);

  const selectedDay = useMemo(
    () => planner?.days.find((day) => day.local_date === selectedDate) || null,
    [planner, selectedDate],
  );
  const stats = useMemo(() => {
    const days = planner?.days || [];
    return {
      completed: days.filter((day) => day.state === "completed").length,
      partial: days.filter((day) => day.state === "partial").length,
      readingDays: days.filter((day) => day.has_reading).length,
    };
  }, [planner]);
  const historyGroups = useMemo<HistoryGroup[]>(() => {
    const groups = new Map<string, HistoryGroup>();
    const visibleDates = new Set(planner?.days.map((day) => day.local_date) || []);
    const prayerSessionIds = new Set(
      planner?.days.flatMap((day) =>
        day.prayer_check_ins
          .map((checkIn) => checkIn.reading_session_id)
          .filter((id): id is string => Boolean(id)),
      ) || [],
    );
    for (const day of planner?.days || []) {
      if (day.automatic_sessions === 0) continue;
      groups.set(day.local_date, {
        localDate: day.local_date,
        manual: [],
        automatic: {
          sessions: day.automatic_sessions,
          activeSeconds: day.automatic_active_seconds,
          pages: day.automatic_pages,
          ayahs: day.automatic_ayahs,
        },
      });
    }
    for (const item of sessions) {
      if (
        item.source !== "manual" ||
        !visibleDates.has(item.local_date) ||
        prayerSessionIds.has(item.id)
      ) {
        continue;
      }
      const group = groups.get(item.local_date) || {
        localDate: item.local_date,
        manual: [],
        automatic: { sessions: 0, activeSeconds: 0, pages: 0, ayahs: 0 },
      };
      group.manual.push(item);
      groups.set(item.local_date, group);
    }
    return [...groups.values()]
      .filter((group) => historyDate === null || group.localDate === historyDate)
      .sort((left, right) => right.localDate.localeCompare(left.localDate));
  }, [historyDate, planner, sessions]);

  const continueHref = today?.continue_reading?.ayah
    ? localizedPath(
        locale,
        `/quran?surah=${today.continue_reading.ayah.surah_number}&ayah=${today.continue_reading.ayah.ayah_number}`,
      )
    : localizedPath(locale, "/quran");
  const firstCalendarDate = planner?.days[0]?.local_date;
  const calendarOffset = firstCalendarDate
    ? (dateAtNoon(firstCalendarDate).getUTCDay() + 6) % 7
    : 0;
  const weekdayLabels = Array.from({ length: 7 }, (_, index) => {
    const date = new Date(Date.UTC(2024, 0, 1 + index, 12));
    return formatDate(date, { weekday: "short", timeZone: "UTC" });
  });

  const openDay = (day: ReadingPlannerDay) => {
    setSelectedDate(day.local_date);
    setHistoryDate(day.local_date);
  };

  const startEditing = (item: ReadingSession) => {
    if (!item.manual_metric || !item.manual_amount) return;
    setEditDraft({
      session: item,
      metric: item.manual_metric,
      amount: String(Number(item.manual_amount)),
      localDate: item.local_date,
    });
    setError(null);
  };

  const saveManualEntry = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    if (!editDraft) return;
    const amount = Number(editDraft.amount);
    if (!Number.isFinite(amount) || amount <= 0) return;
    setBusyId(editDraft.session.id);
    setError(null);
    try {
      await api.updateManualReadingSession(editDraft.session.id, {
        metric: editDraft.metric,
        amount,
        timezone_name: editDraft.session.timezone_name,
        local_date: editDraft.localDate,
        base_revision: editDraft.session.revision,
      });
      setEditDraft(null);
      window.dispatchEvent(new Event("quran-reading-progress-changed"));
    } catch (err) {
      setError(api.normalizeError(err));
    } finally {
      setBusyId(null);
    }
  };

  const deleteManualEntry = async (item: ReadingSession) => {
    if (!window.confirm(t("planner.history.deleteConfirm"))) return;
    setBusyId(item.id);
    setError(null);
    try {
      await api.deleteManualReadingSession(item.id, item.revision);
      if (editDraft?.session.id === item.id) setEditDraft(null);
      window.dispatchEvent(new Event("quran-reading-progress-changed"));
    } catch (err) {
      setError(api.normalizeError(err));
    } finally {
      setBusyId(null);
    }
  };

  return (
    <div className="planner-dashboard" data-testid="reading-planner-dashboard">
      <section className="surface planner-summary">
        <div className="surface-head planner-summary-head">
          <div>
            <p className="eyebrow">{t("planner.eyebrow")}</p>
            <h1 className="surface-title">{t("planner.title")}</h1>
            <p className="surface-subtitle">{t("planner.description")}</p>
          </div>
          <div className="planner-summary-actions">
            <Link href={continueHref} className="btn btn-primary">
              {today?.continue_reading ? t("reading.continue") : t("reading.startReading")}
            </Link>
            <button type="button" className="btn btn-secondary" onClick={() => void loadPlanner()}>
              {t("common.refresh")}
            </button>
          </div>
        </div>

        {error && (
          <div className="alert alert-error" role="alert">
            {error}
          </div>
        )}
        <div className="planner-stats" aria-label={t("planner.statsAria")}>
          <article>
            <strong>{formatNumber(stats.readingDays)}</strong>
            <span>{t("planner.stats.readingDays")}</span>
          </article>
          <article>
            <strong>{formatNumber(stats.completed)}</strong>
            <span>{t("planner.stats.completed")}</span>
          </article>
          <article>
            <strong>{formatNumber(stats.partial)}</strong>
            <span>{t("planner.stats.partial")}</span>
          </article>
          <article>
            <strong>{formatNumber(today?.streak.current_count || 0)}</strong>
            <span>{t("planner.stats.streak")}</span>
          </article>
        </div>
        <p className="planner-calm-note">{t("planner.noDebt")}</p>
      </section>

      <section className="surface planner-calendar-section">
        <div className="surface-head planner-calendar-head">
          <div>
            <h2 className="surface-title">{t("planner.calendarTitle")}</h2>
            <p className="surface-subtitle">{t("planner.calendarDescription")}</p>
          </div>
          <div className="planner-range" aria-label={t("planner.rangeAria")}>
            {RANGE_OPTIONS.map((days) => (
              <button
                key={days}
                type="button"
                className={`btn btn-sm ${rangeDays === days ? "btn-primary" : "btn-secondary"}`}
                onClick={() => setRangeDays(days)}
                aria-pressed={rangeDays === days}
              >
                {t("planner.rangeDays", { days: formatNumber(days) })}
              </button>
            ))}
          </div>
        </div>

        {loading && !planner ? (
          <p aria-live="polite">{t("common.loading")}</p>
        ) : (
          <>
            <div className="planner-calendar" role="grid" aria-label={t("planner.calendarAria")}>
              {weekdayLabels.map((label) => (
                <span key={label} className="planner-weekday" role="columnheader">
                  {label}
                </span>
              ))}
              {Array.from({ length: calendarOffset }, (_, index) => (
                <span key={`offset-${index}`} className="planner-calendar-offset" aria-hidden="true" />
              ))}
              {planner?.days.map((day) => {
                const goal = day.goal;
                const isSelected = selectedDate === day.local_date;
                return (
                  <button
                    key={day.local_date}
                    type="button"
                    role="gridcell"
                    className={`planner-day is-${day.state}${isSelected ? " is-selected" : ""}`}
                    onClick={() => openDay(day)}
                    aria-selected={isSelected}
                    aria-label={`${formatDate(dateAtNoon(day.local_date), { dateStyle: "long", timeZone: "UTC" })}: ${t(STATE_LABELS[day.state])}`}
                  >
                    <span className="planner-day-number">
                      <b>{formatNumber(dateAtNoon(day.local_date).getUTCDate())}</b>
                      <em>
                        {formatDate(dateAtNoon(day.local_date), {
                          month: "short",
                          timeZone: "UTC",
                        })}
                      </em>
                    </span>
                    <span className="planner-day-state">{t(STATE_LABELS[day.state])}</span>
                    {goal && (
                      <small>
                        {formatNumber(Number(goal.achieved_amount), { maximumFractionDigits: 2 })}/{formatNumber(Number(goal.target_amount), { maximumFractionDigits: 2 })} {t(metricUnitKey(goal.metric))}
                      </small>
                    )}
                    {!goal && day.has_reading && <small>📖 {t("planner.readingRecorded")}</small>}
                    {day.prayer_count > 0 && (
                      <small>🕌 {formatNumber(day.prayer_count)}/5 · {formatNumber(day.prayer_pages)} {t("reading.unit.pages")}</small>
                    )}
                  </button>
                );
              })}
            </div>
            <div className="planner-legend" aria-label={t("planner.legendAria")}>
              {(
                ["completed", "partial", "missed", "pending", "no_goal"] as ReadingPlannerDayState[]
              ).map((state) => (
                <span key={state}>
                  <i className={`is-${state}`} aria-hidden="true" />
                  {t(STATE_LABELS[state])}
                </span>
              ))}
            </div>
          </>
        )}
      </section>

      {selectedDay && (
        <section className="surface planner-day-detail" data-testid="planner-day-detail">
          <div className="surface-head">
            <div>
              <p className="eyebrow">{t("planner.selectedDay")}</p>
              <h2 className="surface-title">
                {formatDate(dateAtNoon(selectedDay.local_date), { dateStyle: "long", timeZone: "UTC" })}
              </h2>
              <p className="surface-subtitle">{t(STATE_LABELS[selectedDay.state])}</p>
            </div>
            <button
              type="button"
              className="btn btn-secondary btn-sm"
              onClick={() => setHistoryDate(selectedDay.local_date)}
            >
              {t("planner.showDayEntries")}
            </button>
          </div>
          <div className="planner-day-detail-grid">
            <article className="planner-detail-card">
              <strong>{t("planner.dailyGoal")}</strong>
              {selectedDay.goal ? (
                <>
                  <span>
                    {formatNumber(Number(selectedDay.goal.achieved_amount), { maximumFractionDigits: 2 })} / {formatNumber(Number(selectedDay.goal.target_amount), { maximumFractionDigits: 2 })} {t(metricUnitKey(selectedDay.goal.metric))}
                  </span>
                  <small>
                    {selectedDay.state === "missed" ? t("planner.missedCalm") : t(STATE_LABELS[selectedDay.state])}
                  </small>
                </>
              ) : <span>{t("planner.state.noGoal")}</span>}
            </article>
            <article className="planner-detail-card">
              <strong>{t("planner.afterPrayer")}</strong>
              <span>
                {formatNumber(selectedDay.prayer_count)} / 5 · {formatNumber(selectedDay.prayer_pages)}{" "}
                {t("reading.unit.pages")}
              </span>
              <div className="planner-prayer-badges">
                {PRAYERS.map(([code, label]) => {
                  const checkIn = selectedDay.prayer_check_ins.find((item) => item.prayer === code);
                  return (
                    <span key={code} className={checkIn ? "is-complete" : ""}>
                      {t(label)} · {formatNumber(checkIn?.pages || 0)}
                    </span>
                  );
                })}
              </div>
            </article>
          </div>
        </section>
      )}

      <section className="surface planner-history" data-testid="reading-history">
        <div className="surface-head">
          <div>
            <h2 className="surface-title">{t("planner.historyTitle")}</h2>
            <p className="surface-subtitle">{t("planner.historyDescription")}</p>
          </div>
          {historyDate && (
            <button type="button" className="btn btn-secondary btn-sm" onClick={() => setHistoryDate(null)}>
              {t("planner.showAllEntries")}
            </button>
          )}
        </div>

        {historyGroups.length === 0 ? (
          <p className="planner-history-empty">{t("planner.historyEmpty")}</p>
        ) : (
          <div className="planner-history-groups">
            {historyGroups.map((group) => (
              <article key={group.localDate} className="planner-history-group">
                <div className="planner-history-date">
                  <strong>{formatDate(dateAtNoon(group.localDate), { dateStyle: "long", timeZone: "UTC" })}</strong>
                </div>
                {group.automatic.sessions > 0 && (
                  <div className="planner-history-entry is-automatic">
                    <span className="planner-history-icon" aria-hidden="true">⏱</span>
                    <div>
                      <strong>{t("planner.history.automatic")}</strong>
                      <small>
                        {t("planner.history.automaticSummary", {
                          minutes: formatNumber(group.automatic.activeSeconds / 60, { maximumFractionDigits: 1 }),
                          pages: formatNumber(group.automatic.pages),
                          ayahs: formatNumber(group.automatic.ayahs),
                        })}
                      </small>
                    </div>
                  </div>
                )}
                {group.manual.map((item) => {
                  const canEdit = planner ? differenceInDays(planner.local_date, item.local_date) <= 7 : false;
                  const isEditing = editDraft?.session.id === item.id;
                  return (
                    <div key={item.id} className="planner-history-entry is-manual">
                      <span className="planner-history-icon" aria-hidden="true">✍️</span>
                      <div className="planner-history-entry-copy">
                        <strong>{t("planner.history.manual")}</strong>
                        <small>
                          {formatNumber(Number(item.manual_amount || 0), { maximumFractionDigits: 2 })} {item.manual_metric ? t(metricUnitKey(item.manual_metric)) : ""}
                        </small>
                        {!canEdit && <small>{t("planner.history.editWindow")}</small>}
                      </div>
                      <div className="planner-history-actions">
                        {canEdit && (
                          <button
                            type="button"
                            className="btn btn-secondary btn-sm"
                            onClick={() => startEditing(item)}
                            disabled={busyId !== null}
                          >
                            {t("common.edit")}
                          </button>
                        )}
                        <button
                          type="button"
                          className="btn btn-danger btn-sm"
                          onClick={() => void deleteManualEntry(item)}
                          disabled={busyId !== null}
                        >
                          {t("common.delete")}
                        </button>
                      </div>
                      {isEditing && editDraft && planner && (
                        <form className="planner-history-edit" onSubmit={saveManualEntry}>
                          <div className="form-group">
                            <label className="form-label" htmlFor={`planner-edit-date-${item.id}`}>
                              {t("planner.history.date")}
                            </label>
                            <input
                              id={`planner-edit-date-${item.id}`}
                              type="date"
                              min={shiftDate(planner.local_date, -7)}
                              max={planner.local_date}
                              value={editDraft.localDate}
                              onChange={(event) =>
                                setEditDraft({ ...editDraft, localDate: event.target.value })
                              }
                              required
                              disabled={busyId !== null}
                            />
                          </div>
                          <div className="form-group">
                            <label className="form-label" htmlFor={`planner-edit-metric-${item.id}`}>
                              {t("reading.goalMetric")}
                            </label>
                            <select
                              id={`planner-edit-metric-${item.id}`}
                              value={editDraft.metric}
                              onChange={(event) =>
                                setEditDraft({
                                  ...editDraft,
                                  metric: event.target.value as ReadingGoalMetric,
                                })
                              }
                              disabled={busyId !== null}
                            >
                              <option value="minutes">{t("reading.metric.minutes")}</option>
                              <option value="pages">{t("reading.metric.pages")}</option>
                              <option value="ayahs">{t("reading.metric.ayahs")}</option>
                            </select>
                          </div>
                          <div className="form-group">
                            <label className="form-label" htmlFor={`planner-edit-amount-${item.id}`}>
                              {t("planner.history.amount")}
                            </label>
                            <input
                              id={`planner-edit-amount-${item.id}`}
                              type="number"
                              min={editDraft.metric === "minutes" ? "0.25" : "1"}
                              max={
                                editDraft.metric === "minutes"
                                  ? "1440"
                                  : editDraft.metric === "pages"
                                    ? "604"
                                    : "6236"
                              }
                              step={editDraft.metric === "minutes" ? "0.25" : "1"}
                              value={editDraft.amount}
                              onChange={(event) =>
                                setEditDraft({ ...editDraft, amount: event.target.value })
                              }
                              required
                              disabled={busyId !== null}
                            />
                          </div>
                          <div className="planner-history-actions">
                            <button
                              type="submit"
                              className="btn btn-primary btn-sm"
                              disabled={busyId !== null}
                            >
                              {busyId ? t("common.saving") : t("common.save")}
                            </button>
                            <button
                              type="button"
                              className="btn btn-secondary btn-sm"
                              onClick={() => setEditDraft(null)}
                              disabled={busyId !== null}
                            >
                              {t("common.cancel")}
                            </button>
                          </div>
                        </form>
                      )}
                    </div>
                  );
                })}
              </article>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
