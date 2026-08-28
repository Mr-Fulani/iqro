"use client";

import { FormEvent, useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  api,
  Ayah,
  generateUuidV7,
  MemorizationAssessment,
  MemorizationDashboard,
  Recitation,
  Surah,
} from "../lib/api";
import { useAuth } from "../lib/auth-context";
import { useI18n } from "../lib/i18n-context";
import { latestRecitationsByVariant } from "../lib/reciter-catalog";
import {
  loadReciterPreference,
  preferredRecitation,
  rememberReciterPreference,
} from "../lib/reciter-preference";
import { MemorizationAudioLoop } from "./MemorizationAudioLoop";
import { MemorizationTajweedAyahs } from "./MemorizationTajweedAyahs";

type PracticeMode = "read" | "listen" | "test";

function browserTimezone(): string {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
  } catch {
    return "UTC";
  }
}

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.min(Math.max(value, minimum), maximum);
}

export function MemorizationWorkspace() {
  const { session, isLoading: authLoading } = useAuth();
  const { formatDate, formatNumber, locale, t } = useI18n();
  const [timezoneName] = useState(browserTimezone);
  const [dashboard, setDashboard] = useState<MemorizationDashboard | null>(null);
  const [surahs, setSurahs] = useState<Surah[]>([]);
  const [ayahs, setAyahs] = useState<Ayah[]>([]);
  const [recitations, setRecitations] = useState<Recitation[]>([]);
  const [selectedSurah, setSelectedSurah] = useState(1);
  const [startAyah, setStartAyah] = useState(1);
  const [endAyah, setEndAyah] = useState(1);
  const [recitationId, setRecitationId] = useState("");
  const [dailyRepetitions, setDailyRepetitions] = useState(5);
  const [pauseSeconds, setPauseSeconds] = useState(2);
  const [editingPlan, setEditingPlan] = useState(false);
  const [mode, setMode] = useState<PracticeMode>("read");
  const [revealedAyahs, setRevealedAyahs] = useState<Set<number>>(new Set());
  const [localRepetitions, setLocalRepetitions] = useState(0);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const practiceStartedAt = useRef<number | null>(null);
  const pendingSessionId = useRef<string | null>(null);
  const deepLinkApplied = useRef(false);

  const surahName = useCallback((surah: Surah) => {
    if (locale === "ar") return surah.name_ar;
    if (locale === "ru") return surah.name_ru;
    return surah.name_en;
  }, [locale]);
  const reciterName = useCallback((recitation: Recitation) => {
    if (locale === "ar") return recitation.reciter.name_ar;
    if (locale === "ru") return recitation.reciter.name_ru;
    return recitation.reciter.name_en;
  }, [locale]);

  const applyPlan = useCallback((next: MemorizationDashboard) => {
    setDashboard(next);
    if (!next.plan) {
      setEditingPlan(true);
      return;
    }
    setSelectedSurah(next.plan.start_ayah.surah_number);
    setStartAyah(next.plan.start_ayah.ayah_number);
    setEndAyah(next.plan.end_ayah.ayah_number);
    setRecitationId(next.plan.recitation_id || "");
    setDailyRepetitions(next.plan.daily_repetitions);
    setPauseSeconds(next.plan.pause_seconds);
    setEditingPlan(false);
  }, []);

  const loadDashboard = useCallback(async () => {
    const next = await api.getMemorizationDashboard(timezoneName);
    applyPlan(next);
    return next;
  }, [applyPlan, timezoneName]);

  useEffect(() => {
    if (authLoading) return;
    if (!api.getSession()) {
      setLoading(false);
      setError(t("reading.sessionUnavailable"));
      return;
    }
    let active = true;
    setLoading(true);
    setError(null);
    Promise.all([
      loadDashboard(),
      api.getSurahs("madani-hafs"),
      api.getAllRecitations({ quran_edition: "madani-hafs" }),
    ])
      .then(([nextDashboard, nextSurahs, allRecitations]) => {
        if (!active) return;
        setSurahs(nextSurahs);
        const availableRecitations = latestRecitationsByVariant(allRecitations).filter(
          (item) => item.rights.stream && item.timings.available,
        );
        setRecitations(availableRecitations);
        const plannedRecitation = availableRecitations.find(
          (item) => item.id === nextDashboard.plan?.recitation_id,
        );
        if (plannedRecitation) {
          rememberReciterPreference(plannedRecitation.reciter, plannedRecitation);
        } else if (!nextDashboard.plan) {
          const remembered = preferredRecitation(
            availableRecitations,
            loadReciterPreference(),
          );
          if (remembered) setRecitationId(remembered.id);
        }
        if (!nextDashboard.plan && !deepLinkApplied.current) {
          deepLinkApplied.current = true;
          const params = new URLSearchParams(window.location.search);
          const linkedSurah = Number(params.get("surah"));
          const linkedStart = Number(params.get("start_ayah"));
          const linkedEnd = Number(params.get("end_ayah"));
          if (Number.isInteger(linkedSurah) && linkedSurah >= 1 && linkedSurah <= 114) {
            setSelectedSurah(linkedSurah);
            setStartAyah(Math.max(1, linkedStart || 1));
            setEndAyah(Math.max(1, linkedEnd || linkedStart || 1));
          }
        }
      })
      .catch((reason) => {
        if (active) setError(api.normalizeError(reason));
      })
      .finally(() => {
        if (active) setLoading(false);
      });
    return () => {
      active = false;
    };
  }, [authLoading, loadDashboard, session, t]);

  useEffect(() => {
    let active = true;
    setAyahs([]);
    api.getAyahs("madani-hafs", selectedSurah)
      .then((items) => {
        if (!active) return;
        setAyahs(items);
        const maximum = Math.max(1, items.length);
        setStartAyah((value) => clamp(value, 1, maximum));
        setEndAyah((value) => clamp(value, 1, maximum));
      })
      .catch((reason) => {
        if (active) setError(api.normalizeError(reason));
      });
    return () => {
      active = false;
    };
  }, [selectedSurah]);

  const practiceAyahs = useMemo(
    () => ayahs.filter((item) => item.number >= startAyah && item.number <= endAyah),
    [ayahs, endAyah, startAyah],
  );
  const plan = dashboard?.plan || null;
  const recordedToday = dashboard?.today.completed_repetitions || 0;
  const totalToday = recordedToday + localRepetitions;
  const targetToday = plan?.daily_repetitions || dailyRepetitions;
  const progressPercent = targetToday > 0 ? Math.min(100, (totalToday / targetToday) * 100) : 0;
  const remainingForAudio = Math.max(targetToday - totalToday, 1);
  const hiddenPracticeAyahs = useMemo(
    () => new Set(
      mode === "test"
        ? practiceAyahs
            .filter((ayah) => !revealedAyahs.has(ayah.number))
            .map((ayah) => ayah.number)
        : [],
    ),
    [mode, practiceAyahs, revealedAyahs],
  );

  const savePlan = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const start = ayahs.find((item) => item.number === startAyah);
    const end = ayahs.find((item) => item.number === endAyah);
    if (!start || !end || end.number < start.number) {
      setError(t("memorization.rangeInvalid"));
      return;
    }
    setSaving(true);
    setError(null);
    try {
      await api.saveMemorizationPlan({
        start_ayah_id: start.id,
        end_ayah_id: end.id,
        recitation_id: recitationId || null,
        daily_repetitions: dailyRepetitions,
        pause_seconds: pauseSeconds,
        timezone_name: timezoneName,
        base_revision: plan?.revision || 0,
      });
      await loadDashboard();
      setLocalRepetitions(0);
      pendingSessionId.current = null;
      practiceStartedAt.current = Date.now();
      window.dispatchEvent(new Event("memorization-progress-changed"));
    } catch (reason) {
      setError(api.normalizeError(reason));
    } finally {
      setSaving(false);
    }
  };

  const addRepetition = () => {
    if (practiceStartedAt.current === null) practiceStartedAt.current = Date.now();
    setLocalRepetitions((value) => value + 1);
  };

  const selectRecitation = (nextRecitationId: string) => {
    const recitation = recitations.find((item) => item.id === nextRecitationId);
    if (recitation) rememberReciterPreference(recitation.reciter, recitation);
    setRecitationId(nextRecitationId);
  };

  const resetCounters = async () => {
    if (totalToday < 1 || !window.confirm(t("memorization.resetConfirm"))) return;
    setSaving(true);
    setError(null);
    setMode("read");
    setLocalRepetitions(0);
    pendingSessionId.current = null;
    practiceStartedAt.current = Date.now();
    try {
      if (recordedToday > 0) {
        await api.resetTodayMemorizationProgress(timezoneName);
        await loadDashboard();
      }
      window.dispatchEvent(new Event("memorization-progress-changed"));
    } catch (reason) {
      setError(api.normalizeError(reason));
      await loadDashboard().catch(() => undefined);
    } finally {
      setSaving(false);
    }
  };

  const finishSession = async (assessment: MemorizationAssessment) => {
    if (!plan || localRepetitions < 1 || !dashboard) return;
    setSaving(true);
    setError(null);
    try {
      const startedAt = practiceStartedAt.current ?? Date.now();
      pendingSessionId.current ||= generateUuidV7();
      await api.createMemorizationSession({
        id: pendingSessionId.current,
        plan_id: plan.id,
        completed_repetitions: localRepetitions,
        assessment,
        duration_seconds: clamp(
          Math.round((Date.now() - startedAt) / 1000),
          0,
          86_400,
        ),
        timezone_name: dashboard.timezone_name,
        local_date: dashboard.today.local_date,
      });
      setLocalRepetitions(0);
      pendingSessionId.current = null;
      setRevealedAyahs(new Set());
      practiceStartedAt.current = Date.now();
      await loadDashboard();
      window.dispatchEvent(new Event("memorization-progress-changed"));
    } catch (reason) {
      setError(api.normalizeError(reason));
    } finally {
      setSaving(false);
    }
  };

  const revealAyah = (ayahNumber: number) => {
    setRevealedAyahs((current) => new Set(current).add(ayahNumber));
  };

  if (loading) return <section className="surface"><p>{t("common.loading")}</p></section>;

  return (
    <div className="memorization-stack">
      <section className="surface memorization-hero">
        <div className="surface-head">
          <div>
            <p className="eyebrow">{t("memorization.eyebrow")}</p>
            <h1 className="surface-title">{t("memorization.title")}</h1>
            <p className="surface-subtitle">{t("memorization.description")}</p>
          </div>
          {plan && !editingPlan && (
            <button type="button" className="btn btn-secondary" onClick={() => setEditingPlan(true)}>
              {t("memorization.changePlan")}
            </button>
          )}
        </div>
      </section>

      {(editingPlan || !plan) && (
        <section className="surface" data-testid="memorization-plan-form">
          <div className="surface-head">
            <div>
              <p className="eyebrow">{t("memorization.planEyebrow")}</p>
              <h2 className="surface-title">{plan ? t("memorization.changePlan") : t("memorization.createPlan")}</h2>
              <p className="surface-subtitle">{t("memorization.planDescription")}</p>
            </div>
          </div>
          <form className="memorization-plan-form" onSubmit={(event) => void savePlan(event)}>
            <label className="form-group">
              <span className="form-label">{t("memorization.surah")}</span>
              <select
                value={selectedSurah}
                onChange={(event) => {
                  setSelectedSurah(Number(event.target.value));
                  setStartAyah(1);
                  setEndAyah(1);
                }}
              >
                {surahs.map((surah) => (
                  <option key={surah.id} value={surah.number}>
                    {formatNumber(surah.number)}. {surahName(surah)} — {surah.name_ar}
                  </option>
                ))}
              </select>
            </label>
            <label className="form-group">
              <span className="form-label">{t("memorization.startAyah")}</span>
              <select value={startAyah} onChange={(event) => {
                const value = Number(event.target.value);
                setStartAyah(value);
                setEndAyah((current) => Math.max(current, value));
              }}>
                {ayahs.map((ayah) => <option key={ayah.id} value={ayah.number}>{formatNumber(ayah.number)}</option>)}
              </select>
            </label>
            <label className="form-group">
              <span className="form-label">{t("memorization.endAyah")}</span>
              <select value={endAyah} onChange={(event) => setEndAyah(Number(event.target.value))}>
                {ayahs.filter((ayah) => ayah.number >= startAyah).map((ayah) => (
                  <option key={ayah.id} value={ayah.number}>{formatNumber(ayah.number)}</option>
                ))}
              </select>
            </label>
            <label className="form-group">
              <span className="form-label">{t("memorization.dailyRepetitions")}</span>
              <input type="number" min={1} max={100} value={dailyRepetitions} onChange={(event) => setDailyRepetitions(clamp(Number(event.target.value), 1, 100))} />
            </label>
            <label className="form-group">
              <span className="form-label">{t("memorization.pauseSeconds")}</span>
              <input type="number" min={0} max={30} value={pauseSeconds} onChange={(event) => setPauseSeconds(clamp(Number(event.target.value), 0, 30))} />
            </label>
            <label className="form-group memorization-reciter-field">
              <span className="form-label">{t("memorization.reciter")}</span>
              <select value={recitationId} onChange={(event) => selectRecitation(event.target.value)}>
                <option value="">{t("memorization.withoutAudio")}</option>
                {recitations.map((recitation) => (
                  <option key={recitation.id} value={recitation.id}>
                    {reciterName(recitation)} · {recitation.style}
                  </option>
                ))}
              </select>
            </label>
            <div className="memorization-form-actions">
              <button type="submit" className="btn btn-primary" disabled={saving || ayahs.length === 0}>
                {saving ? t("common.saving") : t("memorization.savePlan")}
              </button>
              {plan && (
                <button type="button" className="btn btn-secondary" onClick={() => {
                  applyPlan(dashboard!);
                  setEditingPlan(false);
                }}>
                  {t("common.cancel")}
                </button>
              )}
            </div>
          </form>
        </section>
      )}

      {plan && !editingPlan && (
        <>
          <section className="surface" data-testid="memorization-progress">
            <div className="surface-head">
              <div>
                <p className="eyebrow">{t("memorization.todayEyebrow")}</p>
                <h2 className="surface-title">
                  {t("memorization.rangeTitle", {
                    surah: formatNumber(plan.start_ayah.surah_number),
                    start: formatNumber(plan.start_ayah.ayah_number),
                    end: formatNumber(plan.end_ayah.ayah_number),
                  })}
                </h2>
                <p className="surface-subtitle">
                  {t("memorization.syncedHint")}
                </p>
              </div>
              <div className="memorization-progress-total">
                <strong>{formatNumber(totalToday)} / {formatNumber(targetToday)}</strong>
                <span>{t("memorization.repetitions")}</span>
                <button
                  type="button"
                  className="btn btn-danger btn-sm"
                  onClick={() => void resetCounters()}
                  disabled={saving || totalToday < 1}
                >
                  {t("memorization.resetCounters")}
                </button>
              </div>
            </div>
            <div className="today-progress-track" aria-label={t("memorization.todayProgress")}>
              <span style={{ width: `${progressPercent}%` }} />
            </div>
            <p className="field-help">
              {dashboard?.today.is_completed && localRepetitions === 0
                ? t("memorization.todayCompleted")
                : t("memorization.remaining", { count: formatNumber(Math.max(targetToday - totalToday, 0)) })}
            </p>
          </section>

          <section className="surface memorization-practice" data-testid="memorization-practice">
            <div className="memorization-mode-tabs" role="tablist" aria-label={t("memorization.modeAria")}>
              {(["read", "listen", "test"] as const).map((item) => (
                <button
                  key={item}
                  type="button"
                  className={`btn ${mode === item ? "btn-primary" : "btn-secondary"}`}
                  onClick={() => {
                    setMode(item);
                    setRevealedAyahs(new Set());
                  }}
                  role="tab"
                  aria-selected={mode === item}
                >
                  {t(`memorization.mode.${item}`)}
                </button>
              ))}
            </div>

            {mode === "listen" && (
              <MemorizationAudioLoop
                recitationId={plan.recitation_id}
                surahNumber={plan.start_ayah.surah_number}
                startAyah={plan.start_ayah.ayah_number}
                endAyah={plan.end_ayah.ayah_number}
                repeatLimit={remainingForAudio}
                pauseSeconds={plan.pause_seconds}
                onCycleComplete={addRepetition}
              />
            )}

            <MemorizationTajweedAyahs
              ayahs={practiceAyahs}
              hiddenAyahs={hiddenPracticeAyahs}
              onReveal={revealAyah}
            />

            <div className="memorization-counter">
              <div>
                <span>{t("memorization.currentSession")}</span>
                <strong>{formatNumber(localRepetitions)} {t("memorization.repetitions")}</strong>
              </div>
              <button type="button" className="btn btn-secondary" onClick={addRepetition}>
                {t("memorization.addRepetition")}
              </button>
            </div>

            {localRepetitions > 0 && (
              <div className="memorization-assessment">
                <p>{t("memorization.assessmentQuestion")}</p>
                <div className="memorization-assessment-actions">
                  <button type="button" className="btn btn-secondary" disabled={saving} onClick={() => void finishSession("difficult")}>{t("memorization.assessment.difficult")}</button>
                  <button type="button" className="btn btn-secondary" disabled={saving} onClick={() => void finishSession("repeat")}>{t("memorization.assessment.repeat")}</button>
                  <button type="button" className="btn btn-primary" disabled={saving} onClick={() => void finishSession("memorized")}>{t("memorization.assessment.memorized")}</button>
                </div>
              </div>
            )}
          </section>

          <section className="surface">
            <div className="surface-head">
              <div>
                <p className="eyebrow">{t("memorization.historyEyebrow")}</p>
                <h2 className="surface-title">{t("memorization.historyTitle")}</h2>
              </div>
            </div>
            {dashboard?.recent_days.length ? (
              <div className="memorization-history-list">
                {dashboard.recent_days.map((day) => (
                  <div key={day.local_date} className="memorization-history-row">
                    <span>{formatDate(`${day.local_date}T12:00:00`, { dateStyle: "medium" })}</span>
                    <strong>{t("memorization.historyRepetitions", { count: formatNumber(day.completed_repetitions) })}</strong>
                    <span>{t(`memorization.assessment.${day.last_assessment}`)}</span>
                  </div>
                ))}
              </div>
            ) : <p className="muted">{t("memorization.historyEmpty")}</p>}
          </section>
        </>
      )}

      {error && <p className="error-text" role="alert">{error}</p>}
    </div>
  );
}
