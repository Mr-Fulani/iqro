// Thematic courses (docs/courses/README.md): topic courses with notes, made in the admin.
// The prayer and tajweed courses have their own modules and are not part of this API.
// The server compiles the notes into blocks; the site only draws them.

import {
  readCourseProgress,
  recordLessonStep,
  writeCourseProgress,
  type CourseProgress,
} from "./course-progress.ts";

export const COURSES_SCHEMA_VERSION = 1;
export const COURSES_PROGRESS_EVENT = "iqro:courses-progress";

const SLUG_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

/** Course slugs the backend never gives out: they would clash with routes and the old courses. */
export const RESERVED_COURSE_SLUGS: ReadonlySet<string> = new Set([
  "salah",
  "tajweed",
  "quiz",
  "courses",
  "new",
  "preview",
  "events",
]);

function isSlug(value: string): boolean {
  return value.length <= 64 && SLUG_PATTERN.test(value);
}

export function isCourseSlug(value: string): boolean {
  return isSlug(value) && !RESERVED_COURSE_SLUGS.has(value);
}

export function isLessonSlug(value: string): boolean {
  return isSlug(value);
}

export function isQuizSlug(value: string): boolean {
  return isSlug(value) && !RESERVED_COURSE_SLUGS.has(value);
}

export type CourseCover = { url: string; thumb_url: string; width: number; height: number };

export type CourseListItem = {
  slug: string;
  version: string;
  title: string;
  summary: string;
  source: string;
  cover: CourseCover | null;
  lesson_count: number;
  minutes: number;
  video_minutes: number;
};

export type Segment = { text: string; bold?: true; lang?: "ar" };
export type TextDirection = "ltr" | "rtl";

export type NoteBlock =
  | { type: "heading"; dir: TextDirection; text: Segment[] }
  | { type: "paragraph"; dir: TextDirection; lines: Segment[][] }
  | { type: "list"; dir: TextDirection; ordered: boolean; items: Segment[][] }
  | { type: "quote"; dir: TextDirection; lines: Segment[][]; source: string | null }
  | { type: "note"; dir: TextDirection; lines: Segment[][] };

export type CourseLesson = {
  slug: string;
  number: number;
  title: string;
  summary: string;
  minutes: number;
  notes: NoteBlock[];
  sources: string[];
};

export type CourseDocument = {
  course: {
    slug: string;
    version: string;
    language: string;
    languages: string[];
    title: string;
    summary: string;
    source: string;
    cover: CourseCover | null;
  };
  lessons: CourseLesson[];
};

/** A document from a newer release than this page knows: the visitor reloads to get new code. */
export type CourseDocumentResult = { outdated: false; document: CourseDocument } | { outdated: true };

/** The part of a course the progress views need, small enough to pass to client components. */
export type CourseOutline = {
  slug: string;
  version: string;
  title: string;
  lessons: { slug: string; number: number; title: string }[];
};

export class CourseDocumentError extends Error {
  constructor(message: string) {
    super(`Invalid course document: ${message}`);
    this.name = "CourseDocumentError";
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function text(value: unknown, where: string): string {
  if (typeof value !== "string") throw new CourseDocumentError(`${where} is not a string`);
  return value;
}

function count(value: unknown, where: string): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0) {
    throw new CourseDocumentError(`${where} is not a count`);
  }
  return value;
}

function list(value: unknown, where: string): unknown[] {
  if (!Array.isArray(value)) throw new CourseDocumentError(`${where} is not a list`);
  return value;
}

function slug(value: unknown, where: string, check: (slug: string) => boolean): string {
  const result = text(value, where);
  if (!check(result)) throw new CourseDocumentError(`${where} is not a slug`);
  return result;
}

function mediaUrl(value: unknown, where: string): string {
  const url = text(value, where);
  if (url.startsWith("/") && !url.startsWith("//")) return url;
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    throw new CourseDocumentError(`${where} is not a URL`);
  }
  if (parsed.protocol !== "https:" || parsed.username || parsed.password) {
    throw new CourseDocumentError(`${where} is not an https URL`);
  }
  return parsed.toString();
}

