// Prayer-learning course: the compiled document contract (docs/salah/learning-spec.md §6)
// and the local progress the site shares with the app. The server compiles every
// sequence, so nothing here knows fiqh: it only looks things up and orders them.

import {
  browserStorage,
  parseCourseProgress,
  readCourseProgress,
  recordLessonStep,
  resumeStepIndex,
  stepIndex,
  summarizeCourseProgress,
  writeCourseProgress,
  type CourseProgress,
  type CourseSummary,
  type LessonOutline,
  type LessonProgress,
  type LessonStatus,
} from "./course-progress.ts";

export const SALAH_COURSE_SLUG = "hanbali-umdah";
export const SALAH_SCHEMA_VERSION = 1;

const SLUG_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const STEP_SLUG_PATTERN = /^[a-z0-9-]+(?:\.[a-z0-9-]+)+$/;

export type SalahLessonKind = "article" | "steps" | "prayer";
export type SalahStepKind = "action" | "recitation" | "info";
export type SalahRuling = "shart" | "rukn" | "wajib" | "sunnah";

const SALAH_RULINGS: ReadonlySet<string> = new Set<SalahRuling>(["shart", "rukn", "wajib", "sunnah"]);

/** A newer course may carry rulings this build has no label for; they are shown without one. */
export function isSalahRuling(value: string | undefined): value is SalahRuling {
  return value !== undefined && SALAH_RULINGS.has(value);
}

export type SalahCourseMeta = {
  slug: string;
  version: string;
  methodology: string;
  source_title: string;
  language: string;
  reviewed_by: string;
  reviewed_at: string;
  published_at: string;
  checksum_sha256: string;
};

export type SalahSection = {
  slug: string;
  title: string;
  lessons: string[];
};

/** «?» opens a help note, «!» a warning; a newer kind opens like a help note. */
export type SalahNoteKind = "help" | "warning";
export type SalahStepNote = { kind: SalahNoteKind; text: string };

export type SalahStep = {
  slug: string;
  kind: SalahStepKind;
  position?: string;
  ruling?: string;
  rakat?: number;
  title: string;
  instruction: string;
  details?: string;
  notes?: SalahStepNote[];
  /** The step's own voice-over, in the document's language. */
  audio?: SalahFormulaAudio;
  media?: string;
  formulas: string[];
  repeat?: number;
};

export type SalahPrayer = {
  code: string;
  /** A `prayer_kinds` code of the course; new kinds arrive as data. */
  kind: string;
  kind_title?: string;
  rakats: number;
};

export type SalahLesson = {
  slug: string;
  kind: SalahLessonKind;
  title: string;
  summary: string;
  minutes: number;
  prayer?: SalahPrayer;
  steps: SalahStep[];
};

export type SalahAudioSegment = { ayah: number; start_ms: number; end_ms: number };

export type SalahFormulaAudio = {
  url: string;
  start_ms?: number;
  end_ms?: number;
  segments?: SalahAudioSegment[];
};

export type SalahFormulaSource =
  | { kind: "dua"; collection: string; source_number: number }
  | { kind: "quran"; surah: number; ayah_from: number; ayah_to: number }
  | { kind: "inline" };

export type SalahFormula = {
  arabic: string;
  transliteration?: string;
  translation: string;
  /** Where the words come from, in the course's words: «Хисн аль-Муслим», № 33. */
  caption?: string;
  repetitions: number;
  audio?: SalahFormulaAudio;
  source: SalahFormulaSource;
};

/** The picture is a still of this pose of the schematic 3D scene (docs/salah/salah-3d.md). */
export type SalahMediaScene = { pose: string; view: SalahSceneView };
export type SalahSceneView = "full" | "hand" | "back";
const SALAH_SCENE_VIEWS: ReadonlySet<string> = new Set<SalahSceneView>(["full", "hand", "back"]);

export type SalahMedia = {
  url: string;
  width: number;
  height: number;
  bytes: number;
  sha256: string;
  alt: string;
  scene?: SalahMediaScene;
};

export type SalahCourseDocument = {
  schema_version: 1;
  course: SalahCourseMeta;
  sections: SalahSection[];
  lessons: SalahLesson[];
  formulas: Record<string, SalahFormula>;
  media: Record<string, SalahMedia>;
};

