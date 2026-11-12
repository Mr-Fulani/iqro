// The Names of Allah: the published list (docs/names-of-allah/README.md) and the
// reader's marks. A mark is a course-progress record keyed by the name's slug:
// "in_progress" — the needle has settled on the name («пройдено»),
// "completed" — the reader marked it as learned («выучено»).

import {
  browserStorage,
  parseCourseProgress,
  readCourseProgress,
  writeCourseProgress,
  type CourseProgress,
} from "./course-progress.ts";
import { trackCourseEvent, type CourseEvent } from "./course-feedback.ts";

export const NAMES_COLLECTION_SLUG = "asma-al-husna";
export const NAMES_PROGRESS_EVENT = "iqro:names-progress";

export type NameAyah = { surah: number; ayah: number; word: number | null };

export type DivineName = {
  slug: string;
  position: number;
  arabic: string;
  /** Empty in the Arabic document: the name itself is shown. */
  transliteration: string;
  meaning: string;
  tafsir: string;
  /** The book the explanation is from. */
  tafsir_source: string;
  tafsir_ref: string;
  ayah: NameAyah | null;
};

export type NamesDocument = {
  collection: {
    slug: string;
    version: string;
    language: string;
    list_source: string;
    tafsir_source: string;
  };
  names: DivineName[];
};

const SLUG = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;

export function isNameSlug(slug: string): boolean {
  return slug.length <= 64 && SLUG.test(slug);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function text(value: unknown, field: string): string {
  if (typeof value !== "string") throw new Error(`Names document: ${field} must be a string.`);
  return value;
}

function positive(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 1) {
    throw new Error(`Names document: ${field} must be a positive integer.`);
  }
  return value;
}

function parseAyah(value: unknown): NameAyah | null {
  if (value === null) return null;
  if (!isRecord(value)) throw new Error("Names document: ayah must be an object or null.");
  return {
    surah: positive(value.surah, "ayah.surah"),
    ayah: positive(value.ayah, "ayah.ayah"),
    word: value.word === null ? null : positive(value.word, "ayah.word"),
  };
}

/** The API answer, checked: a list that does not fit is an error, not a half-drawn wheel. */
export function parseNamesDocument(value: unknown): NamesDocument {
  if (!isRecord(value) || !isRecord(value.collection) || !Array.isArray(value.names) || !value.names.length) {
    throw new Error("Names document: collection and a non-empty names list are required.");
  }
  const { collection } = value;
  const names = value.names.map((item: unknown, index): DivineName => {
    if (!isRecord(item)) throw new Error("Names document: a name must be an object.");
    const slug = text(item.slug, "slug");
    if (!isNameSlug(slug)) throw new Error(`Names document: bad slug "${slug}".`);
    if (item.position !== index + 1) throw new Error("Names document: positions must run from 1 without gaps.");
    const arabic = text(item.arabic, "arabic");
    if (!arabic) throw new Error("Names document: arabic is required.");
    return {
      slug,
      position: index + 1,
      arabic,
      transliteration: text(item.transliteration, "transliteration"),
      meaning: text(item.meaning, "meaning"),
      tafsir: text(item.tafsir, "tafsir"),
      tafsir_source: text(item.tafsir_source, "tafsir_source"),
      tafsir_ref: text(item.tafsir_ref, "tafsir_ref"),
      ayah: parseAyah(item.ayah),
    };
  });
  if (new Set(names.map((name) => name.slug)).size !== names.length) {
    throw new Error("Names document: slugs must be unique.");
  }
  return {
    collection: {
      slug: text(collection.slug, "collection.slug"),
      version: text(collection.version, "collection.version"),
      language: text(collection.language, "collection.language"),
      list_source: text(collection.list_source, "collection.list_source"),
      tafsir_source: text(collection.tafsir_source, "collection.tafsir_source"),
    },
    names,
  };
}

/** The name as the interface language writes it; the Arabic interface shows the name itself. */
export function nameLabel(name: DivineName): string {
  return name.transliteration || name.arabic;
}

/** Arabic without vowel marks: small labels on the wheel stay legible. */
export function stripHarakat(arabic: string): string {
  return arabic.replace(/[ً-ْٰـ]/g, "");
}

// Marks -------------------------------------------------------------------

export function namesProgressStorageKey(collection: string = NAMES_COLLECTION_SLUG): string {
  return `names.progress.${collection}`;
}

export function parseNamesProgress(raw: string | null): CourseProgress {
  return parseCourseProgress(raw, isNameSlug);
}

export function readNamesProgress(
  collection: string = NAMES_COLLECTION_SLUG,
  storage: Pick<Storage, "getItem"> | null = browserStorage(),
): CourseProgress {
  return readCourseProgress(namesProgressStorageKey(collection), isNameSlug, storage);
}

export function writeNamesProgress(
  progress: CourseProgress,
  collection: string = NAMES_COLLECTION_SLUG,
  storage: Pick<Storage, "getItem" | "setItem"> | null = browserStorage(),
): void {
  writeCourseProgress(progress, namesProgressStorageKey(collection), NAMES_PROGRESS_EVENT, storage);
}

function withMark(
  progress: CourseProgress,
  slug: string,
  status: "in_progress" | "completed",
  version: string,
  now: Date,
): CourseProgress {
  return {
    lessons: {
      ...progress.lessons,
      [slug]: { status, step_slug: "", content_version: version, updated_at: now.toISOString() },
    },
  };
}

/** The needle settled on the name. A name already seen or learned keeps its mark. */
export function markNameSeen(progress: CourseProgress, slug: string, version: string, now = new Date()): CourseProgress {
  return progress.lessons[slug] ? progress : withMark(progress, slug, "in_progress", version, now);
}

/** «Выучено» on the card, or the mark taken back: the name stays seen. */
export function setNameLearned(
  progress: CourseProgress,
  slug: string,
  learned: boolean,
  version: string,
  now = new Date(),
): CourseProgress {
  return withMark(progress, slug, learned ? "completed" : "in_progress", version, now);
}

export function isNameLearned(progress: CourseProgress | null, slug: string): boolean {
  return progress?.lessons[slug]?.status === "completed";
}

/** How many names of the current list the needle has settled on. */
export function seenCount(progress: CourseProgress | null, names: readonly Pick<DivineName, "slug">[]): number {
  return progress ? names.filter((name) => name.slug in progress.lessons).length : 0;
}

// «Статистика курсов» (docs/names-of-allah/README.md, «Статистика») ------------
// The same anonymous counters a course sends: a name is a lesson. The section
// and each name count once per page view, however often a card is reopened.

export type NamesCounter = (event: "section_opened" | "lesson_opened" | "lesson_completed", name?: string) => void;

export function namesCounter(
  collection: string,
  track: (event: CourseEvent) => void = trackCourseEvent,
): NamesCounter {
  const counted = new Set<string>();
  return (event, name = "") => {
    const key = `${event}/${name}`;
    if (counted.has(key)) return;
    counted.add(key);
    track({ course: collection, lesson: name, event });
  };
}

// The wheel ---------------------------------------------------------------

/** The index of the name under the needle for a wheel position that may run past either end. */
export function wheelIndex(position: number, count: number): number {
  return ((Math.round(position) % count) + count) % count;
}

/** The nearest wheel position that shows `index`, going the short way round from `position`. */
export function wheelTarget(position: number, index: number, count: number): number {
  const from = Math.round(position);
  let delta = wheelIndex(index, count) - wheelIndex(from, count);
  if (delta > count / 2) delta -= count;
  if (delta < -count / 2) delta += count;
  return from + delta;
}
