"use client";

import Link from "next/link";
import { Fragment, useEffect, useMemo, useState } from "react";

import { api } from "../lib/api";
import { useI18n } from "../lib/i18n-context";
import { localizedPath } from "../lib/routing";
import {
  occurrenceAt,
  occurrenceRuns,
  occurrenceTiming,
  type TajweedCourseExample,
  type TajweedCourseTarget,
  type TajweedOccurrence,
} from "../lib/tajweed-course";
import {
  dueReviewKeys,
  emptyPracticeState,
  localDate,
  parsePracticeTasks,
  PRACTICE_TASKS,
  recordPracticeSession,
  shownStreak,
  type PracticeAnswer,
  type PracticeTask,
  type PracticeTaskType,
} from "../lib/tajweed-practice";
import { useCourseRecitationState } from "../lib/use-course-recitation";
import { readPracticeStore, usePracticeStore, useTajweedPracticeSync, writePracticeStore } from "../lib/use-tajweed-practice";
import { useTajweedProgress } from "../lib/use-tajweed-progress";
import { StepNav } from "./StepNav";
import { ClipButtons, loadAyahAudio, useClipPlayer, type AyahAudio } from "./TajweedAudio";
import { colorStyle } from "./TajweedParts";
import { useStepNavigation } from "./useStepNavigation";

export type PracticeLesson = { slug: string; title: string; target: string };

type Given = { correct: boolean; picked: number | string; answer: PracticeAnswer };
type Phase = "start" | "loading" | "error" | "session" | "summary";

/** The ayah's audio and whether its lookup is over (a null audio then means there is none). */
function useAyahAudioState(recitationId: string | null, verseKey: string | null) {
  const key = recitationId && verseKey ? `${recitationId}|${verseKey}` : "";
  const [state, setState] = useState<{ key: string; audio: AyahAudio | null }>({ key: "", audio: null });
  useEffect(() => {
    if (!recitationId || !verseKey) return;
    let cancelled = false;
    void loadAyahAudio(recitationId, verseKey).then((audio) => {
      if (!cancelled) setState({ key: `${recitationId}|${verseKey}`, audio });
    });
    return () => { cancelled = true; };
  }, [recitationId, verseKey]);
  return { done: key !== "" && state.key === key, audio: state.key === key ? state.audio : null };
}

function WordText({ word, occurrence }: { word: { position: number; text: string }; occurrence: TajweedOccurrence | null }) {
  return occurrenceRuns(word, occurrence).map((run, index) => (run.code ? <mark key={index}>{run.text}</mark> : run.text));
}

