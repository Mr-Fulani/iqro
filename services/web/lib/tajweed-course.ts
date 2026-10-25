// The tajweed course (docs/tajweed/course.md): the compiled document, lesson
// examples picked from the markup of the whole Quran, the steps of a lesson and
// the local progress the site shares with the app.

import {
  parseCourseProgress,
  readCourseProgress,
  recordLessonStep,
  writeCourseProgress,
  type CourseProgress,
  type LessonOutline,
} from "./course-progress.ts";
import { highlightRuns, joinedRuns, wordTiming, type TajweedRun } from "./tajweed.ts";
import { CourseDocumentError, parseLessonMedia, type CourseMediaBlock } from "./thematic-courses.ts";

export const TAJWEED_COURSE_SLUG = "tajweed";
export const TAJWEED_COURSE_SCHEMA_VERSION = 1;
export const TAJWEED_PROGRESS_EVENT = "iqro:tajweed-progress";
/** Examples a lesson asks for first: three to read and one for «find the rule». */
export const FIRST_EXAMPLES = 4;
export const MORE_EXAMPLES = 3;

const SLUG_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const STEP_SLUG_PATTERN = /^(?:intro|how|find|example-[1-9][0-9]?)$/;

export type TajweedCourseTarget = {
  name: string;
  arabic_name: string;
  color: string;
  /** The Quran.Foundation class; null when the course reads the target from letters. */
  rule: string | null;
};

export type TajweedCourseLesson = {
  slug: string;
  section: string;
  target: string;
  minutes: number;
  title: string;
  summary: string;
  explanation: string;
  how: string;
  letters: string;
  /** Video, slides and banners above the explanation, in the author's order; `[]` without them. */
  media: CourseMediaBlock[];
};

export type TajweedCourseSection = { slug: string; title: string; lessons: string[] };

export type TajweedCourseDocument = {
  schema_version: number;
  course: {
    slug: string;
    version: string;
    language: string;
    title: string;
    summary: string;
    review_status: string;
    published_at: string | null;
  };
  targets: Record<string, TajweedCourseTarget>;
  sections: TajweedCourseSection[];
  lessons: TajweedCourseLesson[];
};

export type TajweedOccurrencePart = { position: number; start: number; end: number };
export type TajweedOccurrence = { parts: TajweedOccurrencePart[]; variant?: string };

export type TajweedCourseExample = {
  verse_key: string;
  surah_number: number;
  ayah_number: number;
  page_number: number;
  words: { position: number; text: string }[];
  occurrences: TajweedOccurrence[];
};

export type TajweedExamplesPage = {
  offset: number;
  next_offset: number | null;
  examples: TajweedCourseExample[];
};

