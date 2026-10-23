// Lesson progress of a step-by-step course (the prayer course, the tajweed course).
// Same shape as the app's `app_state` value and the backend's progress API:
// {"lessons": {"<lesson>": {"status", "step_slug", "content_version", "updated_at"}}}

export type LessonStatus = "in_progress" | "completed";

export type LessonProgress = {
  status: LessonStatus;
  step_slug: string;
  content_version: string;
  updated_at: string;
};

export type CourseProgress = {
  lessons: Record<string, LessonProgress>;
};

/** The part of a lesson that progress needs, small enough to pass to client components. */
export type LessonOutline = { slug: string; steps: { slug: string }[] };

type ProgressStorage = Pick<Storage, "getItem" | "setItem">;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function browserStorage(): ProgressStorage | null {
  try {
    return typeof window !== "undefined" ? window.localStorage : null;
  } catch {
    return null;
  }
}

/** Progress from its stored or received JSON; entries that do not fit are dropped. */
export function parseCourseProgress(raw: string | null, isLessonSlug: (slug: string) => boolean): CourseProgress {
  const empty: CourseProgress = { lessons: {} };
  if (!raw) return empty;
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return empty;
  }
  return progressFromJson(parsed, isLessonSlug);
}

export function progressFromJson(value: unknown, isLessonSlug: (slug: string) => boolean): CourseProgress {
  if (!isRecord(value) || !isRecord(value.lessons)) return { lessons: {} };
  const lessons: Record<string, LessonProgress> = {};
  for (const [slug, entry] of Object.entries(value.lessons)) {
    if (
      !isLessonSlug(slug)
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

export function readCourseProgress(
  storageKey: string,
  isLessonSlug: (slug: string) => boolean,
  storage: Pick<Storage, "getItem"> | null = browserStorage(),
): CourseProgress {
  if (!storage) return { lessons: {} };
  try {
    return parseCourseProgress(storage.getItem(storageKey), isLessonSlug);
  } catch {
    return { lessons: {} };
  }
}

/** Records the current step. A completed lesson stays completed when it is reopened. */
export function recordLessonStep(
  progress: CourseProgress,
  lessonSlug: string,
  stepSlug: string,
  contentVersion: string,
  { completed = false, now = new Date() }: { completed?: boolean; now?: Date } = {},
): CourseProgress {
  const previous = progress.lessons[lessonSlug];
  const status: LessonStatus = completed || previous?.status === "completed" ? "completed" : "in_progress";
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

export function writeCourseProgress(
  progress: CourseProgress,
  storageKey: string,
  event: string,
  storage: ProgressStorage | null = browserStorage(),
): void {
  if (!storage) return;
  try {
    storage.setItem(storageKey, JSON.stringify(progress));
  } catch {
    // Progress stays best-effort when storage is blocked or full.
    return;
  }
  if (typeof window !== "undefined") window.dispatchEvent(new Event(event));
}

/**
 * Two copies of the progress as one, as the backend merges them: a passed
 * lesson stays passed, otherwise the later record wins. The result is the same
 * whichever copy comes first.
 */
export function mergeCourseProgress(left: CourseProgress, right: CourseProgress): CourseProgress {
  const lessons: Record<string, LessonProgress> = { ...left.lessons };
  for (const [slug, entry] of Object.entries(right.lessons)) {
    const current = lessons[slug];
    if (!current) {
      lessons[slug] = entry;
      continue;
    }
    const later = entry.updated_at > current.updated_at ? entry : current;
    const completed = entry.status === "completed" || current.status === "completed";
    lessons[slug] = { ...later, status: completed ? "completed" : later.status };
  }
  return { lessons };
}

export function stepIndex(lesson: Pick<LessonOutline, "steps">, stepSlug: string | null | undefined): number {
  if (!stepSlug) return -1;
  return lesson.steps.findIndex((step) => step.slug === stepSlug);
}

/**
 * Step to open a lesson on: a valid step from the link wins, then the saved step
 * of an unfinished lesson. A step that no longer exists starts the lesson over.
 */
export function resumeStepIndex(
  lesson: Pick<LessonOutline, "steps">,
  saved: LessonProgress | undefined,
  linkedStepSlug: string | null,
): number {
  const linked = stepIndex(lesson, linkedStepSlug);
  if (linked >= 0) return linked;
  if (!saved || saved.status === "completed") return 0;
  return Math.max(0, stepIndex(lesson, saved.step_slug));
}

export type CourseSummary = {
  completed: number;
  total: number;
  /** The unfinished lesson to continue: the latest one in progress, else the first not started. */
  continueLesson: { slug: string; stepSlug: string | null } | null;
};

export function summarizeCourseProgress(lessons: LessonOutline[], progress: CourseProgress): CourseSummary {
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
