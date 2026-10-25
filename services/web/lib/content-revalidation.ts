import { revalidatePath, revalidateTag } from "next/cache";
import { isEditionCode, isUuid } from "./public-content";
import { isDuaCollectionSlug } from "./public-route-params";
import { isSalahSlug } from "./salah";
import { isTajweedLessonSlug } from "./tajweed-course";
import { isCourseSlug, isQuizSlug } from "./thematic-courses";
import { SUPPORTED_LOCALES } from "./i18n";

const VERSION_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/;
const QURAN_ACTIONS = new Set(["published", "activated", "withdrawn"]);
const AUDIO_ACTIONS = new Set(["published", "withdrawn"]);
const RECITER_ACTIONS = new Set(["created", "updated"]);
const DUA_ACTIONS = new Set(["published", "activated", "updated", "withdrawn"]);
const SOCIAL_PROFILE_ACTIONS = new Set(["created", "updated", "deleted"]);
const COURSE_ACTIONS = new Set(["published", "activated", "withdrawn"]);
const THEMATIC_ACTIONS = new Set(["activated", "withdrawn"]);
const ANNOUNCEMENT_ACTIONS = new Set([
  "published",
  "withdrawn",
  "archived",
  "scheduled",
  "enabled",
  "disabled",
]);

type QuranContentChange = {
  type: "quran.edition.changed";
  action: string;
  edition: string;
  version: string;
};

type AudioContentChange = {
  type: "audio.recitation.changed";
  action: string;
  recitation_id: string;
  reciter_id: string;
  version: string;
};

type ReciterContentChange = {
  type: "audio.reciter.changed";
  action: string;
  reciter_id: string;
};

type SocialProfilesChange = {
  type: "site.social_profiles.changed";
  action: string;
};

type AnnouncementsChange = {
  type: "site.announcements.changed";
  action: string;
};

type DuaContentChange = {
  type: "dua.collection.changed";
  action: string;
  collection: string;
  version: string;
};

type SalahCourseChange = {
  type: "salah.course.changed";
  action: string;
  course: string;
  version: string;
};

type TajweedCourseChange = {
  type: "tajweed.course.changed";
  action: string;
  course: string;
  version: string;
};

type ThematicCourseChange = {
  type: "courses.course.changed";
  action: string;
  course: string;
  version: string;
};

/** Catalog cards changed outside a release: the cover of the prayer or tajweed course. */
type CourseCatalogChange = {
  type: "courses.catalog.changed";
  action: string;
};

type QuizChange = {
  type: "quizzes.quiz.changed";
  action: string;
  quiz: string;
  version: string;
};

export type ContentChange =
  | QuranContentChange
  | AudioContentChange
  | ReciterContentChange
  | DuaContentChange
  | SalahCourseChange
  | TajweedCourseChange
  | ThematicCourseChange
  | CourseCatalogChange
  | QuizChange
  | SocialProfilesChange
  | AnnouncementsChange;

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function hasExactKeys(value: Record<string, unknown>, keys: string[]): boolean {
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  return actual.length === expected.length && actual.every((key, index) => key === expected[index]);
}

