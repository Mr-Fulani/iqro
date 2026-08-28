import { revalidatePath, revalidateTag } from "next/cache";
import { isEditionCode, isUuid } from "./public-content";

const VERSION_PATTERN = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/;
const QURAN_ACTIONS = new Set(["published", "activated", "withdrawn"]);
const AUDIO_ACTIONS = new Set(["published", "withdrawn"]);
const DUA_ACTIONS = new Set(["published", "activated", "updated", "withdrawn"]);
const SOCIAL_PROFILE_ACTIONS = new Set(["created", "updated", "deleted"]);

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

type SocialProfilesChange = {
  type: "site.social_profiles.changed";
  action: string;
};

type DuaContentChange = {
  type: "dua.collection.changed";
  action: string;
  collection: string;
  version: string;
};

export type ContentChange =
  | QuranContentChange
  | AudioContentChange
  | DuaContentChange
  | SocialProfilesChange;

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

  if (value.type === "site.social_profiles.changed") {
    if (!hasExactKeys(value, ["type", "action"])) return null;
    if (typeof value.action !== "string" || !SOCIAL_PROFILE_ACTIONS.has(value.action)) {
      return null;
    }
    return value as SocialProfilesChange;
  }

  if (value.type === "dua.collection.changed") {
    if (!hasExactKeys(value, ["type", "action", "collection", "version"])) return null;
    if (
      typeof value.action !== "string" ||
      !DUA_ACTIONS.has(value.action) ||
      typeof value.collection !== "string" ||
      !/^[a-z0-9][a-z0-9-]{0,99}$/.test(value.collection) ||
      typeof value.version !== "string" ||
      !VERSION_PATTERN.test(value.version)
    ) return null;
    return value as DuaContentChange;
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
