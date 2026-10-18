"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { preload } from "react-dom";

import { claimAudioFocus, registerAudioPlayer } from "../lib/audio-focus";
import { useI18n } from "../lib/i18n-context";
import type { MessageKey } from "../lib/i18n";
import { localizedPath } from "../lib/routing";
import {
  formulaAudioRange,
  readSalahProgress,
  recordSalahStep,
  resumeStepIndex,
  type SalahFormula,
  type SalahLessonBundle,
  type SalahMedia,
  type SalahStep,
  stepRepeatTarget,
  stepSlugFromLocation,
  writeSalahProgress,
} from "../lib/salah";

type Mode = "learn" | "practice";
type Display = { mode: Mode; transliteration: boolean; translation: boolean };

const DISPLAY_STORAGE_KEY = "iqro_salah_display_v1";
const DEFAULT_DISPLAY: Display = { mode: "learn", transliteration: true, translation: true };
const RULING_LABELS: Record<NonNullable<SalahStep["ruling"]>, MessageKey> = {
  shart: "salah.rulingShart",
  rukn: "salah.rulingRukn",
  wajib: "salah.rulingWajib",
  sunnah: "salah.rulingSunnah",
};

function readDisplay(): Display {
  try {
    const parsed = JSON.parse(window.localStorage.getItem(DISPLAY_STORAGE_KEY) || "{}") as Partial<Display>;
    return {
      mode: parsed.mode === "practice" ? "practice" : "learn",
      transliteration: parsed.transliteration !== false,
      translation: parsed.translation !== false,
    };
  } catch {
    return DEFAULT_DISPLAY;
  }
}

function AudioIcon({ playing }: { playing: boolean }) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      {playing ? (
        <>
          <path d="M7 5h3v14H7z" fill="currentColor" />
          <path d="M14 5h3v14h-3z" fill="currentColor" />
        </>
      ) : (
        <path d="m8 5 11 7-11 7Z" fill="currentColor" />
      )}
    </svg>
  );
}

function RepetitionCounter({ target, label }: { target: number; label: string }) {
  const { formatNumber, t } = useI18n();
  const [count, setCount] = useState(0);
  const done = count >= target;
  return (
    <div className={`salah-counter${done ? " is-done" : ""}`} role="group" aria-label={label}>
      <button
        type="button"
        className="salah-counter-add"
        onClick={() => setCount((value) => Math.min(target, value + 1))}
        disabled={done}
        aria-label={t("salah.counterAdd")}
      >
        +1
      </button>
      <output aria-live="polite">
        {done
          ? `${t("salah.counterDone")} · ${formatNumber(target)}`
          : t("salah.counter", { count: formatNumber(count), total: formatNumber(target) })}
      </output>
      <button
        type="button"
        className="salah-counter-reset"
        onClick={() => setCount(0)}
        disabled={count === 0}
        aria-label={t("salah.counterReset")}
        title={t("salah.counterReset")}
      >
        ↺
      </button>
    </div>
  );
}

function StepImage({ media, eager }: { media: SalahMedia; eager: boolean }) {
  return (
    // Course images are versioned WebP files from object storage with known
    // dimensions; next/image has no remote pattern for them.
    // eslint-disable-next-line @next/next/no-img-element
    <img
      className="salah-step-image"
      src={media.url}
      width={media.width}
      height={media.height}
      alt={media.alt}
      loading={eager ? "eager" : "lazy"}
      decoding="async"
    />
  );
}