export class TajweedCourseDocumentError extends Error {
  constructor(message: string) {
    super(`Invalid tajweed course document: ${message}`);
    this.name = "TajweedCourseDocumentError";
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function text(value: unknown, where: string): string {
  if (typeof value !== "string") throw new TajweedCourseDocumentError(`${where} is not a string`);
  return value;
}

/** The blocks are those of thematic courses; a broken one breaks this document like any field. */
function media(value: unknown, where: string): CourseMediaBlock[] {
  try {
    return parseLessonMedia(value, where);
  } catch (error) {
    if (error instanceof CourseDocumentError) throw new TajweedCourseDocumentError(error.detail);
    throw error;
  }
}

export function isTajweedLessonSlug(value: string): boolean {
  return value.length <= 64 && SLUG_PATTERN.test(value);
}

export function isTajweedStepSlug(value: string): boolean {
  return STEP_SLUG_PATTERN.test(value);
}

export function parseTajweedCourseDocument(value: unknown): TajweedCourseDocument {
  if (!isRecord(value)) throw new TajweedCourseDocumentError("not an object");
  if (value.schema_version !== TAJWEED_COURSE_SCHEMA_VERSION) {
    throw new TajweedCourseDocumentError(`unsupported schema_version ${String(value.schema_version)}`);
  }
  const course = value.course;
  if (!isRecord(course)) throw new TajweedCourseDocumentError("course is missing");
  if (!isRecord(value.targets)) throw new TajweedCourseDocumentError("targets is missing");
  const targets: Record<string, TajweedCourseTarget> = {};
  for (const [key, target] of Object.entries(value.targets)) {
    if (!isRecord(target)) throw new TajweedCourseDocumentError(`targets.${key} is not an object`);
    targets[key] = {
      name: text(target.name, `targets.${key}.name`),
      arabic_name: text(target.arabic_name, `targets.${key}.arabic_name`),
      color: text(target.color, `targets.${key}.color`),
      rule: typeof target.rule === "string" ? target.rule : null,
    };
  }
  if (!Array.isArray(value.lessons)) throw new TajweedCourseDocumentError("lessons is missing");
  const lessons = value.lessons.map((lesson, index): TajweedCourseLesson => {
    if (!isRecord(lesson)) throw new TajweedCourseDocumentError(`lessons[${index}] is not an object`);
    const slug = text(lesson.slug, `lessons[${index}].slug`);
    if (!isTajweedLessonSlug(slug)) throw new TajweedCourseDocumentError(`lessons[${index}].slug is not a slug`);
    const target = text(lesson.target, `lessons[${index}].target`);
    if (!targets[target]) throw new TajweedCourseDocumentError(`lessons[${index}].target is unknown`);
    return {
      slug,
      section: text(lesson.section, `lessons[${index}].section`),
      target,
      minutes: typeof lesson.minutes === "number" ? lesson.minutes : 0,
      title: text(lesson.title, `lessons[${index}].title`),
      summary: text(lesson.summary, `lessons[${index}].summary`),
      explanation: text(lesson.explanation, `lessons[${index}].explanation`),
      how: text(lesson.how, `lessons[${index}].how`),
      letters: typeof lesson.letters === "string" ? lesson.letters : "",
      media: media(lesson.media, `lessons[${index}].media`),
    };
  });
  const known = new Set(lessons.map((lesson) => lesson.slug));
  if (!Array.isArray(value.sections)) throw new TajweedCourseDocumentError("sections is missing");
  const sections = value.sections.map((section, index): TajweedCourseSection => {
    if (!isRecord(section) || !Array.isArray(section.lessons)) {
      throw new TajweedCourseDocumentError(`sections[${index}] is not a section`);
    }
    return {
      slug: text(section.slug, `sections[${index}].slug`),
      title: text(section.title, `sections[${index}].title`),
      lessons: section.lessons.filter((slug): slug is string => typeof slug === "string" && known.has(slug)),
    };
  });
  return {
    schema_version: TAJWEED_COURSE_SCHEMA_VERSION,
    course: {
      slug: text(course.slug, "course.slug"),
      version: text(course.version, "course.version"),
      language: text(course.language, "course.language"),
      title: text(course.title, "course.title"),
      summary: text(course.summary, "course.summary"),
      review_status: text(course.review_status, "course.review_status"),
      published_at: typeof course.published_at === "string" ? course.published_at : null,
    },
    targets,
    sections,
    lessons,
  };
}

/** A page of lesson examples from the API; examples that do not fit are dropped. */
export function parseTajweedExamplesPage(value: unknown): TajweedExamplesPage {
  if (!isRecord(value) || !Array.isArray(value.examples)) return { offset: 0, next_offset: null, examples: [] };
  const examples = value.examples.filter((example): example is TajweedCourseExample =>
    isRecord(example)
    && typeof example.verse_key === "string"
    && Array.isArray(example.words)
    && example.words.every((word) => isRecord(word) && typeof word.position === "number" && typeof word.text === "string")
    && Array.isArray(example.occurrences)
    && example.occurrences.length > 0
    && example.occurrences.every((occurrence) =>
      isRecord(occurrence)
      && Array.isArray(occurrence.parts)
      && occurrence.parts.length > 0
      && occurrence.parts.every((part) =>
        isRecord(part) && typeof part.position === "number" && typeof part.start === "number" && typeof part.end === "number")));
  return {
    offset: typeof value.offset === "number" ? value.offset : 0,
    next_offset: typeof value.next_offset === "number" ? value.next_offset : null,
    examples,
  };
}

/** Lessons in the course order. */
export function courseLessons(document: TajweedCourseDocument): TajweedCourseLesson[] {
  const bySlug = new Map(document.lessons.map((lesson) => [lesson.slug, lesson]));
  return document.sections.flatMap((section) => section.lessons.map((slug) => bySlug.get(slug)!));
}

export function nextTajweedLesson(document: TajweedCourseDocument, slug: string): TajweedCourseLesson | null {
  const lessons = courseLessons(document);
  const index = lessons.findIndex((lesson) => lesson.slug === slug);
  return index >= 0 ? lessons[index + 1] ?? null : null;
}

// Steps ----------------------------------------------------------------------

/** Step slugs of a lesson with `shown` examples to read and, maybe, the «find» exercise. */
export function lessonStepSlugs(shown: number, hasFind: boolean): string[] {
  return [
    "intro",
    "how",
    ...Array.from({ length: Math.max(1, shown) }, (_, index) => `example-${index + 1}`),
    ...(hasFind ? ["find"] : []),
  ];
}

/** The first page of examples: all but the last are read, the last is found. */
export function splitFirstExamples(examples: readonly TajweedCourseExample[]): {
  shown: TajweedCourseExample[];
  find: TajweedCourseExample | null;
} {
  if (examples.length < 2) return { shown: [...examples], find: null };
  return { shown: examples.slice(0, -1), find: examples.at(-1)! };
}

/** The steps progress knows before the examples arrive: three examples and «find». */
export function lessonOutline(lesson: Pick<TajweedCourseLesson, "slug">): LessonOutline {
  return { slug: lesson.slug, steps: lessonStepSlugs(FIRST_EXAMPLES - 1, true).map((slug) => ({ slug })) };
}

/** Step slug from `#example-2`, `#step=example-2` or `?step=example-2`. */
export function tajweedStepFromLocation(hash: string, search: string): string | null {
  const fragment = hash.replace(/^#/, "");
  const candidate = fragment.startsWith("step=")
    ? fragment.slice(5)
    : fragment || new URLSearchParams(search).get("step") || "";
  return isTajweedStepSlug(candidate) ? candidate : null;
}

// Examples -------------------------------------------------------------------

export function occurrencePositions(occurrence: TajweedOccurrence): number[] {
  return occurrence.parts.map((part) => part.position);
}

/** Index of the occurrence that has a part in the word at `position`, or -1. */
export function occurrenceAt(example: TajweedCourseExample, position: number): number {
  return example.occurrences.findIndex((occurrence) => occurrencePositions(occurrence).includes(position));
}

/** A word's text in runs; `code` is "target" on the letters of the occurrence. */
export function occurrenceRuns(
  word: { position: number; text: string },
  occurrence: TajweedOccurrence | null,
): TajweedRun[] {
  const fragments = (occurrence?.parts ?? [])
    .filter((part) => part.position === word.position)
    .map((part) => ({ code: "target", start: part.start, end: part.end }));
  return fragments.length ? joinedRuns(highlightRuns(word.text, fragments)) : [{ text: word.text, code: null }];
}

/** `[start_ms, end_ms)` of an occurrence in the reciter's track: its first word to its last. */
export function occurrenceTiming(
  words: readonly (readonly number[])[] | undefined,
  occurrence: TajweedOccurrence,
): { startMs: number; endMs: number } | null {
  const positions = occurrencePositions(occurrence);
  const first = wordTiming(words, Math.min(...positions));
  const last = wordTiming(words, Math.max(...positions));
  return first && last && last.endMs > first.startMs ? { startMs: first.startMs, endMs: last.endMs } : null;
}

// Progress -------------------------------------------------------------------

export function tajweedProgressStorageKey(courseSlug: string = TAJWEED_COURSE_SLUG): string {
  return `tajweed.progress.${courseSlug}`;
}

export function parseTajweedProgress(raw: string | null): CourseProgress {
  return parseCourseProgress(raw, isTajweedLessonSlug);
}

export function readTajweedProgress(
  courseSlug: string = TAJWEED_COURSE_SLUG,
  storage?: Pick<Storage, "getItem"> | null,
): CourseProgress {
  return readCourseProgress(tajweedProgressStorageKey(courseSlug), isTajweedLessonSlug, storage);
}

export function writeTajweedProgress(
  progress: CourseProgress,
  courseSlug: string = TAJWEED_COURSE_SLUG,
  storage?: Pick<Storage, "getItem" | "setItem"> | null,
): void {
  writeCourseProgress(progress, tajweedProgressStorageKey(courseSlug), TAJWEED_PROGRESS_EVENT, storage);
}

export const recordTajweedStep = recordLessonStep;
