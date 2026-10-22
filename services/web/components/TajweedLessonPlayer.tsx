"use client";

import Link from "next/link";
import { Fragment, useCallback, useEffect, useMemo, useState } from "react";

import { api } from "../lib/api";
import { useI18n } from "../lib/i18n-context";
import { latestRecitationsByVariant } from "../lib/reciter-catalog";
import { loadReciterPreference, preferredRecitation } from "../lib/reciter-preference";
import { localizedPath } from "../lib/routing";
import { timedPosition } from "../lib/tajweed";
import {
  FIRST_EXAMPLES,
  lessonStepSlugs,
  MORE_EXAMPLES,
  occurrenceAt,
  occurrenceRuns,
  occurrenceTiming,
  parseTajweedExamplesPage,
  readTajweedProgress,
  recordTajweedStep,
  splitFirstExamples,
  tajweedStepFromLocation,
  writeTajweedProgress,
  type TajweedCourseExample,
  type TajweedCourseLesson,
  type TajweedCourseTarget,
  type TajweedOccurrence,
} from "../lib/tajweed-course";
import { useTajweedProgressSync } from "../lib/use-tajweed-progress";
import { StepNav } from "./StepNav";
import { ClipButtons, useAyahAudio, useClipPlayer } from "./TajweedAudio";
import { colorStyle, Explanation } from "./TajweedParts";
import { useStepNavigation } from "./useStepNavigation";

type Examples =
  | { status: "loading" | "error" }
  | {
    status: "ready";
    shown: TajweedCourseExample[];
    find: TajweedCourseExample | null;
    /** The shared cursor of «More examples» and «Another ayah»; null when none are left. */
    nextOffset: number | null;
  };

type FindState = { wrong: number[]; found: number | null; revealed: boolean };
const NO_ANSWER: FindState = { wrong: [], found: null, revealed: false };
const MISSES_BEFORE_ANSWER = 2;

let courseRecitation: Promise<string | null> | null = null;

/** The reciter of the course clips: the Mushaf's, else Mishary al-Afasy, else the first one. */
function loadCourseRecitation(): Promise<string | null> {
  courseRecitation ??= api.getAllRecitations({ quran_edition: "madani-hafs" })
    .then((catalog) => {
      const available = latestRecitationsByVariant(catalog, "ayah_playback");
      const fallback = available
        .filter((item) => item.code.startsWith("qf-7-"))
        .sort((left, right) => right.coverage.surah_count - left.coverage.surah_count)[0];
      return (preferredRecitation(available, loadReciterPreference("mushaf")) || fallback || available[0])?.id ?? null;
    })
    .catch(() => {
      courseRecitation = null;
      return null;
    });
  return courseRecitation;
}

/** The course reciter, looked up once a step has something to play. */
function useCourseRecitation(needed: boolean): string | null {
  const [recitationId, setRecitationId] = useState<string | null>(null);
  useEffect(() => {
    if (!needed) return;
    let cancelled = false;
    void loadCourseRecitation().then((id) => {
      if (!cancelled) setRecitationId(id);
    });
    return () => { cancelled = true; };
  }, [needed]);
  return recitationId;
}

function Paragraphs({ text }: { text: string }) {
  return text.split(/\n{2,}/).filter(Boolean).map((paragraph, index) => <Explanation key={index} text={paragraph} />);
}

function WordText({ word, occurrence }: { word: { position: number; text: string }; occurrence: TajweedOccurrence | null }) {
  return occurrenceRuns(word, occurrence).map((run, index) => (run.code ? <mark key={index}>{run.text}</mark> : run.text));
}

