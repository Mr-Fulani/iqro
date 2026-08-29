import { cache } from "react";
import { SOCIAL_PLATFORM_CODES } from "./api";
import type {
  AudioTrack,
  Ayah,
  DuaCategory,
  DuaCollection,
  DuaEntry,
  PaginatedResponse,
  QuranEdition,
  Recitation,
  Reciter,
  SocialProfile,
  SupportedLocale,
  Surah,
} from "./api";
import { latestRecitationsByVariant, reciterPersonKey } from "./reciter-catalog";

export const PUBLIC_CONTENT_REVALIDATE_SECONDS = 3_600;

const PUBLIC_CONTENT_TIMEOUT_MS = 5_000;
const EDITION_CODE_PATTERN = /^[a-z0-9]+(?:[-_][a-z0-9]+)*$/;
const DUA_CATEGORY_SLUG_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export class PublicContentNotFoundError extends Error {
  constructor(path: string) {
    super(`Published content was not found: ${path}`);
    this.name = "PublicContentNotFoundError";
  }
}

export function isEditionCode(value: string): boolean {
  return value.length <= 64 && EDITION_CODE_PATTERN.test(value);
}

export function isDuaCategorySlug(value: string): boolean {
  return value.length <= 180 && DUA_CATEGORY_SLUG_PATTERN.test(value);
}

export function isUuid(value: string): boolean {
  return UUID_PATTERN.test(value);
}

function backendBaseUrl(): string {
  const configured =
    process.env.BACKEND_INTERNAL_URL?.trim() ||
    process.env.NEXT_PUBLIC_API_BASE_URL?.trim() ||
    "http://127.0.0.1:8000";
  const url = new URL(configured);

  if (url.protocol !== "http:" && url.protocol !== "https:") {
    throw new Error("BACKEND_INTERNAL_URL must use http or https");
  }
  if (url.username || url.password || url.search || url.hash) {
    throw new Error("BACKEND_INTERNAL_URL must not contain credentials, query, or hash");
  }

  return url.toString().replace(/\/$/, "");
}

async function fetchPublishedJson<T>(path: string, tags: string[]): Promise<T> {
  const response = await fetch(`${backendBaseUrl()}${path}`, {
    headers: {
      Accept: "application/json",
      "X-Forwarded-Proto": "https",
    },
    next: {
      revalidate: PUBLIC_CONTENT_REVALIDATE_SECONDS,
      tags,
    },
    signal: AbortSignal.timeout(PUBLIC_CONTENT_TIMEOUT_MS),
  });

  if (response.status === 404) throw new PublicContentNotFoundError(path);
  if (!response.ok) {
    throw new Error(`Published content API returned HTTP ${response.status} for ${path}`);
  }

  return response.json() as Promise<T>;
}

function assertArray<T>(value: T[], resource: string): T[] {
  if (!Array.isArray(value)) {
    throw new Error(`Published content API returned an invalid ${resource} payload`);
  }
  return value;
}

function assertSocialProfiles(value: unknown): SocialProfile[] {
  if (!Array.isArray(value)) {
    throw new Error("Published content API returned an invalid social profile list");
  }
  const supportedPlatforms = new Set<string>(SOCIAL_PLATFORM_CODES);
  const seenPlatforms = new Set<string>();
  for (const profile of value) {
    if (
      !profile ||
      typeof profile !== "object" ||
      typeof profile.platform !== "string" ||
      !supportedPlatforms.has(profile.platform) ||
      seenPlatforms.has(profile.platform) ||
      typeof profile.platform_name !== "string" ||
      !profile.platform_name.trim() ||
      typeof profile.display_name !== "string" ||
      typeof profile.url !== "string" ||
      typeof profile.sort_order !== "number" ||
      !Number.isInteger(profile.sort_order) ||
      profile.sort_order < 0 ||
      typeof profile.include_in_seo !== "boolean"
    ) {
      throw new Error("Published content API returned an invalid social profile item");
    }
    const url = new URL(profile.url);
    if (url.protocol !== "https:" || url.username || url.password) {
      throw new Error("Published content API returned an unsafe social profile URL");
    }
    seenPlatforms.add(profile.platform);
  }
  return value as SocialProfile[];
}