/** One lesson with only the formulas and media its steps use, for the client player. */
export type SalahLessonBundle = {
  courseVersion: string;
  lesson: SalahLesson;
  formulas: Record<string, SalahFormula>;
  media: Record<string, SalahMedia>;
};

export class SalahDocumentError extends Error {
  constructor(detail: string) {
    super(`Invalid prayer-learning course document: ${detail}`);
    this.name = "SalahDocumentError";
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function requireString(value: unknown, path: string): string {
  if (typeof value !== "string" || !value.trim()) throw new SalahDocumentError(`${path} must be a string`);
  return value;
}

function requirePositiveInteger(value: unknown, path: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 1) {
    throw new SalahDocumentError(`${path} must be a positive integer`);
  }
  return value;
}

function requireCount(value: unknown, path: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    throw new SalahDocumentError(`${path} must be a non-negative integer`);
  }
  return value;
}

function isSalahMediaScene(value: unknown): value is SalahMediaScene {
  return isRecord(value) && typeof value.pose === "string" && typeof value.view === "string" && SALAH_SCENE_VIEWS.has(value.view);
}

/** The notes a step can show: empty or malformed ones are dropped. */
export function parseSalahStepNotes(value: unknown): SalahStepNote[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((note): SalahStepNote[] =>
    isRecord(note) && typeof note.text === "string" && note.text.trim()
      ? [{ kind: note.kind === "warning" ? "warning" : "help", text: note.text }]
      : []);
}

function parseStepAudio(value: unknown): SalahFormulaAudio | undefined {
  return isRecord(value) && typeof value.url === "string" && value.url.trim() ? { url: value.url } : undefined;
}

export function isSalahSlug(value: string): boolean {
  return value.length <= 64 && SLUG_PATTERN.test(value);
}

export function isSalahStepSlug(value: string): boolean {
  return value.length <= 128 && STEP_SLUG_PATTERN.test(value);
}

/**
 * Checks the parts every renderer relies on and drops dangling references, so a
 * bad publish fails the render (ISR keeps the last good page) instead of shipping
 * a broken player.
 */