export function parseContentChange(value: unknown): ContentChange | null {
  if (!isRecord(value) || typeof value.type !== "string") return null;

  if (value.type === "quran.edition.changed") {
    if (!hasExactKeys(value, ["type", "action", "edition", "version"])) return null;
    if (
      typeof value.action !== "string" ||
      !QURAN_ACTIONS.has(value.action) ||
      typeof value.edition !== "string" ||
      !isEditionCode(value.edition) ||
      typeof value.version !== "string" ||
      !VERSION_PATTERN.test(value.version)
    ) return null;
    return value as QuranContentChange;
  }

  if (value.type === "audio.recitation.changed") {
    if (
      !hasExactKeys(value, ["type", "action", "recitation_id", "reciter_id", "version"])
    ) return null;
    if (
      typeof value.action !== "string" ||
      !AUDIO_ACTIONS.has(value.action) ||
      typeof value.recitation_id !== "string" ||
      !isUuid(value.recitation_id) ||
      typeof value.reciter_id !== "string" ||
      !isUuid(value.reciter_id) ||
      typeof value.version !== "string" ||
      !VERSION_PATTERN.test(value.version)
    ) return null;
    return value as AudioContentChange;
  }

  if (value.type === "audio.reciter.changed") {
    if (!hasExactKeys(value, ["type", "action", "reciter_id"])) return null;
    if (
      typeof value.action !== "string" ||
      !RECITER_ACTIONS.has(value.action) ||
      typeof value.reciter_id !== "string" ||
      !isUuid(value.reciter_id)
    ) return null;
    return value as ReciterContentChange;
  }

  if (value.type === "site.social_profiles.changed") {
    if (!hasExactKeys(value, ["type", "action"])) return null;
    if (typeof value.action !== "string" || !SOCIAL_PROFILE_ACTIONS.has(value.action)) {
      return null;
    }
    return value as SocialProfilesChange;
  }

  if (value.type === "site.announcements.changed") {
    if (!hasExactKeys(value, ["type", "action"])) return null;
    if (typeof value.action !== "string" || !ANNOUNCEMENT_ACTIONS.has(value.action)) {
      return null;
    }
    return value as AnnouncementsChange;
  }

  if (value.type === "dua.collection.changed") {
    if (!hasExactKeys(value, ["type", "action", "collection", "version"])) return null;
    if (
      typeof value.action !== "string" ||
      !DUA_ACTIONS.has(value.action) ||
      typeof value.collection !== "string" ||
      !isDuaCollectionSlug(value.collection) ||
      typeof value.version !== "string" ||
      !VERSION_PATTERN.test(value.version)
    ) return null;
    return value as DuaContentChange;
  }

  if (value.type === "salah.course.changed") {
    if (!hasExactKeys(value, ["type", "action", "course", "version"])) return null;
    if (
      typeof value.action !== "string" ||
      !COURSE_ACTIONS.has(value.action) ||
      typeof value.course !== "string" ||
      !isSalahSlug(value.course) ||
      typeof value.version !== "string" ||
      !VERSION_PATTERN.test(value.version)
    ) return null;
    return value as SalahCourseChange;
  }

  if (value.type === "tajweed.course.changed") {
    if (!hasExactKeys(value, ["type", "action", "course", "version"])) return null;
    if (
      typeof value.action !== "string" ||
      !COURSE_ACTIONS.has(value.action) ||
      typeof value.course !== "string" ||
      !isTajweedLessonSlug(value.course) ||
      typeof value.version !== "string" ||
      !VERSION_PATTERN.test(value.version)
    ) return null;
    return value as TajweedCourseChange;
  }

  if (value.type === "courses.course.changed") {
    if (!hasExactKeys(value, ["type", "action", "course", "version"])) return null;
    if (
      typeof value.action !== "string" ||
      !THEMATIC_ACTIONS.has(value.action) ||
      typeof value.course !== "string" ||
      !isCourseSlug(value.course) ||
      typeof value.version !== "string" ||
      !VERSION_PATTERN.test(value.version)
    ) return null;
    return value as ThematicCourseChange;
  }

  if (value.type === "courses.catalog.changed") {
    if (!hasExactKeys(value, ["type", "action"]) || value.action !== "updated") return null;
    return value as CourseCatalogChange;
  }

  if (value.type === "quizzes.quiz.changed") {
    if (!hasExactKeys(value, ["type", "action", "quiz", "version"])) return null;
    if (
      typeof value.action !== "string" ||
      !THEMATIC_ACTIONS.has(value.action) ||
      typeof value.quiz !== "string" ||
      !isQuizSlug(value.quiz) ||
      typeof value.version !== "string" ||
      !VERSION_PATTERN.test(value.version)
    ) return null;
    return value as QuizChange;
  }

  return null;
}

function expireTag(tag: string): void {
  revalidateTag(tag, { expire: 0 });
}

