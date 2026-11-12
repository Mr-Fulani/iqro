"use client";

import Link from "next/link";
import { lazy, Suspense, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { preload } from "react-dom";

import { claimAudioFocus, registerAudioPlayer } from "../lib/audio-focus";
import { useI18n } from "../lib/i18n-context";
import type { MessageKey } from "../lib/i18n";
import { localizedPath } from "../lib/routing";
import {
  formulaAudioRange,
  isSalahRuling,
  lessonHasPractice,
  readSalahProgress,
  recordSalahStep,
  resumeStepIndex,
  SALAH_COURSE_SLUG,
  salahQuranAyahs,
  type SalahFormula,
  type SalahFormulaAudio,
  type SalahLessonBundle,
  type SalahMedia,
  type SalahRuling,
  type SalahStep,
  stepRepeatTarget,
  stepSlugFromLocation,
  writeSalahProgress,
} from "../lib/salah";
import { salahStepScenes } from "../lib/salah-3d";
import { trackEvent } from "../lib/analytics";
import { trackCourseEvent } from "../lib/course-feedback";
import { useSalahProgressSync } from "../lib/use-salah-progress";
import { useLessonOpened } from "./courses/useLessonOpened";
import { type Salah3D, useSalah3D } from "./SalahStep3D";
import { SalahQuranText } from "./SalahQuranText";
import { SalahStepNotes } from "./SalahStepNotes";
import { StepNav } from "./StepNav";
import { useStepNavigation } from "./useStepNavigation";

// The script of the selected Mushaf for the ayahs: its own chunk, fetched once the page has
// loaded, so the lesson's first paint carries none of it.
const SalahQuranScript = lazy(() => import("./SalahQuranScript"));

type Mode = "learn" | "practice";
type Display = { mode: Mode; transliteration: boolean; translation: boolean };

const DISPLAY_STORAGE_KEY = "iqro_salah_display_v1";
const DEFAULT_DISPLAY: Display = { mode: "learn", transliteration: true, translation: true };
const RULING_LABELS: Record<SalahRuling, MessageKey> = {
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

function ReplayIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path
        d="M12 5V1L7 6l5 5V7c3.31 0 6 2.69 6 6s-2.69 6-6 6-6-2.69-6-6H4c0 4.42 3.58 8 8 8s8-3.58 8-8-3.58-8-8-8Z"
        fill="currentColor"
      />
    </svg>
  );
}

function CameraIcon({ path }: { path: string }) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d={path} fill="currentColor" />
    </svg>
  );
}

const TURN_LEFT_ICON =
  "M7.11 8.53 5.7 7.11C4.8 8.27 4.24 9.61 4.07 11h2.02c.14-.87.49-1.72 1.02-2.47ZM6.09 13H4.07c.17 1.39.72 2.73 1.62 3.89l1.41-1.42c-.52-.75-.87-1.59-1.01-2.47Zm1.01 5.32c1.16.9 2.51 1.44 3.9 1.61V17.9c-.87-.15-1.71-.49-2.46-1.03L7.1 18.32ZM13 4.07V1L8.45 5.55 13 10V6.09c2.84.48 5 2.94 5 5.91s-2.16 5.43-5 5.91v2.02c3.95-.49 7-3.85 7-7.93s-3.05-7.44-7-7.93Z";
const TURN_RIGHT_ICON =
  "M15.55 5.55 11 1v3.07C7.06 4.56 4 7.92 4 12s3.05 7.44 7 7.93v-2.02c-2.84-.48-5-2.94-5-5.91s2.16-5.43 5-5.91V10l4.55-4.45ZM19.93 11c-.17-1.39-.72-2.73-1.62-3.89l-1.42 1.42c.54.75.88 1.6 1.02 2.47h2.02ZM13 17.9v2.02c1.39-.17 2.74-.71 3.9-1.61l-1.44-1.44c-.75.54-1.59.89-2.46 1.03Zm3.89-2.42 1.42 1.41c.9-1.16 1.45-2.5 1.62-3.89h-2.02c-.14.87-.48 1.72-1.02 2.48Z";