export function parseSalahCourseDocument(value: unknown): SalahCourseDocument {
  if (!isRecord(value)) throw new SalahDocumentError("root must be an object");
  if (value.schema_version !== SALAH_SCHEMA_VERSION) {
    throw new SalahDocumentError(`unsupported schema_version ${String(value.schema_version)}`);
  }
  const course = value.course;
  if (!isRecord(course)) throw new SalahDocumentError("course must be an object");
  requireString(course.slug, "course.slug");
  requireString(course.version, "course.version");
  if (!Array.isArray(value.sections)) throw new SalahDocumentError("sections must be an array");
  if (!Array.isArray(value.lessons)) throw new SalahDocumentError("lessons must be an array");
  if (!isRecord(value.formulas)) throw new SalahDocumentError("formulas must be an object");
  if (!isRecord(value.media)) throw new SalahDocumentError("media must be an object");

  const formulas = value.formulas as Record<string, SalahFormula>;
  for (const [id, formula] of Object.entries(formulas)) {
    if (!isRecord(formula)) throw new SalahDocumentError(`formulas.${id} must be an object`);
    requireString(formula.arabic, `formulas.${id}.arabic`);
    requirePositiveInteger(formula.repetitions, `formulas.${id}.repetitions`);
    // A malformed caption leaves the formula without one.
    if (typeof formula.caption !== "string" || !formula.caption.trim()) delete formula.caption;
  }
  const media: Record<string, SalahMedia> = {};
  for (const [key, item] of Object.entries(value.media)) {
    if (!isRecord(item)) throw new SalahDocumentError(`media.${key} must be an object`);
    requireString(item.url, `media.${key}.url`);
    requirePositiveInteger(item.width, `media.${key}.width`);
    requirePositiveInteger(item.height, `media.${key}.height`);
    // A malformed scene leaves just the picture.
    const { scene, ...picture } = item as SalahMedia & { scene?: unknown };
    media[key] = isSalahMediaScene(scene) ? { ...picture, scene } : picture;
  }

  const lessonSlugs = new Set<string>();
  const lessons = (value.lessons as unknown[]).map((lesson, index): SalahLesson => {
    if (!isRecord(lesson)) throw new SalahDocumentError(`lessons[${index}] must be an object`);
    const slug = requireString(lesson.slug, `lessons[${index}].slug`);
    if (!isSalahSlug(slug)) throw new SalahDocumentError(`lessons[${index}].slug is not a slug`);
    if (lessonSlugs.has(slug)) throw new SalahDocumentError(`lesson ${slug} is duplicated`);
    lessonSlugs.add(slug);
    requireString(lesson.title, `lessons.${slug}.title`);
    if (!Array.isArray(lesson.steps) || lesson.steps.length === 0) {
      throw new SalahDocumentError(`lessons.${slug}.steps must be a non-empty array`);
    }
    if (lesson.kind === "prayer") {
      if (!isRecord(lesson.prayer)) throw new SalahDocumentError(`lessons.${slug}.prayer is missing`);
      // 0 for a prayer without rak'ahs, such as the funeral prayer.
      requireCount(lesson.prayer.rakats, `lessons.${slug}.prayer.rakats`);
    }
    const stepSlugs = new Set<string>();
    const steps = (lesson.steps as unknown[]).map((step, stepIndex): SalahStep => {
      if (!isRecord(step)) throw new SalahDocumentError(`lessons.${slug}.steps[${stepIndex}] must be an object`);
      const stepSlug = requireString(step.slug, `lessons.${slug}.steps[${stepIndex}].slug`);
      if (!isSalahStepSlug(stepSlug) || stepSlugs.has(stepSlug)) {
        throw new SalahDocumentError(`step ${stepSlug} is not a unique step slug`);
      }
      stepSlugs.add(stepSlug);
      requireString(step.title, `steps.${stepSlug}.title`);
      if (typeof step.instruction !== "string") {
        throw new SalahDocumentError(`steps.${stepSlug}.instruction must be a string`);
      }
      const stepFormulas = Array.isArray(step.formulas) ? step.formulas : [];
      const { notes: rawNotes, audio: rawAudio, ...rest } = step as SalahStep & { notes?: unknown; audio?: unknown };
      const notes = parseSalahStepNotes(rawNotes);
      const audio = parseStepAudio(rawAudio);
      return {
        ...rest,
        formulas: stepFormulas.filter((id): id is string => typeof id === "string" && id in formulas),
        media: typeof step.media === "string" && step.media in media ? step.media : undefined,
        // Absent rather than empty, so the lesson bundle stays small.
        ...(notes.length ? { notes } : {}),
        ...(audio ? { audio } : {}),
      };
    });
    return { ...(lesson as SalahLesson), steps };
  });

  const sections = (value.sections as unknown[]).map((section, index): SalahSection => {
    if (!isRecord(section)) throw new SalahDocumentError(`sections[${index}] must be an object`);
    requireString(section.slug, `sections[${index}].slug`);
    requireString(section.title, `sections[${index}].title`);
    const sectionLessons = Array.isArray(section.lessons) ? section.lessons : [];
    return {
      ...(section as SalahSection),
      lessons: sectionLessons.filter((slug): slug is string => typeof slug === "string" && lessonSlugs.has(slug)),
    };
  });

  return {
    ...(value as SalahCourseDocument),
    sections,
    lessons,
    formulas,
    media,
  };
}

/** Lessons in course order: sections first, then any lesson no section lists. */
export function orderedLessons(document: SalahCourseDocument): SalahLesson[] {
  const bySlug = new Map(document.lessons.map((lesson) => [lesson.slug, lesson]));
  const ordered: SalahLesson[] = [];
  const seen = new Set<string>();
  for (const slug of document.sections.flatMap((section) => section.lessons)) {
    const lesson = bySlug.get(slug);
    if (lesson && !seen.has(slug)) {
      ordered.push(lesson);
      seen.add(slug);
    }
  }
  return [...ordered, ...document.lessons.filter((lesson) => !seen.has(lesson.slug))];
}