/** The ayah of a task; `lit` is shown in `color`, a wrong pick is marked. */
function TaskAyah({
  example,
  lit,
  color,
  wrong,
  onPick,
}: {
  example: TajweedCourseExample;
  lit: TajweedOccurrence | null;
  color: string;
  wrong: number | null;
  onPick?: (position: number) => void;
}) {
  const positions = new Set(lit?.parts.map((part) => part.position) ?? []);
  return (
    <p className="tajweed-course-ayah" dir="rtl" lang="ar" translate="no" data-testid="tajweed-practice-ayah">
      {example.words.map((word, index) => {
        const isLit = positions.has(word.position);
        const className = ["tajweed-course-word", isLit ? "is-lit" : "", wrong === word.position ? "is-wrong" : ""]
          .filter(Boolean).join(" ");
        const content = <WordText word={word} occurrence={isLit ? lit : null} />;
        return (
          <Fragment key={word.position}>
            {index > 0 && " "}
            {onPick ? (
              <button
                type="button"
                className={className}
                style={isLit ? colorStyle(color) : undefined}
                aria-pressed={isLit || wrong === word.position}
                onClick={() => onPick(word.position)}
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

/**
 * Practice of the tajweed course (docs/tajweed/practice.md): tasks on the
 * rules of passed lessons from the whole Quran, one per step as in a lesson,
 * then the score, the day streak and what comes back for review.
 */
export function TajweedPractice({
  courseSlug,
  lessons,
  targets,
}: {
  courseSlug: string;
  lessons: PracticeLesson[];
  targets: Record<string, TajweedCourseTarget>;
}) {
  const { direction, formatNumber, locale, t } = useI18n();
  const progress = useTajweedProgress(courseSlug);
  const store = usePracticeStore(courseSlug);
  const sync = useTajweedPracticeSync(courseSlug);
  const [phase, setPhase] = useState<Phase>("start");
  const [tasks, setTasks] = useState<PracticeTask[]>([]);
  const [given, setGiven] = useState<Record<number, Given>>({});
  const [result, setResult] = useState<{ correct: number; total: number } | null>(null);
  const [slow, setSlow] = useState(false);
  // Due reviews are counted on the start and summary screens, at the moment they open.
  const [now, setNow] = useState(() => new Date());
  const { index, setIndex, go, onKeyDown } = useStepNavigation(Math.max(1, tasks.length), direction);

  const passed = useMemo(
    () => lessons.filter((lesson) => progress?.lessons[lesson.slug]?.status === "completed"),
    [lessons, progress],
  );
  const state = store?.state ?? emptyPracticeState();
  const due = dueReviewKeys(state, now, Number.MAX_SAFE_INTEGER).length;
  const task = phase === "session" ? tasks[index] ?? null : null;
  const answer = task ? given[index] : undefined;
  const recitation = useCourseRecitationState(task !== null);
  const sound = useAyahAudioState(recitation.id, task?.example.verse_key ?? null);
  const focus = task ? task.example.occurrences[task.focus] ?? null : null;
  // After a «find» answer the place shown and played is the one tapped (else the first).
  const tapped = task?.type === "find" && answer && typeof answer.picked === "number"
    ? task.example.occurrences[Math.max(0, occurrenceAt(task.example, answer.picked))] ?? null
    : null;
  const played = tapped ?? focus;
  const timing = sound.audio && played ? occurrenceTiming(sound.audio.words, played) : null;
  // Without the reciter's timings there is nothing to listen to: the task is asked as «which rule».
  const silent = recitation.settled && (!recitation.id || (sound.done && !timing));
  const type: PracticeTaskType | null = task ? (task.type === "listen" && silent ? "identify" : task.type) : null;
  const target = task ? targets[task.target] : undefined;
  const player = useClipPlayer();
  const { stop } = player;

  useEffect(() => {
    stop();
  }, [index, phase, stop]);

  useEffect(() => {
    if (phase !== "session") return;
    const listener = (event: KeyboardEvent) => { onKeyDown(event); };
    document.addEventListener("keydown", listener);
    return () => document.removeEventListener("keydown", listener);
  }, [onKeyDown, phase]);

  const start = async () => {
    setPhase("loading");
    setGiven({});
    setResult(null);
    try {
      const page = await api.getTajweedPractice(courseSlug, {
        lessons: passed.map((lesson) => lesson.slug),
        count: PRACTICE_TASKS,
        seed: Math.floor(Math.random() * 2 ** 31),
        review: dueReviewKeys(readPracticeStore(courseSlug).state, new Date()),
      });
      const received = parsePracticeTasks(page).filter((item) => targets[item.target]);
      if (!received.length) throw new Error("no tasks");
      setTasks(received);
      setIndex(0);
      setPhase("session");
    } catch {
      setPhase("error");
    }
  };

  const give = (picked: number | string, correct: boolean) => {
    if (!task || !type || answer) return;
    const key = `${type}~${task.example.verse_key}~${task.target}`;
    setGiven({
      ...given,
      [index]: {
        correct,
        picked,
        answer: { key, target: task.target, type, correct, at: new Date().toISOString() },
      },
    });
  };

  const finish = () => {
    const answers = tasks.map((_, taskIndex) => given[taskIndex]?.answer).filter((item): item is PracticeAnswer => Boolean(item));
    if (answers.length) {
      const finished = new Date();
      writePracticeStore(recordPracticeSession(readPracticeStore(courseSlug), {
        id: crypto.randomUUID(),
        course: courseSlug,
        local_date: localDate(finished),
        finished_at: finished.toISOString(),
        answers,
      }), courseSlug);
      void sync();
    }
    setResult({ correct: answers.filter((item) => item.correct).length, total: answers.length });
    setNow(new Date());
    setPhase("summary");
  };

  const stats = (
    <dl className="tajweed-practice-stats" data-testid="tajweed-practice-stats">
      <div>
        <dt>{t("tajweedPractice.score")}</dt>
        <dd>{formatNumber(state.score)}</dd>
      </div>
      <div>
        <dt>{t("tajweedPractice.streak")}</dt>
        <dd>{t("tajweedPractice.streakDays", { count: formatNumber(shownStreak(state, localDate(now))) })}</dd>
      </div>
      <div>
        <dt>{t("tajweedPractice.reviewBadge")}</dt>
        <dd>{formatNumber(due)}</dd>
      </div>
    </dl>
  );

  if (phase === "start" || phase === "loading" || phase === "error" || phase === "summary") {
    return (
      <section className="surface tajweed-practice" aria-busy={store === null || phase === "loading"} data-testid="tajweed-practice">
        {phase === "summary" && result ? (
          <p className="tajweed-practice-result" role="status">
            {t("tajweedPractice.summary", { correct: formatNumber(result.correct), total: formatNumber(result.total) })}
          </p>
        ) : null}
        {stats}
        {passed.length ? (
          <>
            <h2>{t("tajweedPractice.learned")}</h2>
            <ul className="tajweed-practice-rules">
              {passed.map((lesson) => {
                const item = targets[lesson.target];
                return item ? (
                  <li key={lesson.slug}>
                    <span className="tajweed-dot" style={{ background: item.color }} aria-hidden="true" />
                    {item.name}
                  </li>
                ) : null;
              })}
            </ul>
            {phase === "error" ? <p role="alert">{t("tajweedPractice.error")}</p> : null}
            {phase === "loading" ? <p role="status">{t("tajweedPractice.loading")}</p> : null}
            <div className="tajweed-practice-actions">
              <button type="button" className="btn btn-primary" onClick={() => void start()} disabled={phase === "loading"}>
                {phase === "summary" ? t("tajweedPractice.again") : t("tajweedPractice.start")}
              </button>
              <Link className="btn btn-secondary" href={localizedPath(locale, "/tajweed")}>{t("tajweedPractice.toCourse")}</Link>
            </div>
          </>
        ) : (
          <>
            <p>{t("tajweedPractice.noLessons")}</p>
            <div className="tajweed-practice-actions">
              <Link className="btn btn-primary" href={localizedPath(locale, "/tajweed")}>{t("tajweedPractice.toCourse")}</Link>
            </div>
          </>
        )}
      </section>
    );
  }

  if (!task || !type || !target) return null;
  const isLast = index === tasks.length - 1;
  const name = target.name;
  const answered = Boolean(answer);
  const shown = type === "find" ? tapped : focus;
  const showAyah = type !== "listen" || answered;

  return (
    <section className="surface tajweed-practice tajweed-lesson" aria-label={t("tajweedPractice.title")} data-testid="tajweed-practice">
      <div className="tajweed-lesson-status">
        <p aria-live="polite" data-testid="tajweed-practice-counter">
          {t("tajweedPractice.taskOf", { current: formatNumber(index + 1), total: formatNumber(tasks.length) })}
          {task.review ? <span className="status-chip tajweed-practice-review">{t("tajweedPractice.reviewBadge")}</span> : null}
        </p>
        <span className="tajweed-breakdown-progress" aria-hidden="true">
          <span style={{ inlineSize: `${((index + 1) / tasks.length) * 100}%` }} />
        </span>
      </div>

      <div className="tajweed-lesson-step" data-task={type} data-testid="tajweed-practice-task">
        <h2>
          {type === "find"
            ? t("tajweedPractice.findPrompt", { rule: name })
            : type === "identify" ? t("tajweedPractice.identifyPrompt") : t("tajweedPractice.listenPrompt")}
        </h2>
        {type === "listen" && !answered ? (
          sound.audio && timing
            ? <ClipButtons player={player} clip={{ url: sound.audio.url, ...timing }} slow={slow} onSlowChange={setSlow} />
            : <p role="status">{t("tajweedPractice.loading")}</p>
        ) : null}
        {showAyah ? (
          <TaskAyah
            example={task.example}
            lit={shown}
            // Before the answer the place is marked in the accent colour: the rule's own would tell it.
            color={answered ? target.color : "var(--primary)"}
            wrong={type === "find" && answer && !answer.correct && typeof answer.picked === "number" ? answer.picked : null}
            onPick={type === "find" ? (position) => give(position, occurrenceAt(task.example, position) >= 0) : undefined}
          />
        ) : null}
        {type !== "find" ? (
          <div className="tajweed-practice-options" role="group" aria-label={t("tajweedPractice.options")}>
            {task.options.map((option) => {
              const optionTarget = targets[option];
              if (!optionTarget) return null;
              const chosen = answer?.picked === option;
              const mark = answered ? (option === task.target ? " is-correct" : chosen ? " is-wrong" : "") : "";
              return (
                <button
                  key={option}
                  type="button"
                  className={`btn btn-secondary tajweed-practice-option${mark}`}
                  aria-pressed={chosen}
                  onClick={() => give(option, option === task.target)}
                  data-option={option}
                >
                  {optionTarget.name}
                </button>
              );
            })}
          </div>
        ) : null}
        <p
          className={`tajweed-lesson-feedback${answer?.correct ? " is-correct" : ""}`}
          role="status"
          aria-live="polite"
          data-testid="tajweed-practice-feedback"
        >
          {answer ? (answer.correct ? t("tajweedPractice.correct") : t("tajweedPractice.wrong", { rule: name })) : ""}
        </p>
        {answered && sound.audio && timing ? (
          <ClipButtons player={player} clip={{ url: sound.audio.url, ...timing }} slow={slow} onSlowChange={setSlow} />
        ) : null}
      </div>

      <StepNav
        className="tajweed-lesson-nav"
        backLabel={t("tajweedPractice.previous")}
        nextLabel={isLast ? t("tajweedPractice.finish") : t("tajweedPractice.next")}
        onBack={() => go(-1)}
        onNext={isLast ? finish : () => go(1)}
        isFirst={index === 0}
        isLast={isLast}
      />
    </section>
  );
}
