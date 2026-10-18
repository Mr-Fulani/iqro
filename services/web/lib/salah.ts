// Prayer-learning course: the compiled document contract (docs/salah/learning-spec.md §6)
// and the local progress the site shares with the app. The server compiles every
// sequence, so nothing here knows fiqh: it only looks things up and orders them.

export const SALAH_COURSE_SLUG = "hanbali-umdah";
export const SALAH_SCHEMA_VERSION = 1;

const SLUG_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const STEP_SLUG_PATTERN = /^[a-z0-9-]+(?:\.[a-z0-9-]+)+$/;

export type SalahLessonKind = "article" | "steps" | "prayer";
export type SalahStepKind = "action" | "recitation" | "info";
export type SalahRuling = "shart" | "rukn" | "wajib" | "sunnah";

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

export type SalahStep = {
  slug: string;
  kind: SalahStepKind;
  position?: string;
  ruling?: SalahRuling;
  rakat?: number;
  title: string;
  instruction: string;
  details?: string;
  media?: string;
  formulas: string[];
  repeat?: number;
};

export type SalahPrayer = {
  code: string;
  kind: "fard" | "witr" | "sunnah";
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
  repetitions: number;
  audio?: SalahFormulaAudio;
  source: SalahFormulaSource;
};

export type SalahMedia = {
  url: string;
  width: number;
  height: number;
  bytes: number;
  sha256: string;
  alt: string;
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
  }
  const media = value.media as Record<string, SalahMedia>;
  for (const [key, item] of Object.entries(media)) {
    if (!isRecord(item)) throw new SalahDocumentError(`media.${key} must be an object`);
    requireString(item.url, `media.${key}.url`);
    requirePositiveInteger(item.width, `media.${key}.width`);
    requirePositiveInteger(item.height, `media.${key}.height`);
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
      requirePositiveInteger(lesson.prayer.rakats, `lessons.${slug}.prayer.rakats`);
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
      return {
        ...(step as SalahStep),
        formulas: stepFormulas.filter((id): id is string => typeof id === "string" && id in formulas),
        media: typeof step.media === "string" && step.media in media ? step.media : undefined,
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
export type SalahLessonOutline = { slug: string; steps: { slug: string }[] };

export function stepIndex(lesson: Pick<SalahLessonOutline, "steps">, stepSlug: string | null | undefined): number {
  if (!stepSlug) return -1;
  return lesson.steps.findIndex((step) => step.slug === stepSlug);
}

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
// Progress. Same shape as the app's `app_state` value `salah.progress.<course>`:
// {"lessons": {"<lesson>": {"status", "step_slug", "content_version", "updated_at"}}}

export type SalahLessonStatus = "in_progress" | "completed";

export type SalahLessonProgress = {
  status: SalahLessonStatus;
  step_slug: string;
  content_version: string;
  updated_at: string;
};

export type SalahProgress = {
  lessons: Record<string, SalahLessonProgress>;
};

type ProgressStorage = Pick<Storage, "getItem" | "setItem">;

export const SALAH_PROGRESS_EVENT = "iqro:salah-progress";

export function salahProgressStorageKey(courseSlug: string = SALAH_COURSE_SLUG): string {
  return `salah.progress.${courseSlug}`;
}

function browserStorage(): ProgressStorage | null {
  try {
    return typeof window !== "undefined" ? window.localStorage : null;
  } catch {
    return null;
  }
}

export function parseSalahProgress(raw: string | null): SalahProgress {
  const empty: SalahProgress = { lessons: {} };
  if (!raw) return empty;
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return empty;
  }
  if (!isRecord(parsed) || !isRecord(parsed.lessons)) return empty;
  const lessons: Record<string, SalahLessonProgress> = {};
  for (const [slug, entry] of Object.entries(parsed.lessons)) {
    if (
      !isSalahSlug(slug)
      || !isRecord(entry)
      || (entry.status !== "in_progress" && entry.status !== "completed")
      || typeof entry.step_slug !== "string"
      || typeof entry.content_version !== "string"
    ) continue;
    lessons[slug] = {
      status: entry.status,
      step_slug: entry.step_slug,
      content_version: entry.content_version,
      updated_at: typeof entry.updated_at === "string" ? entry.updated_at : "",
    };
  }
  return { lessons };
}

export function readSalahProgress(
  courseSlug: string = SALAH_COURSE_SLUG,
  storage: Pick<Storage, "getItem"> | null = browserStorage(),
): SalahProgress {
  if (!storage) return { lessons: {} };
  try {
    return parseSalahProgress(storage.getItem(salahProgressStorageKey(courseSlug)));
  } catch {
    return { lessons: {} };
  }
}

/** Records the current step. A completed lesson stays completed when it is reopened. */
export function recordSalahStep(
  progress: SalahProgress,
  lessonSlug: string,
  stepSlug: string,
  contentVersion: string,
  { completed = false, now = new Date() }: { completed?: boolean; now?: Date } = {},
): SalahProgress {
  const previous = progress.lessons[lessonSlug];
  const status: SalahLessonStatus = completed || previous?.status === "completed" ? "completed" : "in_progress";
  return {
    lessons: {
      ...progress.lessons,
      [lessonSlug]: {
        status,
        step_slug: stepSlug,
        content_version: contentVersion,
        updated_at: now.toISOString(),
      },
    },
  };
}

export function writeSalahProgress(
  progress: SalahProgress,
  courseSlug: string = SALAH_COURSE_SLUG,
  storage: ProgressStorage | null = browserStorage(),
): void {
  if (!storage) return;
  try {
    storage.setItem(salahProgressStorageKey(courseSlug), JSON.stringify(progress));
  } catch {
    // Progress stays best-effort when storage is blocked or full.
    return;
  }
  if (typeof window !== "undefined") window.dispatchEvent(new Event(SALAH_PROGRESS_EVENT));
}

/**
 * Step to open a lesson on: a valid step from the link wins, then the saved step
 * of an unfinished lesson. A step that no longer exists starts the lesson over.
 */
export function resumeStepIndex(
  lesson: SalahLesson,
  saved: SalahLessonProgress | undefined,
  linkedStepSlug: string | null,
): number {
  const linked = stepIndex(lesson, linkedStepSlug);
  if (linked >= 0) return linked;
  if (!saved || saved.status === "completed") return 0;
  return Math.max(0, stepIndex(lesson, saved.step_slug));
}

export type SalahCourseSummary = {
  completed: number;
  total: number;
  /** The unfinished lesson to continue: the latest one in progress, else the first not started. */
  continueLesson: { slug: string; stepSlug: string | null } | null;
};

export function summarizeSalahProgress(
  lessons: SalahLessonOutline[],
  progress: SalahProgress,
): SalahCourseSummary {
  const known = lessons.filter((lesson) => progress.lessons[lesson.slug]);
  const completed = known.filter((lesson) => progress.lessons[lesson.slug]!.status === "completed").length;
  const inProgress = known
    .filter((lesson) => progress.lessons[lesson.slug]!.status === "in_progress")
    .sort((left, right) =>
      progress.lessons[right.slug]!.updated_at.localeCompare(progress.lessons[left.slug]!.updated_at));
  const current = inProgress[0];
  if (current) {
    const saved = progress.lessons[current.slug]!.step_slug;
    return {
      completed,
      total: lessons.length,
      continueLesson: { slug: current.slug, stepSlug: stepIndex(current, saved) >= 0 ? saved : null },
    };
  }
  const next = lessons.find((lesson) => !progress.lessons[lesson.slug]);
  return {
    completed,
    total: lessons.length,
    continueLesson: next ? { slug: next.slug, stepSlug: null } : null,
  };
}
