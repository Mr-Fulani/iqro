// Thematic courses (docs/courses/README.md): topic courses with notes, made in the admin.
// The prayer and tajweed courses have their own modules and are not part of this API.
// The server compiles the notes into blocks; the site only draws them.

import {
  browserStorage,
  readCourseProgress,
  recordLessonStep,
  writeCourseProgress,
  type CourseProgress,
} from "./course-progress.ts";

export const COURSES_SCHEMA_VERSION = 1;
export const COURSES_PROGRESS_EVENT = "iqro:courses-progress";
export const COURSES_POSITION_EVENT = "iqro:courses-position";

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

/** One video per lesson; the server already chose the file with the sound of the document's language. */
export type CourseVideo = {
  url: string;
  bytes: number;
  duration_ms: number;
  width: number;
  height: number;
  /** The language heard in the file; "" for a video without speech. */
  spoken_language: string;
  poster: { url: string; small_url: string; width: number; height: number };
};

/** A WebP from the media host: `url` up to 1600 px on the longer side, `small_url` up to 800 px. */
export type CourseImage = { url: string; small_url: string; width: number; height: number };

export type CourseSlide = { image: CourseImage; caption: string; alt: string; dir: TextDirection };

/** Lesson media above the notes, in the author's order (docs/courses/README.md, «Медиа темы»). */
export type CourseMediaBlock =
  | { type: "video"; video: CourseVideo }
  | { type: "slides"; slides: CourseSlide[] }
  | { type: "banner"; image: CourseImage; caption: string; alt: string; dir: TextDirection };