export function revalidateContentChange(change: ContentChange): void {
  if (change.type === "site.social_profiles.changed") {
    expireTag("site:social-profiles");
    revalidatePath("/", "layout");
    return;
  }

  if (change.type === "site.announcements.changed") {
    expireTag("site:announcements");
    revalidatePath("/[locale]", "page");
    revalidatePath("/[locale]/news", "page");
    return;
  }

  if (change.type === "quran.edition.changed") {
    expireTag("quran:editions");
    expireTag(`quran:edition:${change.edition}`);
    revalidatePath("/[locale]/quran/[edition]", "page");
    revalidatePath("/[locale]/quran/[edition]/surah/[surah]", "page");
    revalidatePath("/[locale]/quran/[edition]/surah/[surah]/ayah/[ayah]", "page");
    revalidatePath("/sitemaps/quran/sitemap.xml");
    revalidatePath(
      `/sitemaps/quran/${encodeURIComponent(change.edition)}/${encodeURIComponent(change.version)}/sitemap.xml`,
    );
    return;
  }

  if (change.type === "dua.collection.changed") {
    expireTag("dua:catalog");
    revalidatePath("/[locale]/dua", "page");
    revalidatePath("/[locale]/dua/[category]", "page");
    revalidatePath("/[locale]/dua/[category]/categories/[topic]", "page");
    revalidatePath("/[locale]/dua/[category]/[sourceNumber]", "page");
    return;
  }

  if (change.type === "salah.course.changed") {
    expireTag(`salah:course:${change.course}`);
    for (const locale of SUPPORTED_LOCALES) expireTag(`salah:locale:${locale}`);
    revalidatePath("/[locale]/salah", "page");
    revalidatePath("/[locale]/salah/[lesson]", "page");
    return;
  }

  if (change.type === "tajweed.course.changed") {
    expireTag(`tajweed:course:${change.course}`);
    for (const locale of SUPPORTED_LOCALES) expireTag(`tajweed:locale:${locale}`);
    revalidatePath("/[locale]/tajweed", "page");
    revalidatePath("/[locale]/tajweed/[lesson]", "page");
    return;
  }

  if (change.type === "courses.catalog.changed") {
    expireTag("courses:catalog");
    revalidatePath("/[locale]/courses", "page");
    return;
  }

  if (change.type === "courses.course.changed") {
    expireTag("courses:catalog");
    expireTag(`courses:course:${change.course}`);
    // Quizzes link to course lessons.
    expireTag("quizzes:catalog");
    revalidatePath("/[locale]/courses", "page");
    revalidatePath("/[locale]/courses/[course]", "page");
    revalidatePath("/[locale]/courses/[course]/[lesson]", "page");
    return;
  }

  if (change.type === "quizzes.quiz.changed") {
    expireTag("quizzes:catalog");
    expireTag(`quizzes:quiz:${change.quiz}`);
    revalidatePath("/[locale]/quiz", "page");
    revalidatePath("/[locale]/quiz/[quiz]", "page");
    return;
  }

  if (change.type === "audio.reciter.changed") {
    expireTag("audio:reciters");
    expireTag(`audio:reciter:${change.reciter_id}`);
    expireTag("audio:recitations");
    revalidatePath("/[locale]/audio/reciters", "page");
    revalidatePath("/[locale]/audio/reciters/[reciter]", "page");
    revalidatePath("/[locale]/audio/recitations/[recitation]", "page");
    revalidatePath("/sitemaps/audio/sitemap.xml");
    return;
  }

  expireTag("audio:reciters");
  expireTag("audio:recitations");
  expireTag(`audio:reciter:${change.reciter_id}`);
  expireTag(`audio:recitation:${change.recitation_id}`);
  expireTag(`audio:tracks:${change.recitation_id}`);
  revalidatePath("/[locale]/audio/reciters", "page");
  revalidatePath("/[locale]/audio/reciters/[reciter]", "page");
  revalidatePath("/[locale]/audio/recitations/[recitation]", "page");
  revalidatePath("/sitemaps/audio/sitemap.xml");
  revalidatePath(
    `/sitemaps/audio/${encodeURIComponent(change.recitation_id)}/${encodeURIComponent(change.version)}/sitemap.xml`,
  );
}
