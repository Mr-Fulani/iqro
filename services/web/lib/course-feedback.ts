// Sharing, votes, ratings and anonymous counters of thematic courses
// (docs/courses/README.md, «Поделиться, оценка, замечания и статистика»).
// The app keeps the same storage keys and sends the same events.

import { browserStorage } from "./course-progress.ts";

export const COURSE_EVENTS_URL = "/api/v1/courses/events";
export const FLUSH_EVERY_MS = 60_000;
export const MAX_EVENTS_PER_BATCH = 50;
export const MAX_RATING_COMMENT = 1_000;
export const MAX_REPORT_MESSAGE = 4_000;
export const MAX_REPORT_SUBJECT = 160;

export type CourseEventName =
  | "lesson_opened"
  | "video_started"
  | "video_finished"
  | "lesson_completed"
  | "lesson_helpful"
  | "lesson_not_helpful";

export type CourseEvent = { course: string; lesson: string; event: CourseEventName };

/** A video counts as watched from 90 % of its length. */
export function isVideoFinished(currentMs: number, durationMs: number): boolean {
  return durationMs > 0 && currentMs >= durationMs * 0.9;
}

/** Request bodies of at most 50 events each, in order. */
export function eventBatches(events: readonly CourseEvent[], platform = "web"): string[] {
  const bodies: string[] = [];
  for (let start = 0; start < events.length; start += MAX_EVENTS_PER_BATCH) {
    bodies.push(JSON.stringify({ platform, events: events.slice(start, start + MAX_EVENTS_PER_BATCH) }));
  }
  return bodies;
}

// The queue -------------------------------------------------------------------
// Counters are best effort: a failed or throttled batch is dropped, never retried.

const queue: CourseEvent[] = [];
let flushTimer: ReturnType<typeof setTimeout> | null = null;
let flushOnHideBound = false;

function sendBatch(body: string): void {
  // No cookie and no account: the server keeps only daily sums.
  void fetch(COURSE_EVENTS_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body,
    credentials: "omit",
    keepalive: true,
  }).catch(() => undefined);
}

export function flushCourseEvents(send: (body: string) => void = sendBatch): void {
  if (flushTimer) clearTimeout(flushTimer);
  flushTimer = null;
  for (const body of eventBatches(queue.splice(0))) send(body);
}

export function trackCourseEvent(event: CourseEvent): void {
  queue.push(event);
  if (typeof window === "undefined") return;
  if (!flushOnHideBound) {
    flushOnHideBound = true;
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "hidden") flushCourseEvents();
    });
    window.addEventListener("pagehide", () => flushCourseEvents());
  }
  if (!flushTimer) flushTimer = setTimeout(() => flushCourseEvents(), FLUSH_EVERY_MS);
}

// Where the lesson video is now, for «Сообщить об ошибке» ----------------------

const videoTimes = new Map<string, number>();

export function noteVideoTime(course: string, lesson: string, ms: number): void {
  videoTimes.set(`${course}/${lesson}`, Math.max(0, Math.floor(ms)));
}

/** The video position of this page view; undefined if the video was not started. */
export function videoTimeOf(course: string, lesson: string): number | undefined {
  return videoTimes.get(`${course}/${lesson}`);
}

// «Полезно / Не очень»: one vote per lesson on this device --------------------

export type LessonVote = "helpful" | "not_helpful";
export type LessonVotes = Record<string, LessonVote>;

export function voteStorageKey(courseSlug: string): string {
  return `courses.vote.${courseSlug}`;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function parseJson(raw: string | null | undefined): unknown {
  if (!raw) return null;
  try {
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

export function parseVotes(raw: string | null | undefined): LessonVotes {
  const parsed = parseJson(raw);
  const votes: LessonVotes = {};
  if (!isRecord(parsed)) return votes;
  for (const [lesson, vote] of Object.entries(parsed)) {
    if (vote === "helpful" || vote === "not_helpful") votes[lesson] = vote;
  }
  return votes;
}

export function readVotes(courseSlug: string, storage = browserStorage()): LessonVotes {
  try {
    return parseVotes(storage?.getItem(voteStorageKey(courseSlug)));
  } catch {
    return {};
  }
}

/** Saves the vote unless the lesson already has one; true when it was saved. */
export function recordVote(
  courseSlug: string,
  lessonSlug: string,
  vote: LessonVote,
  storage: Pick<Storage, "getItem" | "setItem"> | null = browserStorage(),
): boolean {
  const votes = readVotes(courseSlug, storage);
  if (votes[lessonSlug]) return false;
  votes[lessonSlug] = vote;
  try {
    storage?.setItem(voteStorageKey(courseSlug), JSON.stringify(votes));
  } catch {
    // A blocked storage still counts this vote once for the page view.
  }
  return true;
}

// The course rating, as the device remembers it -------------------------------

export type StoredRating = { stars: number; comment: string; updated_at: string };

export function ratingStorageKey(courseSlug: string): string {
  return `courses.rating.${courseSlug}`;
}

export function parseRating(raw: string | null | undefined): StoredRating | null {
  const parsed = parseJson(raw);
  if (!isRecord(parsed)) return null;
  const { stars, comment, updated_at: updatedAt } = parsed;
  if (typeof stars !== "number" || !Number.isInteger(stars) || stars < 1 || stars > 5) return null;
  return {
    stars,
    comment: typeof comment === "string" ? comment : "",
    updated_at: typeof updatedAt === "string" ? updatedAt : "",
  };
}

export function readRating(courseSlug: string, storage = browserStorage()): StoredRating | null {
  try {
    return parseRating(storage?.getItem(ratingStorageKey(courseSlug)));
  } catch {
    return null;
  }
}

export function writeRating(
  courseSlug: string,
  rating: StoredRating,
  storage: Pick<Storage, "setItem"> | null = browserStorage(),
): void {
  try {
    storage?.setItem(ratingStorageKey(courseSlug), JSON.stringify(rating));
  } catch {
    // The server has the rating; only the reminder on this device is lost.
  }
}

// «Сообщить об ошибке» ---------------------------------------------------------

export const REPORT_CATEGORIES = ["religious_content", "accessibility_localization", "technical", "other"] as const;
export type ReportCategory = (typeof REPORT_CATEGORIES)[number];

/** «{курс} · {номер}. {тема}», cut to the 160 characters a ticket subject takes. */
export function reportSubject(courseTitle: string, lessonNumber: number, lessonTitle: string): string {
  const subject = `${courseTitle} · ${lessonNumber}. ${lessonTitle}`.replace(/\s+/g, " ").trim();
  return subject.length > MAX_REPORT_SUBJECT ? `${subject.slice(0, MAX_REPORT_SUBJECT - 1)}…` : subject;
}

export type ReportContext = {
  course_slug: string;
  lesson_slug: string;
  content_version: string;
  route: string;
  client_platform: "web";
  playback_ms?: number;
};

export function reportContext(
  course: string,
  lesson: string,
  version: string,
  playbackMs: number | undefined,
): ReportContext {
  return {
    course_slug: course,
    lesson_slug: lesson,
    content_version: version,
    route: `/courses/${course}/${lesson}`,
    client_platform: "web",
    ...(playbackMs === undefined ? {} : { playback_ms: playbackMs }),
  };
}