export type CourseLesson = {
  slug: string;
  number: number;
  title: string;
  summary: string;
  minutes: number;
  video: CourseVideo | null;
  media: CourseMediaBlock[];
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
  /** What is wrong, without the prefix: the tajweed course reports media errors as its own. */
  readonly detail: string;

  constructor(message: string) {
    super(`Invalid course document: ${message}`);
    this.name = "CourseDocumentError";
    this.detail = message;
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

const MEDIA_HOST = "media.iqro.forum";

function fromMediaHost(url: string): boolean {
  return url.startsWith("/") || new URL(url).host === MEDIA_HOST;
}

/** Videos come only from the media host (or this site's /media proxy), as the app requires. */
function video(value: unknown, where: string): CourseVideo | null {
  if (value === null || value === undefined) return null;
  if (!isRecord(value)) throw new CourseDocumentError(`${where} is not an object`);
  const poster = value.poster;
  if (!isRecord(poster)) throw new CourseDocumentError(`${where}.poster is not an object`);
  const result: CourseVideo = {
    url: mediaUrl(value.url, `${where}.url`),
    bytes: count(value.bytes, `${where}.bytes`),
    duration_ms: count(value.duration_ms, `${where}.duration_ms`),
    width: count(value.width, `${where}.width`),
    height: count(value.height, `${where}.height`),
    spoken_language: text(value.spoken_language, `${where}.spoken_language`),
    poster: {
      url: mediaUrl(poster.url, `${where}.poster.url`),
      small_url: mediaUrl(poster.small_url, `${where}.poster.small_url`),
      width: count(poster.width, `${where}.poster.width`),
      height: count(poster.height, `${where}.poster.height`),
    },
  };
  const approved = [result.url, result.poster.url, result.poster.small_url].every(fromMediaHost);
  // A file from elsewhere is left out; the notes of the lesson still show.
  return approved ? result : null;
}

function direction(value: unknown, where: string): TextDirection {
  if (value !== "ltr" && value !== "rtl") throw new CourseDocumentError(`${where} is not ltr or rtl`);
  return value;
}

/** A slide or banner picture; one from another host is `null`, like a video. */
function image(value: unknown, where: string): CourseImage | null {
  if (!isRecord(value)) throw new CourseDocumentError(`${where} is not an object`);
  const result: CourseImage = {
    url: mediaUrl(value.url, `${where}.url`),
    small_url: mediaUrl(value.small_url, `${where}.small_url`),
    width: count(value.width, `${where}.width`),
    height: count(value.height, `${where}.height`),
  };
  return fromMediaHost(result.url) && fromMediaHost(result.small_url) ? result : null;
}

/**
 * `lessons[].media`. A release prepared before media has no field: its video is the only block.
 * A block of an unknown type, or with a file from another host, is left out; the notes still show.
 */
function media(value: unknown, lessonVideo: CourseVideo | null, where: string): CourseMediaBlock[] {
  if (value === undefined || value === null) return lessonVideo ? [{ type: "video", video: lessonVideo }] : [];
  return parseLessonMedia(value, where);
}

/**
 * Media blocks of a lesson, shared with the tajweed course (docs/tajweed/course.md): no field is
 * no media. A block of an unknown type, or with a file from another host, is left out.
 */
export function parseLessonMedia(value: unknown, where: string): CourseMediaBlock[] {
  if (value === undefined || value === null) return [];
  const blocks: CourseMediaBlock[] = [];
  list(value, where).forEach((block, index) => {
    const at = `${where}[${index}]`;
    if (!isRecord(block)) throw new CourseDocumentError(`${at} is not a block`);
    if (block.type === "video") {
      const parsed = video(block.video, `${at}.video`);
      if (parsed) blocks.push({ type: "video", video: parsed });
    } else if (block.type === "slides") {
      const slides = list(block.slides, `${at}.slides`).map((slide, item) => {
        const on = `${at}.slides[${item}]`;
        if (!isRecord(slide)) throw new CourseDocumentError(`${on} is not an object`);
        return {
          image: image(slide.image, `${on}.image`),
          caption: text(slide.caption, `${on}.caption`),
          alt: text(slide.alt, `${on}.alt`),
          dir: direction(slide.dir, `${on}.dir`),
        };
      });
      // A block with a picture from another host is left out whole, as is an empty one.
      if (slides.length && slides.every((slide) => slide.image)) blocks.push({ type: "slides", slides: slides as CourseSlide[] });
    } else if (block.type === "banner") {
      const picture = image(block.image, `${at}.image`);
      const caption = text(block.caption, `${at}.caption`);
      const alt = text(block.alt, `${at}.alt`);
      const dir = direction(block.dir, `${at}.dir`);
      if (picture) blocks.push({ type: "banner", image: picture, caption, alt, dir });
    }
  });
  return blocks;
}

/** The lesson video among its media, for «12 min · video 9:48». */
export function mediaVideo(blocks: CourseMediaBlock[]): CourseVideo | null {
  for (const block of blocks) if (block.type === "video") return block.video;
  return null;
}

/** The lesson column on the site: the full width on a phone, about 880 px beside the outline. */
export const LESSON_MEDIA_SIZES = "(max-width: 900px) 100vw, 880px";

/** `srcset` with the real widths: `small_url` is the same picture at up to 800 px on its longer side. */
export function lessonImageSrcSet(image: CourseImage): string {
  const small = Math.round(image.width * Math.min(1, 800 / Math.max(image.width, image.height, 1)));
  return `${image.small_url} ${small}w, ${image.url} ${image.width}w`;
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
    const lessonVideo = video(lesson.video, `${at}.video`);
    return {
      slug: slug(lesson.slug, `${at}.slug`, isLessonSlug),
      number: count(lesson.number, `${at}.number`),
      title: text(lesson.title, `${at}.title`),
      summary: text(lesson.summary, `${at}.summary`),
      minutes: count(lesson.minutes, `${at}.minutes`),
      video: lessonVideo,
      media: media(lesson.media, lessonVideo, `${at}.media`),
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

/** Whole minutes of video, rounded up, as `courses[].video_minutes` in the list. */
export function videoMinutes(lessons: Pick<CourseLesson, "video">[]): number {
  return Math.ceil(lessons.reduce((total, lesson) => total + (lesson.video?.duration_ms ?? 0), 0) / 60_000);
}

/** The size on the video's cover, in the binary megabytes the contract example shows (108 МБ). */
export function videoMegabytes(bytes: number): number {
  return Math.max(1, Math.round(bytes / 1_048_576));
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

// Video positions ------------------------------------------------------------
// `courses.position.<slug>` = {"<lesson>": {"ms": 252000, "updated_at": "<ISO>"}}, as in the app.

export type VideoPositions = Record<string, { ms: number; updated_at: string }>;

export function videoPositionStorageKey(courseSlug: string): string {
  return `courses.position.${courseSlug}`;
}

/** Stored positions; entries that do not fit are dropped. */
export function parseVideoPositions(raw: string | null): VideoPositions {
  const positions: VideoPositions = {};
  if (!raw) return positions;
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return positions;
  }
  if (!isRecord(parsed)) return positions;
  for (const [slug, entry] of Object.entries(parsed)) {
    if (!isLessonSlug(slug) || !isRecord(entry)) continue;
    const { ms } = entry;
    if (typeof ms !== "number" || !Number.isInteger(ms) || ms <= 0) continue;
    positions[slug] = { ms, updated_at: typeof entry.updated_at === "string" ? entry.updated_at : "" };
  }
  return positions;
}

export function readVideoPositions(courseSlug: string, storage = browserStorage()): VideoPositions {
  try {
    return parseVideoPositions(storage?.getItem(videoPositionStorageKey(courseSlug)) ?? null);
  } catch {
    return {};
  }
}

/** Saves where the video stopped; `null` (watched to the end) forgets it. */
export function writeVideoPosition(
  courseSlug: string,
  lessonSlug: string,
  ms: number | null,
  { storage = browserStorage(), now = new Date() }: { storage?: Pick<Storage, "getItem" | "setItem"> | null; now?: Date } = {},
): void {
  if (!storage) return;
  const positions = readVideoPositions(courseSlug, storage);
  const whole = ms === null ? 0 : Math.floor(ms);
  if (whole > 0) positions[lessonSlug] = { ms: whole, updated_at: now.toISOString() };
  else delete positions[lessonSlug];
  try {
    storage.setItem(videoPositionStorageKey(courseSlug), JSON.stringify(positions));
  } catch {
    // The position stays best-effort when storage is blocked or full.
    return;
  }
  if (typeof window !== "undefined") window.dispatchEvent(new Event(COURSES_POSITION_EVENT));
}
