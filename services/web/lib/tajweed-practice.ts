// Tajweed practice (docs/tajweed/practice.md): the tasks the API builds from the
// markup of the whole Quran, and the score, day streak and review list kept
// locally and recomputed by the backend from the same sessions.

import { parseTajweedExamplesPage, type TajweedCourseExample } from "./tajweed-course.ts";

export const PRACTICE_TASKS = 8;
export const PRACTICE_REVIEW = 4;
export const PRACTICE_PENDING = 50;
export const TAJWEED_PRACTICE_EVENT = "iqro:tajweed-practice";
const REVIEW_DAYS: Record<number, number> = { 2: 1, 3: 3 };
const LAST_BOX = 3;
const DAY_MS = 86_400_000;

export type PracticeTaskType = "find" | "identify" | "listen";

export type PracticeTask = {
  key: string;
  type: PracticeTaskType;
  target: string;
  review: boolean;
  example: TajweedCourseExample;
  focus: number;
  options: string[];
};

export type PracticeAnswer = { key: string; target: string; type: PracticeTaskType; correct: boolean; at: string };

export type PracticeSession = {
  id: string;
  course: string;
  local_date: string;
  finished_at: string;
  answers: PracticeAnswer[];
};

export type ReviewItem = { key: string; target: string; type: PracticeTaskType; box: number; due_at: string };

export type PracticeState = {
  sessions: number;
  answers: number;
  correct: number;
  score: number;
  streak: { current: number; best: number; last_date: string | null };
  review: ReviewItem[];
};

export type PracticeStore = { state: PracticeState; pending: PracticeSession[] };

export function emptyPracticeState(): PracticeState {
  return { sessions: 0, answers: 0, correct: 0, score: 0, streak: { current: 0, best: 0, last_date: null }, review: [] };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

const TYPES = new Set<string>(["find", "identify", "listen"]);

function isTaskType(value: unknown): value is PracticeTaskType {
  return typeof value === "string" && TYPES.has(value);
}

/** `YYYY-MM-DD` of a moment in the visitor's own time zone. */
export function localDate(moment: Date): string {
  const pad = (value: number) => String(value).padStart(2, "0");
  return `${moment.getFullYear()}-${pad(moment.getMonth() + 1)}-${pad(moment.getDate())}`;
}

function nextDay(day: string): string {
  return new Date(Date.parse(`${day}T00:00:00Z`) + DAY_MS).toISOString().slice(0, 10);
}

/** The state after one more session; the backend's `apply_session`, step for step. */
export function applyPracticeSession(state: PracticeState, session: PracticeSession): PracticeState {
  const streak = { ...state.streak };
  if (streak.last_date === null || session.local_date > streak.last_date) {
    streak.current = streak.last_date !== null && session.local_date === nextDay(streak.last_date) ? streak.current + 1 : 1;
    streak.best = Math.max(streak.best, streak.current);
    streak.last_date = session.local_date;
  }
  const review = new Map(state.review.map((item) => [item.key, item]));
  let { answers, correct } = state;
  for (const answer of session.answers) {
    answers += 1;
    if (!answer.correct) {
      review.set(answer.key, {
        key: answer.key,
        target: answer.target,
        type: answer.type,
        box: 1,
        due_at: new Date(answer.at).toISOString(),
      });
      continue;
    }
    correct += 1;
    const item = review.get(answer.key);
    if (!item) continue;
    if (item.box >= LAST_BOX) {
      review.delete(answer.key);
      continue;
    }
    const box = item.box + 1;
    review.set(answer.key, { ...item, box, due_at: new Date(Date.parse(answer.at) + REVIEW_DAYS[box]! * DAY_MS).toISOString() });
  }
  return {
    sessions: state.sessions + 1,
    answers,
    correct,
    score: correct,
    streak,
    review: [...review.values()].sort((left, right) =>
      left.due_at === right.due_at ? left.key.localeCompare(right.key) : left.due_at.localeCompare(right.due_at)),
  };
}

/** The streak to show: it is broken when the last practice was before yesterday. */
export function shownStreak(state: PracticeState, today: string): number {
  const last = state.streak.last_date;
  return last !== null && (last === today || nextDay(last) === today) ? state.streak.current : 0;
}

/** Keys of the tasks due for review, oldest first. */
export function dueReviewKeys(state: PracticeState, now: Date, limit = PRACTICE_REVIEW): string[] {
  const moment = now.toISOString();
  return state.review.filter((item) => item.due_at <= moment).slice(0, limit).map((item) => item.key);
}

export function parsePracticeState(value: unknown): PracticeState | null {
  if (!isRecord(value) || !isRecord(value.streak) || !Array.isArray(value.review)) return null;
  const numbers = ["sessions", "answers", "correct", "score"] as const;
  if (!numbers.every((name) => typeof value[name] === "number")) return null;
  const streak = value.streak;
  return {
    sessions: value.sessions as number,
    answers: value.answers as number,
    correct: value.correct as number,
    score: value.score as number,
    streak: {
      current: typeof streak.current === "number" ? streak.current : 0,
      best: typeof streak.best === "number" ? streak.best : 0,
      last_date: typeof streak.last_date === "string" ? streak.last_date : null,
    },
    review: value.review.filter((item): item is ReviewItem =>
      isRecord(item) && typeof item.key === "string" && typeof item.target === "string"
      && isTaskType(item.type) && typeof item.box === "number" && typeof item.due_at === "string"),
  };
}

export function parsePracticeTasks(value: unknown): PracticeTask[] {
  if (!isRecord(value) || !Array.isArray(value.tasks)) return [];
  const tasks: PracticeTask[] = [];
  for (const item of value.tasks) {
    if (!isRecord(item) || typeof item.key !== "string" || !isTaskType(item.type) || typeof item.target !== "string") continue;
    const [example] = parseTajweedExamplesPage({ examples: [item.example] }).examples;
    const focus = typeof item.focus === "number" ? item.focus : 0;
    if (!example || !example.occurrences[focus]) continue;
    const options = Array.isArray(item.options) ? item.options.filter((option): option is string => typeof option === "string") : [];
    if (item.type !== "find" && !options.includes(item.target)) continue;
    tasks.push({ key: item.key, type: item.type, target: item.target, review: item.review === true, example, focus, options });
  }
  return tasks;
}

// Local store ------------------------------------------------------------------

export function practiceStorageKey(courseSlug: string): string {
  return `tajweed.practice.${courseSlug}`;
}

export function parsePracticeStore(raw: string | null): PracticeStore {
  const empty: PracticeStore = { state: emptyPracticeState(), pending: [] };
  if (!raw) return empty;
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return empty;
  }
  if (!isRecord(parsed)) return empty;
  const pending = Array.isArray(parsed.pending)
    ? parsed.pending.filter((session): session is PracticeSession =>
      isRecord(session) && typeof session.id === "string" && typeof session.local_date === "string"
      && typeof session.finished_at === "string" && Array.isArray(session.answers))
    : [];
  return { state: parsePracticeState(parsed.state) ?? emptyPracticeState(), pending };
}

/** A finished session counts at once and waits in `pending` until the account takes it. */
export function recordPracticeSession(store: PracticeStore, session: PracticeSession): PracticeStore {
  return {
    state: applyPracticeSession(store.state, session),
    pending: [...store.pending, session].slice(-PRACTICE_PENDING),
  };
}