const RESET_VIEW_ICON =
  "M12 8c-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4-1.79-4-4-4Zm-7 7H3v4c0 1.1.9 2 2 2h4v-2H5v-4ZM5 5h4V3H5c-1.1 0-2 .9-2 2v4h2V5Zm14-2h-4v2h4v4h2V5c0-1.1-.9-2-2-2Zm0 16h-4v2h4c1.1 0 2-.9 2-2v-4h-2v4Z";

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

/**
 * The step's picture. A still of the 3D scene says it is schematic and, once the scene
 * runs on the current step, carries it over the still with its tools.
 */
function StepVisual({
  media,
  eager,
  still,
  three,
  slot,
}: {
  media: SalahMedia;
  eager: boolean;
  still: boolean;
  three: Omit<Salah3D, "slot" | "stage"> | null;
  slot?: Salah3D["slot"];
}) {
  const { formatNumber, t } = useI18n();
  // Pause while the pose moves, play when paused, replay once it has played.
  const motion = three?.ended ? t("salah.replay3d") : three?.playing ? t("salah.pause3d") : t("salah.play3d");
  return (
    <figure className="salah-step-visual">
      <div className="salah-step-frame">
        <StepImage media={media} eager={eager} />
        {three?.shown ? <div className="salah-3d-slot" ref={slot} data-testid="salah-3d" /> : null}
      </div>
      {still ? (
        <figcaption className="salah-3d-caption">
          <span>{t("salah.schematic3d")}</span>
          {three?.shown && three.ready ? (
            <span className="salah-3d-tools">
              {(
                [
                  ["salah.turnLeft3d", TURN_LEFT_ICON, () => three.turn(-1)],
                  ["salah.turnRight3d", TURN_RIGHT_ICON, () => three.turn(1)],
                  ["salah.resetView3d", RESET_VIEW_ICON, three.resetCamera],
                ] as const
              ).map(([label, icon, action]) => (
                <button
                  key={label}
                  type="button"
                  className="dua-icon-action"
                  onClick={action}
                  aria-label={t(label)}
                  title={t(label)}
                >
                  <CameraIcon path={icon} />
                </button>
              ))}
              <button
                type="button"
                className="dua-icon-action"
                onClick={three.togglePlaying}
                aria-label={motion}
                title={motion}
              >
                {three.ended ? <ReplayIcon /> : <AudioIcon playing={three.playing} />}
              </button>
              <button
                type="button"
                className="btn btn-sm btn-secondary salah-3d-speed"
                onClick={three.cycleSpeed}
                aria-label={t("salah.speed3d", { speed: `${formatNumber(three.speed)}×` })}
              >
                {formatNumber(three.speed)}×
              </button>
            </span>
          ) : null}
        </figcaption>
      ) : null}
    </figure>
  );
}