function cover(value: unknown, where: string): CourseCover | null {
  if (value === null || value === undefined) return null;
  if (!isRecord(value)) throw new CourseDocumentError(`${where} is not an object`);
  return {
    url: mediaUrl(value.url, `${where}.url`),
    thumb_url: mediaUrl(value.thumb_url, `${where}.thumb_url`),
    width: count(value.width, `${where}.width`),
    height: count(value.height, `${where}.height`),
  };
}

function direction(value: unknown, where: string): TextDirection {
  if (value !== "ltr" && value !== "rtl") throw new CourseDocumentError(`${where} is not ltr or rtl`);
  return value;
}

function segments(value: unknown, where: string): Segment[] {
  return list(value, where).map((item, index) => {
    if (!isRecord(item)) throw new CourseDocumentError(`${where}[${index}] is not a segment`);
    const segment: Segment = { text: text(item.text, `${where}[${index}].text`) };
    if (item.bold === true) segment.bold = true;
    if (item.lang === "ar") segment.lang = "ar";
    return segment;
  });
}

function lines(value: unknown, where: string): Segment[][] {
  return list(value, where).map((line, index) => segments(line, `${where}[${index}]`));
}

export function parseNoteBlocks(value: unknown, where = "notes"): NoteBlock[] {
  return list(value, where).map((block, index): NoteBlock => {
    const at = `${where}[${index}]`;
    if (!isRecord(block)) throw new CourseDocumentError(`${at} is not a block`);
    const dir = direction(block.dir, `${at}.dir`);
    switch (block.type) {
      case "heading":
        return { type: "heading", dir, text: segments(block.text, `${at}.text`) };
      case "paragraph":
        return { type: "paragraph", dir, lines: lines(block.lines, `${at}.lines`) };
      case "list":
        if (typeof block.ordered !== "boolean") throw new CourseDocumentError(`${at}.ordered is not a boolean`);
        return { type: "list", dir, ordered: block.ordered, items: lines(block.items, `${at}.items`) };
      case "quote":
        return {
          type: "quote",
          dir,
          lines: lines(block.lines, `${at}.lines`),
          source: block.source === null ? null : text(block.source, `${at}.source`),
        };
      case "note":
        return { type: "note", dir, lines: lines(block.lines, `${at}.lines`) };
      default:
        throw new CourseDocumentError(`${at}.type is unknown`);
    }
  });
}

/** `GET /api/v1/courses`; fields this site does not know are ignored. */
export function parseCourseList(value: unknown): CourseListItem[] {
  if (!isRecord(value)) throw new CourseDocumentError("course list is not an object");
  return list(value.courses, "courses").map((item, index): CourseListItem => {
    const at = `courses[${index}]`;
    if (!isRecord(item)) throw new CourseDocumentError(`${at} is not an object`);
    return {
      slug: slug(item.slug, `${at}.slug`, isCourseSlug),
      version: text(item.version, `${at}.version`),
      title: text(item.title, `${at}.title`),
      summary: text(item.summary, `${at}.summary`),
      source: text(item.source, `${at}.source`),
      cover: cover(item.cover, `${at}.cover`),
      lesson_count: count(item.lesson_count, `${at}.lesson_count`),
      minutes: count(item.minutes, `${at}.minutes`),
      video_minutes: count(item.video_minutes, `${at}.video_minutes`),
    };
  });
}

/** `GET /api/v1/courses/{slug}`; fields this site does not know are ignored. */
export function parseCourseDocument(value: unknown): CourseDocumentResult {
  if (!isRecord(value)) throw new CourseDocumentError("not an object");
  const version = value.schema_version;
  if (typeof version === "number" && Number.isInteger(version) && version > COURSES_SCHEMA_VERSION) {
    return { outdated: true };
  }
  if (version !== COURSES_SCHEMA_VERSION) {
    throw new CourseDocumentError(`unsupported schema_version ${String(version)}`);
  }
  const course = value.course;
  if (!isRecord(course)) throw new CourseDocumentError("course is missing");
  const lessons = list(value.lessons, "lessons").map((lesson, index): CourseLesson => {
    const at = `lessons[${index}]`;
    if (!isRecord(lesson)) throw new CourseDocumentError(`${at} is not an object`);
    return {
      slug: slug(lesson.slug, `${at}.slug`, isLessonSlug),
      number: count(lesson.number, `${at}.number`),
      title: text(lesson.title, `${at}.title`),
      summary: text(lesson.summary, `${at}.summary`),
      minutes: count(lesson.minutes, `${at}.minutes`),
      notes: parseNoteBlocks(lesson.notes, `${at}.notes`),
      sources: list(lesson.sources, `${at}.sources`).map((source, item) => text(source, `${at}.sources[${item}]`)),
    };
  });
  return {
    outdated: false,
    document: {
      course: {
        slug: slug(course.slug, "course.slug", isCourseSlug),
        version: text(course.version, "course.version"),
        language: text(course.language, "course.language"),
        languages: list(course.languages, "course.languages").filter((item): item is string => typeof item === "string"),
        title: text(course.title, "course.title"),
        summary: text(course.summary, "course.summary"),
        source: text(course.source, "course.source"),
        cover: cover(course.cover, "course.cover"),
      },
      lessons,
    },
  };
}