/** The ayah in the Arabic font; the words of `occurrence` lit in the target colour. */
function AyahText({
  example,
  occurrence,
  color,
  reading,
  find,
}: {
  example: TajweedCourseExample;
  occurrence: TajweedOccurrence | null;
  color: string;
  reading: number | null;
  find?: { wrong: readonly number[]; onPick: (position: number) => void };
}) {
  const lit = new Set(occurrence?.parts.map((part) => part.position) ?? []);
  return (
    <p className="tajweed-course-ayah" dir="rtl" lang="ar" translate="no" data-testid="tajweed-course-ayah">
      {example.words.map((word, index) => {
        const isLit = lit.has(word.position);
        const wrong = find?.wrong.includes(word.position) ?? false;
        const className = [
          "tajweed-course-word",
          isLit ? "is-lit" : "",
          wrong ? "is-wrong" : "",
          reading === word.position ? "is-reading" : "",
        ].filter(Boolean).join(" ");
        const content = <WordText word={word} occurrence={isLit ? occurrence : null} />;
        return (
          <Fragment key={word.position}>
            {index > 0 && " "}
            {find ? (
              <button
                type="button"
                className={className}
                style={isLit ? colorStyle(color) : undefined}
                aria-pressed={isLit || wrong}
                onClick={() => find.onPick(word.position)}
                data-word-position={word.position}
              >
                {content}
              </button>
            ) : (
              <span className={className} style={isLit ? colorStyle(color) : undefined} data-word-position={word.position}>
                {content}
              </span>
            )}
          </Fragment>
        );
      })}
    </p>
  );
}

/** The words of one occurrence, large, with its letters in the target colour. */
function OccurrenceWords({ example, occurrence, color }: { example: TajweedCourseExample; occurrence: TajweedOccurrence; color: string }) {
  const positions = [...new Set(occurrence.parts.map((part) => part.position))].sort((left, right) => left - right);
  return (
    <p className="tajweed-lesson-word" dir="rtl" lang="ar" style={colorStyle(color)}>
      {positions.map((position, index) => {
        const word = example.words.find((item) => item.position === position);
        return word ? (
          <Fragment key={position}>
            {index > 0 && " "}
            <WordText word={word} occurrence={occurrence} />
          </Fragment>
        ) : null;
      })}
    </p>
  );
}

/**
 * One lesson of the tajweed course, step by step (docs/tajweed/course.md): the
 * rule, how to read it, examples from the Quran with their sound, and «find the
 * rule in the ayah». Steps, keys and the step's player are those of the ayah
 * breakdown and the prayer course.
 */