export function SalahStepPlayer({
  bundle,
  nextLesson,
}: {
  bundle: SalahLessonBundle;
  nextLesson: { slug: string; title: string } | null;
}) {
  const { direction, formatNumber, locale, t } = useI18n();
  const { lesson, formulas, media, courseVersion } = bundle;
  const steps = lesson.steps;
  const [index, setIndex] = useState(0);
  const [ready, setReady] = useState(false);
  const [completed, setCompleted] = useState(false);
  const [display, setDisplay] = useState<Display>(DEFAULT_DISPLAY);
  const [audioPlayerId] = useState(() => Symbol("salah-audio-player"));
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const [activeAudio, setActiveAudio] = useState<string | null>(null);
  const [audioPlaying, setAudioPlaying] = useState(false);
  const [audioError, setAudioError] = useState<string | null>(null);
  const step = steps[index]!;
  const practice = display.mode === "practice";
  const isLast = index === steps.length - 1;

  // Open on the linked step, else where the visitor left off.
  useEffect(() => {
    const progress = readSalahProgress();
    const linked = stepSlugFromLocation(window.location.hash, window.location.search);
    setIndex(resumeStepIndex(lesson, progress.lessons[lesson.slug], linked));
    setCompleted(progress.lessons[lesson.slug]?.status === "completed");
    setDisplay(readDisplay());
    setReady(true);
    // The event's own URL: by the time it is dispatched, the router may already
    // have rewritten the address with the step it had recorded.
    const onHashChange = (event: HashChangeEvent) => {
      const slug = stepSlugFromLocation(new URL(event.newURL).hash, "");
      const target = steps.findIndex((item) => item.slug === slug);
      if (target >= 0) setIndex(target);
    };
    window.addEventListener("hashchange", onHashChange);
    return () => window.removeEventListener("hashchange", onHashChange);
  }, [lesson, steps]);

  // Keep the step in the address (shareable) and in local progress.
  useEffect(() => {
    if (!ready) return;
    const hash = `#${step.slug}`;
    if (window.location.hash !== hash && (index > 0 || window.location.hash)) {
      window.history.replaceState(null, "", `${window.location.pathname}${window.location.search}${hash}`);
    }
    writeSalahProgress(recordSalahStep(readSalahProgress(), lesson.slug, step.slug, courseVersion));
  }, [courseVersion, index, lesson.slug, ready, step.slug]);

  // A step change stops the clip; the next step's picture is fetched ahead.
  useEffect(() => {
    setActiveAudio(null);
    setAudioPlaying(false);
    setAudioError(null);
    const upcoming = steps[index + 1]?.media;
    const image = upcoming ? media[upcoming] : undefined;
    if (image) preload(image.url, { as: "image" });
  }, [index, media, steps]);

  useEffect(() => {
    const audio = audioRef.current;
    if (!audio || activeAudio === null) return;
    return registerAudioPlayer(audioPlayerId, () => {
      audio.pause();
      setAudioPlaying(false);
    });
  }, [activeAudio, audioPlayerId]);

  const go = useCallback((delta: number) => {
    setIndex((current) => Math.min(steps.length - 1, Math.max(0, current + delta)));
  }, [steps.length]);

  const finish = () => {
    writeSalahProgress(recordSalahStep(readSalahProgress(), lesson.slug, step.slug, courseVersion, { completed: true }));
    setCompleted(true);
  };

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.defaultPrevented || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;
      if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
      const target = event.target as HTMLElement | null;
      if (target?.closest("input, textarea, select, audio, video, [contenteditable]")) return;
      const forward = event.key === (direction === "rtl" ? "ArrowLeft" : "ArrowRight");
      event.preventDefault();
      go(forward ? 1 : -1);
    };
    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, [direction, go]);

  const updateDisplay = (patch: Partial<Display>) => {
    setDisplay((current) => {
      const next = { ...current, ...patch };
      try {
        window.localStorage.setItem(DISPLAY_STORAGE_KEY, JSON.stringify(next));
      } catch {
        // The choice still applies to this visit.
      }
      return next;
    });
  };

  const toggleAudio = (key: string) => {
    if (activeAudio !== key) {
      claimAudioFocus(audioPlayerId);
      setAudioError(null);
      setAudioPlaying(false);
      setActiveAudio(key);
      return;
    }
    const audio = audioRef.current;
    if (!audio) return;
    if (audio.paused) {
      claimAudioFocus(audioPlayerId);
      void audio.play().catch(() => setAudioError(t("salah.audioError")));
    } else {
      audio.pause();
    }
  };

  const renderFormula = (owner: SalahStep, id: string, formula: SalahFormula) => {
    const key = `${owner.slug}:${id}`;
    const active = activeAudio === key;
    const range = formula.audio ? formulaAudioRange(formula.audio) : null;
    const showTranslation = !practice && display.translation && formula.translation && formula.translation !== formula.arabic;
    return (
      <article className="salah-formula" key={id}>
        <p className="salah-arabic" lang="ar" dir="rtl">{formula.arabic}</p>
        {!practice && display.transliteration && formula.transliteration ? (
          <p className="salah-transliteration">{formula.transliteration}</p>
        ) : null}
        {showTranslation ? <p className="salah-translation">{formula.translation}</p> : null}
        <div className="salah-formula-tools">
          {formula.audio ? (
            <button
              type="button"
              className={`dua-icon-action${active ? " is-active" : ""}`}
              onClick={() => toggleAudio(key)}
              aria-label={active && audioPlaying ? t("salah.pauseAudio") : t("salah.playAudio")}
              title={active && audioPlaying ? t("salah.pauseAudio") : t("salah.playAudio")}
              aria-pressed={active && audioPlaying}
            >
              <AudioIcon playing={active && audioPlaying} />
            </button>
          ) : null}
          {formula.repetitions > 1 ? (
            <RepetitionCounter
              target={formula.repetitions}
              label={t("salah.repeatTimes", { count: formatNumber(formula.repetitions) })}
            />
          ) : null}
        </div>
        {active && formula.audio && range ? (
          <div className="dua-audio-panel salah-audio-panel">
            <audio
              ref={audioRef}
              src={formula.audio.url}
              controls
              autoPlay
              preload="none"
              controlsList="nodownload"
              onLoadedMetadata={(event) => {
                if (range.start > 0) event.currentTarget.currentTime = range.start;
              }}
              onTimeUpdate={(event) => {
                const audio = event.currentTarget;
                if (range.end !== null && audio.currentTime >= range.end) {
                  audio.pause();
                  audio.currentTime = range.start;
                }
              }}
              onPlay={() => {
                claimAudioFocus(audioPlayerId);
                setAudioPlaying(true);
              }}
              onPause={() => setAudioPlaying(false)}
              onEnded={() => setAudioPlaying(false)}
              onError={() => {
                setAudioPlaying(false);
                setAudioError(t("salah.audioError"));
              }}
            >
              {t("salah.audioUnsupported")}
            </audio>
            {audioError ? <span role="alert">{audioError}</span> : null}
          </div>
        ) : null}
      </article>
    );
  };

  const rakats = lesson.prayer?.rakats ?? 0;
  const currentRakat = step.rakat ?? 0;
  const backArrow = direction === "rtl" ? "→" : "←";
  const nextArrow = direction === "rtl" ? "←" : "→";

  return (
    <section
      className={`surface salah-player${practice ? " is-practice" : ""}`}
      aria-label={lesson.title}
      aria-busy={!ready}
      data-testid="salah-player"
    >
      <div className="salah-player-toolbar">
        <div className="salah-mode-switch" role="group" aria-label={t("salah.mode")}>
          {(["learn", "practice"] as const).map((mode) => (
            <button
              key={mode}
              type="button"
              className={`btn btn-sm ${display.mode === mode ? "btn-primary" : "btn-secondary"}`}
              aria-pressed={display.mode === mode}
              onClick={() => updateDisplay({ mode })}
            >
              {mode === "learn" ? t("salah.modeLearn") : t("salah.modePractice")}
            </button>
          ))}
        </div>
        {!practice ? (
          <div className="salah-text-toggles">
            <label>
              <input
                type="checkbox"
                checked={display.transliteration}
                onChange={(event) => updateDisplay({ transliteration: event.target.checked })}
              />
              {t("salah.showTransliteration")}
            </label>
            <label>
              <input
                type="checkbox"
                checked={display.translation}
                onChange={(event) => updateDisplay({ translation: event.target.checked })}
              />
              {t("salah.showTranslation")}
            </label>
          </div>
        ) : null}
      </div>

      <div className="salah-step-status">
        {rakats > 0 ? (
          <ol className="salah-rakats" aria-label={t("salah.rakatsAria")}>
            {Array.from({ length: rakats }, (_, offset) => offset + 1).map((rakat) => (
              <li
                key={rakat}
                className={rakat < currentRakat ? "is-done" : rakat === currentRakat ? "is-current" : undefined}
                aria-current={rakat === currentRakat ? "step" : undefined}
              >
                <span className="sr-only">{t("salah.rakat", { number: formatNumber(rakat) })}</span>
              </li>
            ))}
          </ol>
        ) : null}
        <p aria-live="polite" data-testid="salah-step-counter">
          {t("salah.stepOf", { current: formatNumber(index + 1), total: formatNumber(steps.length) })}
          {currentRakat ? ` · ${t("salah.rakat", { number: formatNumber(currentRakat) })}` : ""}
        </p>
      </div>

      <ol className="salah-steps">
        {steps.map((item, itemIndex) => {
          const image = item.media ? media[item.media] : undefined;
          const repeatTarget = stepRepeatTarget(item, formulas);
          return (
            <li key={item.slug} hidden={itemIndex !== index} className="salah-step" data-step={item.slug}>
              {image ? <StepImage media={image} eager={itemIndex === index} /> : null}
              <div className="salah-step-body">
                <div className="salah-step-head">
                  <h2>{item.title}</h2>
                  {!practice && item.ruling ? (
                    <span className={`status-chip salah-ruling is-${item.ruling}`}>{t(RULING_LABELS[item.ruling])}</span>
                  ) : null}
                </div>
                {!practice ? <p className="salah-instruction">{item.instruction}</p> : null}
                {!practice && item.details ? <p className="salah-details">{item.details}</p> : null}
                {repeatTarget ? (
                  <RepetitionCounter
                    target={repeatTarget}
                    label={t("salah.repeatTimes", { count: formatNumber(repeatTarget) })}
                  />
                ) : null}
                {item.formulas.map((id) => renderFormula(item, id, formulas[id]!))}
              </div>
            </li>
          );
        })}
      </ol>

      <div className="salah-step-nav">
        <button type="button" className="btn btn-secondary" onClick={() => go(-1)} disabled={index === 0}>
          <span aria-hidden="true">{backArrow}</span> {t("salah.previous")}
        </button>
        {isLast ? (
          <button type="button" className="btn btn-primary" onClick={finish}>
            {t("salah.finish")}
          </button>
        ) : (
          <button type="button" className="btn btn-primary" onClick={() => go(1)}>
            {t("salah.next")} <span aria-hidden="true">{nextArrow}</span>
          </button>
        )}
      </div>
      <p className="salah-keyboard-hint">{t("salah.keyboardHint")}</p>

      {completed && isLast ? (
        <div className="salah-completed" role="status">
          <strong>{t("salah.lessonCompleted")}</strong>
          <div>
            {nextLesson ? (
              <Link className="btn btn-primary" href={localizedPath(locale, `/salah/${nextLesson.slug}`)}>
                {t("salah.nextLesson", { title: nextLesson.title })}
              </Link>
            ) : null}
            <Link className="btn btn-secondary" href={localizedPath(locale, "/salah")}>
              {t("salah.allLessons")}
            </Link>
            <button type="button" className="btn btn-secondary" onClick={() => setIndex(0)}>
              {t("salah.restart")}
            </button>
          </div>
        </div>
      ) : null}
    </section>
  );
}