export function courseOutline(document: CourseDocument): CourseOutline {
  return {
    slug: document.course.slug,
    version: document.course.version,
    title: document.course.title,
    lessons: document.lessons.map(({ slug, number, title }) => ({ slug, number, title })),
  };
}

// Progress -------------------------------------------------------------------
// The shape of lib/course-progress.ts; a thematic lesson has no steps, so `step_slug` is "".

export function courseProgressStorageKey(courseSlug: string): string {
  return `courses.progress.${courseSlug}`;
}

export function readThematicProgress(
  courseSlug: string,
  storage?: Pick<Storage, "getItem"> | null,
): CourseProgress {
  return readCourseProgress(courseProgressStorageKey(courseSlug), isLessonSlug, storage);
}

export function writeThematicProgress(
  progress: CourseProgress,
  courseSlug: string,
  storage?: Pick<Storage, "getItem" | "setItem"> | null,
): void {
  writeCourseProgress(progress, courseProgressStorageKey(courseSlug), COURSES_PROGRESS_EVENT, storage);
}

/** An opened lesson is in progress; a completed one stays completed. */
export function recordLessonOpened(
  progress: CourseProgress,
  lessonSlug: string,
  contentVersion: string,
  now?: Date,
): CourseProgress {
  return recordLessonStep(progress, lessonSlug, "", contentVersion, { now });
}

export function recordLessonCompleted(
  progress: CourseProgress,
  lessonSlug: string,
  contentVersion: string,
  now?: Date,
): CourseProgress {
  return recordLessonStep(progress, lessonSlug, "", contentVersion, { completed: true, now });
}

export type ThematicCourseSummary = {
  /** Completed lessons of the current release; a lesson gone from it does not count. */
  completed: number;
  total: number;
  started: boolean;
  /** The first lesson not completed yet, in course order. */
  nextLesson: CourseOutline["lessons"][number] | null;
  /** When the course was last opened, from its progress; "" before that. */
  updatedAt: string;
};

export function summarizeThematicProgress(outline: CourseOutline, progress: CourseProgress): ThematicCourseSummary {
  const entries = outline.lessons.map((lesson) => progress.lessons[lesson.slug]);
  return {
    completed: entries.filter((entry) => entry?.status === "completed").length,
    total: outline.lessons.length,
    started: entries.some(Boolean),
    nextLesson: outline.lessons.find((lesson) => progress.lessons[lesson.slug]?.status !== "completed") ?? null,
    updatedAt: entries.reduce((latest, entry) => (entry && entry.updated_at > latest ? entry.updated_at : latest), ""),
  };
}

/** «Continue»: the first unfinished lesson of the course opened last. */
export function continueTarget(
  outlines: CourseOutline[],
  progressOf: (courseSlug: string) => CourseProgress,
): { course: CourseOutline; lesson: CourseOutline["lessons"][number] } | null {
  let best: { course: CourseOutline; lesson: CourseOutline["lessons"][number]; updatedAt: string } | null = null;
  for (const course of outlines) {
    const summary = summarizeThematicProgress(course, progressOf(course.slug));
    if (!summary.started || !summary.nextLesson) continue;
    if (!best || summary.updatedAt > best.updatedAt) {
      best = { course, lesson: summary.nextLesson, updatedAt: summary.updatedAt };
    }
  }
  return best ? { course: best.course, lesson: best.lesson } : null;
}