export function TajweedLessonPlayer({
  courseSlug,
  courseVersion,
  lesson,
  target,
  reviewPending,
  nextLesson,
}: {
  courseSlug: string;
  courseVersion: string;
  lesson: TajweedCourseLesson;
  target: TajweedCourseTarget;
  reviewPending: boolean;
  nextLesson: { slug: string; title: string } | null;
}) {
  const { direction, formatNumber, locale, t } = useI18n();
  const [examples, setExamples] = useState<Examples>({ status: "loading" });
  const [request, setRequest] = useState(0);
  const [loadingMore, setLoadingMore] = useState(false);
  const [answer, setAnswer] = useState<FindState>(NO_ANSWER);
  const [ready, setReady] = useState(false);
  const [pendingStep, setPendingStep] = useState<string | null>(null);
  const [completed, setCompleted] = useState(false);
  const [slow, setSlow] = useState(false);
  const [readingMs, setReadingMs] = useState<number | null>(null);
  const sync = useTajweedProgressSync(courseSlug);

  const loaded = examples.status === "ready" ? examples : null;
  const shownCount = loaded?.shown.length ?? 1;
  const hasFind = Boolean(loaded?.find);
  const steps = useMemo(() => lessonStepSlugs(shownCount, hasFind), [hasFind, shownCount]);
  const { index, setIndex, go, onKeyDown } = useStepNavigation(steps.length, direction);
  const slug = steps[index]!;
  const isLast = index === steps.length - 1;
  const exampleNumber = slug.startsWith("example-") ? Number(slug.slice(8)) : 0;
  const example = loaded && exampleNumber ? loaded.shown[exampleNumber - 1] ?? null : null;
  const findExample = loaded?.find ?? null;
  const shownOccurrence = slug === "find"
    ? (answer.found !== null ? findExample?.occurrences[answer.found] ?? null : null)
    : example?.occurrences[0] ?? null;
  const current = slug === "find" ? findExample : example;
  const recitationId = useCourseRecitation(current !== null);
  const audio = useAyahAudio(recitationId, current?.verse_key ?? "");
  const fragmentPlayer = useClipPlayer();
  const ayahPlayer = useClipPlayer(setReadingMs);
  const { stop: stopFragment } = fragmentPlayer;
  const { attach, playing: ayahPlaying, error: ayahError, play: playAyah, stop: stopAyah, setRate: setAyahRate } = ayahPlayer;
  const clipTiming = audio && shownOccurrence ? occurrenceTiming(audio.words, shownOccurrence) : null;
  const reading = readingMs === null || !audio ? null : timedPosition(audio.words, readingMs);

  // The first page: all but the last example are read, the last one is found.
  useEffect(() => {
    let cancelled = false;
    api.getTajweedLessonExamples(courseSlug, lesson.slug, 0, FIRST_EXAMPLES)
      .then((value) => {
        if (cancelled) return;
        const page = parseTajweedExamplesPage(value);
        const { shown, find } = splitFirstExamples(page.examples);
        setExamples(shown.length ? { status: "ready", shown, find, nextOffset: page.next_offset } : { status: "error" });
      })
      .catch(() => {
        if (!cancelled) setExamples({ status: "error" });
      });
    return () => { cancelled = true; };
  }, [courseSlug, lesson.slug, request]);

  // Open on the linked step, else where the visitor left off; a step that comes
  // with the examples is opened once they arrive.
  useEffect(() => {
    const saved = readTajweedProgress(courseSlug).lessons[lesson.slug];
    const linked = tajweedStepFromLocation(window.location.hash, window.location.search);
    const wanted = linked ?? (saved && saved.status !== "completed" ? saved.step_slug : null);
    setCompleted(saved?.status === "completed");
    if (wanted && wanted !== "intro") setPendingStep(wanted);
    setReady(true);
    // The event's own URL: by the time it is dispatched, the step effect may
    // already have rewritten the address.
    const onHashChange = (event: HashChangeEvent) => {
      const linkedStep = tajweedStepFromLocation(new URL(event.newURL).hash, "");
      if (linkedStep) setPendingStep(linkedStep);
    };
    window.addEventListener("hashchange", onHashChange);
    return () => window.removeEventListener("hashchange", onHashChange);
  }, [courseSlug, lesson.slug]);

  useEffect(() => {
    if (pendingStep === null || examples.status === "loading") return;
    const target = steps.indexOf(pendingStep);
    if (target >= 0) setIndex(target);
    setPendingStep(null);
  }, [examples.status, pendingStep, setIndex, steps]);

  // Keep the step in the address (shareable) and in local progress.
  useEffect(() => {
    if (!ready || pendingStep !== null) return;
    const hash = `#${slug}`;
    if (window.location.hash !== hash && (index > 0 || window.location.hash)) {
      window.history.replaceState(null, "", `${window.location.pathname}${window.location.search}${hash}`);
    }
    writeTajweedProgress(recordTajweedStep(readTajweedProgress(courseSlug), lesson.slug, slug, courseVersion), courseSlug);
  }, [courseSlug, courseVersion, index, lesson.slug, pendingStep, ready, slug]);

  // A step change, or a new ayah to find in, stops the sound; the next play starts over.
  useEffect(() => {
    stopFragment();
    stopAyah();
  }, [index, findExample, stopAyah, stopFragment]);

  useEffect(() => {
    const listener = (event: KeyboardEvent) => { onKeyDown(event); };
    document.addEventListener("keydown", listener);
    return () => document.removeEventListener("keydown", listener);
  }, [onKeyDown]);

  const fetchMore = useCallback(async (limit: number) => {
    if (!loaded || loaded.nextOffset === null) return null;
    setLoadingMore(true);
    try {
      return parseTajweedExamplesPage(
        await api.getTajweedLessonExamples(courseSlug, lesson.slug, loaded.nextOffset, limit),
      );
    } catch {
      return null;
    } finally {
      setLoadingMore(false);
    }
  }, [courseSlug, lesson.slug, loaded]);

  const showMore = async () => {
    const page = await fetchMore(MORE_EXAMPLES);
    if (!page || !loaded) return;
    const known = new Set([...loaded.shown, loaded.find].map((item) => item?.verse_key));
    const added = page.examples.filter((item) => !known.has(item.verse_key));
    setExamples({ ...loaded, shown: [...loaded.shown, ...added], nextOffset: page.next_offset });
    if (added.length) setIndex(2 + loaded.shown.length);
  };

  const anotherAyah = async () => {
    const page = await fetchMore(1);
    if (!page || !loaded) return;
    setExamples({ ...loaded, find: page.examples[0] ?? loaded.find, nextOffset: page.next_offset });
    setAnswer(NO_ANSWER);
  };

  const pick = (position: number) => {
    if (!findExample || answer.found !== null) return;
    const found = occurrenceAt(findExample, position);
    setAnswer(found >= 0
      ? { ...answer, found }
      : { ...answer, wrong: answer.wrong.includes(position) ? answer.wrong : [...answer.wrong, position] });
  };

  const finish = () => {
    writeTajweedProgress(
      recordTajweedStep(readTajweedProgress(courseSlug), lesson.slug, slug, courseVersion, { completed: true }),
      courseSlug,
    );
    setCompleted(true);
    void sync();
  };

  const stepTitle = (step: string): string => {
    if (step === "intro") return t("tajweedCourse.stepRule");
    if (step === "how") return t("tajweed.howToRead");
    if (step === "find") return t("tajweedCourse.findTitle");
    return t("tajweedCourse.exampleOf", {
      current: formatNumber(Number(step.slice(8))),
      total: formatNumber(loaded?.shown.length ?? 1),
    });
  };

  const audioTools = current && audio ? (
    <div className="tajweed-lesson-tools">
      {clipTiming && shownOccurrence ? (
        <ClipButtons
          player={fragmentPlayer}
          clip={{ url: audio.url, ...clipTiming }}
          slow={slow}
          onSlowChange={(value) => {
            setSlow(value);
            setAyahRate(value ? 0.75 : 1);
          }}
        />
      ) : null}
      <button
        type="button"
        className="btn btn-secondary btn-sm"
        onClick={() => (ayahPlaying
          ? stopAyah()
          : void playAyah({ url: audio.url, startMs: audio.startMs, endMs: audio.endMs }, slow ? 0.75 : 1))}
        data-testid="tajweed-course-play-ayah"
      >
        {ayahPlaying ? t("tajweed.stop") : t("tajweed.playAyah")}
      </button>
      {ayahError ? <p className="error-text" role="alert">{t("tajweed.audioError")}</p> : null}
    </div>
  ) : null;

  const reference = (item: TajweedCourseExample) => (
    <p className="tajweed-lesson-reference">
      {t("tajweedCourse.ayahReference", {
        surah: formatNumber(item.surah_number),
        ayah: formatNumber(item.ayah_number),
      })}
    </p>
  );

  const renderStep = (step: string, active: boolean) => {
    if (step === "intro") {
      return (
        <>
          <h2>
            <span className="tajweed-dot" style={{ background: target.color }} aria-hidden="true" />
            {target.name}
            {target.arabic_name !== target.name ? (
              <span className="tajweed-lesson-arabic-name" lang="ar" dir="rtl">{target.arabic_name}</span>
            ) : null}
          </h2>
          <Paragraphs text={lesson.explanation} />
          {lesson.letters ? (
            <>
              <h3>{t("tajweedCourse.letters")}</h3>
              <ul className="tajweed-lesson-letters" dir="rtl" lang="ar">
                {lesson.letters.split(/\s+/).filter(Boolean).map((letter, letterIndex) => (
                  <li key={letterIndex}>{letter}</li>
                ))}
              </ul>
            </>
          ) : null}
        </>
      );
    }
    if (step === "how") {
      return (
        <>
          <h2>{t("tajweed.howToRead")}</h2>
          <Paragraphs text={lesson.how} />
        </>
      );
    }
    if (step === "find") {
      if (!findExample) return null;
      const found = answer.found !== null ? findExample.occurrences[answer.found]! : null;
      const misses = answer.wrong.length;
      return (
        <>
          <h2>{t("tajweedCourse.findTitle")}</h2>
          <p>{t("tajweedCourse.findPrompt", { rule: target.name })}</p>
          <AyahText
            example={findExample}
            occurrence={found}
            color={target.color}
            reading={active ? reading : null}
            find={{ wrong: answer.wrong, onPick: pick }}
          />
          {reference(findExample)}
          <p
            className={`tajweed-lesson-feedback${found && !answer.revealed ? " is-correct" : ""}`}
            role="status"
            aria-live="polite"
            data-testid="tajweed-find-feedback"
          >
            {found
              ? t(answer.revealed ? "tajweedCourse.answerShown" : "tajweedCourse.findCorrect", { rule: target.name })
              : misses ? t("tajweedCourse.findWrong") : ""}
          </p>
          {active ? audioTools : null}
          <div className="tajweed-lesson-tools">
            {!found && misses >= MISSES_BEFORE_ANSWER ? (
              <button
                type="button"
                className="btn btn-secondary btn-sm"
                onClick={() => setAnswer({ ...answer, found: 0, revealed: true })}
              >
                {t("tajweedCourse.showAnswer")}
              </button>
            ) : null}
            {loaded?.nextOffset !== null ? (
              <button type="button" className="btn btn-secondary btn-sm" onClick={() => void anotherAyah()} disabled={loadingMore}>
                {t("tajweedCourse.anotherAyah")}
              </button>
            ) : null}
          </div>
        </>
      );
    }
    // example-N
    const heading = <h2>{stepTitle(step)}</h2>;
    if (examples.status === "loading") {
      return <>{heading}<p role="status">{t("tajweedCourse.examplesLoading")}</p></>;
    }
    if (examples.status === "error" || !loaded) {
      return (
        <>
          {heading}
          <p role="alert">{t("tajweedCourse.examplesError")}</p>
          <div>
            <button
              type="button"
              className="btn btn-secondary btn-sm"
              onClick={() => {
                setExamples({ status: "loading" });
                setRequest((value) => value + 1);
              }}
            >
              {t("tajweedCourse.retry")}
            </button>
          </div>
        </>
      );
    }
    const item = loaded.shown[Number(step.slice(8)) - 1];
    if (!item) return heading;
    const occurrence = item.occurrences[0]!;
    const lastExample = Number(step.slice(8)) === loaded.shown.length;
    return (
      <>
        {heading}
        <AyahText example={item} occurrence={occurrence} color={target.color} reading={active ? reading : null} />
        {reference(item)}
        <OccurrenceWords example={item} occurrence={occurrence} color={target.color} />
        {active ? audioTools : null}
        {lastExample && loaded.nextOffset !== null ? (
          <div>
            <button type="button" className="btn btn-secondary btn-sm" onClick={() => void showMore()} disabled={loadingMore}>
              {t("tajweedCourse.moreExamples")}
            </button>
          </div>
        ) : null}
      </>
    );
  };

  return (
    <section className="surface tajweed-lesson" aria-label={lesson.title} aria-busy={!ready} data-testid="tajweed-lesson">
      <div className="tajweed-lesson-status">
        <p aria-live="polite" data-testid="tajweed-lesson-counter">
          {t("tajweedCourse.stepOf", { current: formatNumber(index + 1), total: formatNumber(steps.length) })}
          <span className="sr-only">: {stepTitle(slug)}</span>
        </p>
        <span className="tajweed-breakdown-progress" aria-hidden="true">
          <span style={{ inlineSize: `${((index + 1) / steps.length) * 100}%` }} />
        </span>
      </div>

      <ol className="tajweed-lesson-steps">
        {steps.map((step, stepIndex) => (
          <li key={step} hidden={stepIndex !== index} className="tajweed-lesson-step" data-step={step}>
            {renderStep(step, stepIndex === index)}
          </li>
        ))}
      </ol>
      {current && audio ? <audio ref={attach} preload="none" onEnded={stopAyah} /> : null}

      <StepNav
        className="tajweed-lesson-nav"
        backLabel={t("tajweedCourse.previous")}
        nextLabel={isLast ? t("tajweedCourse.finish") : t("tajweedCourse.next")}
        onBack={() => go(-1)}
        onNext={isLast ? finish : () => go(1)}
        isFirst={index === 0}
        isLast={isLast}
      />
      <p className="tajweed-keyboard-hint">{t("tajweed.keyboardHint")}</p>

      {completed && isLast ? (
        <div className="tajweed-lesson-completed" role="status">
          <strong>{t("tajweedCourse.lessonCompleted")}</strong>
          <div>
            {nextLesson ? (
              <Link className="btn btn-primary" href={localizedPath(locale, `/tajweed/${nextLesson.slug}`)}>
                {t("tajweedCourse.nextLesson", { title: nextLesson.title })}
              </Link>
            ) : null}
            <Link className="btn btn-secondary" href={localizedPath(locale, "/tajweed")}>
              {t("tajweedCourse.allLessons")}
            </Link>
            <button type="button" className="btn btn-secondary" onClick={() => setIndex(0)}>
              {t("tajweedCourse.restart")}
            </button>
          </div>
        </div>
      ) : null}

      {reviewPending ? <p className="tajweed-review-note">{t("tajweed.reviewNote")}</p> : null}
    </section>
  );
}