function assertPage<T>(value: PaginatedResponse<T>, resource: string): PaginatedResponse<T> {
  if (
    !value ||
    typeof value !== "object" ||
    !Array.isArray(value.results) ||
    (value.next !== null && typeof value.next !== "string")
  ) {
    throw new Error(`Published content API returned an invalid ${resource} page`);
  }
  return value;
}

async function fetchAllPublishedPages<T>(
  path: string,
  query: URLSearchParams,
  tags: string[],
  resource: string,
  pageSize: number,
): Promise<T[]> {
  const results: T[] = [];
  let cursor: string | null = null;

  for (let pageNumber = 0; pageNumber < 100; pageNumber += 1) {
    const currentQuery = new URLSearchParams(query);
    currentQuery.set("page_size", String(pageSize));
    if (cursor) currentQuery.set("cursor", cursor);
    const page = assertPage(
      await fetchPublishedJson<PaginatedResponse<T>>(
        `${path}?${currentQuery.toString()}`,
        tags,
      ),
      resource,
    );
    results.push(...page.results);
    if (!page.next) return results;

    const nextUrl = new URL(page.next, backendBaseUrl());
    if (nextUrl.pathname !== path) {
      throw new Error(`Published content API returned an invalid ${resource} cursor URL`);
    }
    cursor = nextUrl.searchParams.get("cursor");
    if (!cursor) {
      throw new Error(`Published content API returned an invalid ${resource} cursor`);
    }
  }

  throw new Error(`Published content API exceeded the ${resource} pagination limit`);
}

export const getPublishedEditions = cache(async (): Promise<QuranEdition[]> => {
  const editions = await fetchPublishedJson<QuranEdition[]>("/api/v1/quran/editions", [
    "quran:editions",
  ]);
  return assertArray(editions, "edition list");
});

export const getPublishedEdition = cache(async (edition: string): Promise<QuranEdition> => {
  return fetchPublishedJson<QuranEdition>(
    `/api/v1/quran/editions/${encodeURIComponent(edition)}`,
    ["quran:editions", `quran:edition:${edition}`],
  );
});

export const getPublishedSurahs = cache(async (edition: string): Promise<Surah[]> => {
  const surahs = await fetchPublishedJson<Surah[]>(
    `/api/v1/quran/editions/${encodeURIComponent(edition)}/surahs`,
    [`quran:edition:${edition}`, `quran:surahs:${edition}`],
  );
  return assertArray(surahs, "surah list");
});

export const getPublishedSurah = cache(
  async (edition: string, surah: number): Promise<Surah> => {
    return fetchPublishedJson<Surah>(
      `/api/v1/quran/editions/${encodeURIComponent(edition)}/surahs/${surah}`,
      [`quran:edition:${edition}`, `quran:surah:${edition}:${surah}`],
    );
  },
);

export const getPublishedAyahs = cache(
  async (edition: string, surah: number): Promise<Ayah[]> => {
    const ayahs = await fetchPublishedJson<Ayah[]>(
      `/api/v1/quran/editions/${encodeURIComponent(edition)}/surahs/${surah}/ayahs`,
      [`quran:surah:${edition}:${surah}`, `quran:ayahs:${edition}:${surah}`],
    );
    return assertArray(ayahs, "ayah list");
  },
);

export const getPublishedAyah = cache(
  async (edition: string, surah: number, ayah: number): Promise<Ayah> => {
    return fetchPublishedJson<Ayah>(
      `/api/v1/quran/editions/${encodeURIComponent(edition)}/ayahs/${surah}/${ayah}`,
      [`quran:surah:${edition}:${surah}`, `quran:ayah:${edition}:${surah}:${ayah}`],
    );
  },
);

export const getPublishedReciters = cache(async (): Promise<Reciter[]> => {
  return fetchAllPublishedPages<Reciter>(
    "/api/v1/reciters",
    new URLSearchParams(),
    ["audio:reciters"],
    "reciter catalog",
    100,
  );
});

export const getPublishedReciter = cache(async (reciter: string): Promise<Reciter> => {
  return fetchPublishedJson<Reciter>(`/api/v1/reciters/${encodeURIComponent(reciter)}`, [
    "audio:reciters",
    `audio:reciter:${reciter}`,
  ]);
});

export const getPublishedRecitations = cache(
  async (reciter?: string): Promise<Recitation[]> => {
    const query = new URLSearchParams();
    if (reciter) query.set("reciter_id", reciter);
    return fetchAllPublishedPages<Recitation>(
      "/api/v1/recitations",
      query,
      ["audio:recitations", ...(reciter ? [`audio:reciter:${reciter}`] : [])],
      "recitation catalog",
      100,
    );
  },
);