export function findSalahLesson(document: SalahCourseDocument, slug: string): SalahLesson | null {
  return document.lessons.find((lesson) => lesson.slug === slug) ?? null;
}

export function nextSalahLesson(document: SalahCourseDocument, slug: string): SalahLesson | null {
  const lessons = orderedLessons(document);
  const index = lessons.findIndex((lesson) => lesson.slug === slug);
  return index >= 0 ? lessons[index + 1] ?? null : null;
}

export function salahLessonBundle(document: SalahCourseDocument, lesson: SalahLesson): SalahLessonBundle {
  const formulaIds = new Set(lesson.steps.flatMap((step) => step.formulas));
  const mediaKeys = new Set(lesson.steps.flatMap((step) => (step.media ? [step.media] : [])));
  return {
    courseVersion: document.course.version,
    lesson,
    formulas: Object.fromEntries(Object.entries(document.formulas).filter(([id]) => formulaIds.has(id))),
    media: Object.fromEntries(Object.entries(document.media).filter(([key]) => mediaKeys.has(key))),
  };
}

/** Step slug from `#fajr.r1.ruku`, `#step=fajr.r1.ruku` or `?step=fajr.r1.ruku`. */
export function stepSlugFromLocation(hash: string, search: string): string | null {
  let fragment = hash.replace(/^#/, "");
  try {
    fragment = decodeURIComponent(fragment);
  } catch {
    return null;
  }
  const candidate = fragment.startsWith("step=")
    ? fragment.slice(5)
    : fragment || new URLSearchParams(search).get("step") || "";
  return isSalahStepSlug(candidate) ? candidate : null;
}

/** The part of a lesson that progress needs, small enough to pass to client components. */
export type SalahLessonOutline = LessonOutline;

export { stepIndex };

/** Where a formula's clip starts and stops in its audio file, in seconds. */
export function formulaAudioRange(audio: SalahFormulaAudio): { start: number; end: number | null } {
  const segments = audio.segments ?? [];
  const startMs = audio.start_ms ?? segments[0]?.start_ms ?? 0;
  const endMs = audio.end_ms ?? segments.at(-1)?.end_ms ?? null;
  return { start: startMs / 1000, end: endMs === null ? null : endMs / 1000 };
}

/**
 * The step-level counter is shown only when no formula card already counts the
 * same number of repetitions (the ruku' tasbih, for example, counts itself).
 */
export function stepRepeatTarget(step: SalahStep, formulas: Record<string, SalahFormula>): number | null {
  if (!step.repeat || step.repeat < 2) return null;
  const counted = step.formulas.some((id) => formulas[id]?.repetitions === step.repeat);
  return counted ? null : step.repeat;
}

// ---------------------------------------------------------------------------
// Progress (`course-progress.ts`). Same shape as the app's `app_state` value
// `salah.progress.<course>`.

export type SalahLessonStatus = LessonStatus;
export type SalahLessonProgress = LessonProgress;
export type SalahProgress = CourseProgress;
export type SalahCourseSummary = CourseSummary;

export const SALAH_PROGRESS_EVENT = "iqro:salah-progress";

export function salahProgressStorageKey(courseSlug: string = SALAH_COURSE_SLUG): string {
  return `salah.progress.${courseSlug}`;
}

export function parseSalahProgress(raw: string | null): SalahProgress {
  return parseCourseProgress(raw, isSalahSlug);
}

export function readSalahProgress(
  courseSlug: string = SALAH_COURSE_SLUG,
  storage: Pick<Storage, "getItem"> | null = browserStorage(),
): SalahProgress {
  return readCourseProgress(salahProgressStorageKey(courseSlug), isSalahSlug, storage);
}

/** Records the current step. A completed lesson stays completed when it is reopened. */
export const recordSalahStep = recordLessonStep;

export function writeSalahProgress(
  progress: SalahProgress,
  courseSlug: string = SALAH_COURSE_SLUG,
  storage: Pick<Storage, "getItem" | "setItem"> | null = browserStorage(),
): void {
  writeCourseProgress(progress, salahProgressStorageKey(courseSlug), SALAH_PROGRESS_EVENT, storage);
}

export { resumeStepIndex };
export const summarizeSalahProgress = summarizeCourseProgress;