export function SalahStepPlayer({
  bundle,
  nextLesson,
  media: lessonMedia,
  sources,
}: {
  bundle: SalahLessonBundle;
  nextLesson: { slug: string; title: string } | null;
  /** The lesson's video, slides and banners (LessonMedia), drawn on the server; on the first step. */
  media?: ReactNode;
  /** The lesson's «Sources» (CourseLessonSources), drawn on the server; at the end of the last step. */
  sources?: ReactNode;
}) {
  const { direction, formatNumber, locale, t } = useI18n();
  const { lesson, formulas, media, courseVersion } = bundle;
  // The ayahs of each formula of the Quran, split once: its steps draw them an ayah to a line.
  const quranAyahs = useMemo(
    () => Object.fromEntries(Object.entries(formulas).map(([id, formula]) => [id, salahQuranAyahs(formula)])),
    [formulas],
  );
  const steps = lesson.steps;
  const { index, setIndex, go, onKeyDown } = useStepNavigation(steps.length, direction);
  const [ready, setReady] = useState(false);
  const [completed, setCompleted] = useState(false);
  const syncProgress = useSalahProgressSync();
  const [display, setDisplay] = useState<Display>(DEFAULT_DISPLAY);
  const [audioPlayerId] = useState(() => Symbol("salah-audio-player"));
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const [activeAudio, setActiveAudio] = useState<string | null>(null);
  const [audioPlaying, setAudioPlaying] = useState(false);
  const [audioError, setAudioError] = useState<string | null>(null);
  const [formulaFont, setFormulaFont] = useState(false);
  const step = steps[index]!;
  const scenes = useMemo(() => salahStepScenes(steps, media), [media, steps]);
  const three = useSalah3D(scenes[index] ?? null, scenes.some(Boolean), index);
  // A lesson that is only text («What is salah») has nothing to practise: no switch, always «Learn».
  const hasPractice = useMemo(() => lessonHasPractice(lesson, media), [lesson, media]);
  const practice = hasPractice && display.mode === "practice";
  const isLast = index === steps.length - 1;
  const section = useRef<HTMLElement>(null);
  useLessonOpened(SALAH_COURSE_SLUG, lesson.slug);

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
  }, [lesson, setIndex, steps]);

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

  // The lesson video stays on the hidden first step; leaving the step pauses it too.
  useEffect(() => {
    section.current?.querySelectorAll("video").forEach((video) => video.pause());
  }, [index]);

  useEffect(() => {
    const audio = audioRef.current;
    if (!audio || activeAudio === null) return;
    const unregister = registerAudioPlayer(audioPlayerId, () => {
      audio.pause();
      setAudioPlaying(false);
    });
    // Another step, formula or page stops the clip; coming back plays it from its start.
    return () => {
      unregister();
      audio.pause();
    };
  }, [activeAudio, audioPlayerId]);

  // Hiding the page stops the clip as well, as going to the background does in the app.
  useEffect(() => {
    const stop = () => {
      if (!document.hidden) return;
      setActiveAudio(null);
      setAudioPlaying(false);
    };
    document.addEventListener("visibilitychange", stop);
    return () => document.removeEventListener("visibilitychange", stop);
  }, []);

  // The formulas' font comes after the page has loaded (salah.css, .has-formula-font).
  useEffect(() => {
    const loaded = () => setFormulaFont(true);
    if (document.readyState === "complete") {
      loaded();
      return;
    }
    window.addEventListener("load", loaded, { once: true });
    return () => window.removeEventListener("load", loaded);
  }, []);

  const finish = () => {
    const progress = readSalahProgress();
    // Counted when the lesson is not yet completed on this device, as in a thematic course.
    if (progress.lessons[lesson.slug]?.status !== "completed") {
      trackCourseEvent({ course: SALAH_COURSE_SLUG, lesson: lesson.slug, event: "lesson_completed" });
    }
    writeSalahProgress(recordSalahStep(progress, lesson.slug, step.slug, courseVersion, { completed: true }));
    setCompleted(true);
    trackEvent("lesson_complete", { course: "salah", lesson: lesson.slug });
    void syncProgress();
  };

  useEffect(() => {
    const listener = (event: KeyboardEvent) => { onKeyDown(event); };
    document.addEventListener("keydown", listener);
    return () => document.removeEventListener("keydown", listener);
  }, [onKeyDown]);

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

  // One clip plays at a time: a formula's or the step's own voice-over.
  const audioPanel = (clip: SalahFormulaAudio, range: { start: number; end: number | null }) => (
    <div className="dua-audio-panel salah-audio-panel">
      <audio
        ref={audioRef}
        src={clip.url}
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
  );

  const renderStepAudio = (owner: SalahStep, audio: SalahFormulaAudio) => {
    const key = `${owner.slug}:step`;
    const active = activeAudio === key;
    return (
      <div className="salah-step-audio">
        <div className="salah-formula-tools">
          <button
            type="button"
            className={`dua-icon-action${active ? " is-active" : ""}`}
            onClick={() => toggleAudio(key)}
            aria-label={`${t("salah.stepAudio")}: ${active && audioPlaying ? t("salah.pauseAudio") : t("salah.playAudio")}`}
            title={active && audioPlaying ? t("salah.pauseAudio") : t("salah.playAudio")}
            aria-pressed={active && audioPlaying}
            data-testid="salah-step-audio"
          >
            <AudioIcon playing={active && audioPlaying} />
          </button>
          <span>{t("salah.stepAudio")}</span>
        </div>
        {active ? audioPanel(audio, formulaAudioRange(audio)) : null}
      </div>
    );
  };

  const renderFormula = (owner: SalahStep, id: string, formula: SalahFormula, near: boolean) => {
    const ayahs = quranAyahs[id];
    const key = `${owner.slug}:${id}`;
    const active = activeAudio === key;
    const range = formula.audio ? formulaAudioRange(formula.audio) : null;
    const showTranslation = !practice && display.translation && formula.translation && formula.translation !== formula.arabic;
    return (
      <article className="salah-formula" key={id}>
        {ayahs && formula.source.kind === "quran" ? (
          formulaFont ? (
            <Suspense fallback={<SalahQuranText ayahs={ayahs} />}>
              <SalahQuranScript surah={formula.source.surah} ayahs={ayahs} near={near} />
            </Suspense>
          ) : <SalahQuranText ayahs={ayahs} />
        ) : <p className="salah-arabic" lang="ar" dir="rtl">{formula.arabic}</p>}
        {!practice && display.transliteration && formula.transliteration ? (
          <p className="salah-transliteration">{formula.transliteration}</p>
        ) : null}
        {showTranslation ? <p className="salah-translation">{formula.translation}</p> : null}
        {!practice && formula.caption ? <p className="salah-formula-caption">{formula.caption}</p> : null}
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
        {active && formula.audio && range ? audioPanel(formula.audio, range) : null}
      </article>
    );
  };

  const rakats = lesson.prayer?.rakats ?? 0;
  const currentRakat = step.rakat ?? 0;

  return (
    <section
      ref={section}
      className={`surface salah-player${practice ? " is-practice" : ""}${formulaFont ? " has-formula-font" : ""}`}
      aria-label={lesson.title}
      aria-busy={!ready}
      data-testid="salah-player"
    >
      <div className="salah-player-toolbar">
        {hasPractice ? (
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
        ) : null}
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
              {/* The lesson's media open its first step, as in the app; practice is the prayer alone. */}
              {itemIndex === 0 && !practice && lessonMedia ? <div className="salah-lesson-media">{lessonMedia}</div> : null}
              {image ? (
                <StepVisual
                  media={image}
                  eager={itemIndex === index}
                  still={scenes[itemIndex] !== null}
                  three={itemIndex === index ? three : null}
                  slot={three.slot}
                />
              ) : null}
              <div className="salah-step-body">
                <div className="salah-step-head">
                  <h2>{item.title}</h2>
                  {!practice && isSalahRuling(item.ruling) ? (
                    <span className={`status-chip salah-ruling is-${item.ruling}`}>{t(RULING_LABELS[item.ruling])}</span>
                  ) : null}
                  {!practice && item.notes?.length ? (
                    <SalahStepNotes notes={item.notes} active={itemIndex === index} />
                  ) : null}
                </div>
                {!practice ? <p className="salah-instruction">{item.instruction}</p> : null}
                {!practice && item.details ? <p className="salah-details">{item.details}</p> : null}
                {item.audio ? renderStepAudio(item, item.audio) : null}
                {repeatTarget ? (
                  <RepetitionCounter
                    target={repeatTarget}
                    label={t("salah.repeatTimes", { count: formatNumber(repeatTarget) })}
                  />
                ) : null}
                {item.formulas.map((id) => renderFormula(item, id, formulas[id]!, itemIndex === index || itemIndex === index + 1))}
                {/* As in the app: the lesson's end, in learning only, like the instruction. */}
                {itemIndex === steps.length - 1 && !practice ? sources : null}
              </div>
            </li>
          );
        })}
      </ol>
      {three.stage}

      <StepNav
        className="salah-step-nav"
        backLabel={t("salah.previous")}
        nextLabel={isLast ? t("salah.finish") : t("salah.next")}
        onBack={() => go(-1)}
        onNext={isLast ? finish : () => go(1)}
        isFirst={index === 0}
        isLast={isLast}
      />
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