export const getPublishedRecitationsForPerson = cache(
  async (reciterSlug: string): Promise<Recitation[]> => {
    const personKey = reciterPersonKey(reciterSlug);
    const recitations = await getPublishedRecitations();
    return latestRecitationsByVariant(
      recitations.filter((recitation) => reciterPersonKey(recitation.reciter) === personKey),
    );
  },
);

export const getPublishedRecitation = cache(
  async (recitation: string): Promise<Recitation> => {
    return fetchPublishedJson<Recitation>(
      `/api/v1/recitations/${encodeURIComponent(recitation)}`,
      ["audio:recitations", `audio:recitation:${recitation}`],
    );
  },
);

export const getPublishedSurahTracks = cache(
  async (recitation: string): Promise<AudioTrack[]> => {
    return fetchAllPublishedPages<AudioTrack>(
      `/api/v1/recitations/${encodeURIComponent(recitation)}/tracks`,
      new URLSearchParams({ scope: "surah" }),
      [`audio:recitation:${recitation}`, `audio:tracks:${recitation}`],
      "audio track catalog",
      114,
    );
  },
);

export const getPublishedSocialProfiles = cache(async (): Promise<SocialProfile[]> => {
  const profiles = await fetchPublishedJson<unknown>("/api/v1/site/social-profiles", [
    "site:social-profiles",
  ]);
  return assertSocialProfiles(profiles);
});

export type PublishedDuaInitialData = {
  collections: DuaCollection[];
  categories: DuaCategory[];
};

export type PublishedDuaCategoryData = {
  collection: DuaCollection | null;
  category: DuaCategory;
  entries: DuaEntry[];
};

export const getPublishedDuaCategories = cache(
  async (locale: SupportedLocale): Promise<DuaCategory[]> => {
    const categories = await fetchPublishedJson<DuaCategory[]>(
      `/api/v1/dua/categories?language=${encodeURIComponent(locale)}`,
      ["dua:catalog", `dua:locale:${locale}`],
    );
    return assertArray(categories, "Dua category list");
  },
);

export const getPublishedDuaInitialData = cache(
  async (locale: SupportedLocale): Promise<PublishedDuaInitialData> => {
    const language = encodeURIComponent(locale);
    const [collections, categories] = await Promise.all([
      fetchPublishedJson<DuaCollection[]>(
        `/api/v1/dua/collections?language=${language}`,
        ["dua:catalog", `dua:locale:${locale}`],
      ),
      fetchPublishedJson<DuaCategory[]>(
        `/api/v1/dua/categories?language=${language}`,
        ["dua:catalog", `dua:locale:${locale}`],
      ),
    ]);
    return {
      collections: assertArray(collections, "Dua collection list"),
      categories: assertArray(categories, "Dua category list"),
    };
  },
);

export const getPublishedDuaCategoryData = cache(
  async (locale: SupportedLocale, categorySlug: string): Promise<PublishedDuaCategoryData> => {
    const [collections, categories] = await Promise.all([
      fetchPublishedJson<DuaCollection[]>(
        `/api/v1/dua/collections?language=${encodeURIComponent(locale)}`,
        ["dua:catalog", `dua:locale:${locale}`],
      ),
      getPublishedDuaCategories(locale),
    ]);
    const category = categories.find((item) => item.slug === categorySlug);
    if (!category) {
      throw new PublicContentNotFoundError(`/api/v1/dua/categories/${categorySlug}`);
    }

    const entries = await fetchAllPublishedPages<DuaEntry>(
      "/api/v1/dua/entries",
      new URLSearchParams({ language: locale, category: categorySlug }),
      ["dua:catalog", `dua:locale:${locale}`, `dua:category:${categorySlug}`],
      "Dua category entry",
      100,
    );
    return {
      collection: assertArray(collections, "Dua collection list")[0] ?? null,
      category,
      entries,
    };
  },
);

export async function getPublishedSocialProfilesOrEmpty(): Promise<SocialProfile[]> {
  try {
    return await getPublishedSocialProfiles();
  } catch (error) {
    console.error("Social profiles are temporarily unavailable", error);
    return [];
  }
}
