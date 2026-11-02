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
import {
  parseAnnouncementFeed,
  parseAnnouncements,
  type Announcement,
  type AnnouncementFeedPage,
} from "./announcements";
import { parsePlayerBackgrounds } from "./player-backgrounds";
import type { PlayerBackground } from "./player-backgrounds";
import {
  groupRecitersByPerson,
  latestRecitationsByVariant,
  recitersWithPortraitsFirst,
  reciterSourcesForPerson,
  selectHomePopularReciters,
} from "./reciter-catalog";
import { parseSalahCourseDocument, type SalahCourseDocument } from "./salah";
import { parseTajweedCourseDocument, type TajweedCourseDocument } from "./tajweed-course";
import {
  parseBuiltInCovers,
  parseCourseDocument,
  parseCourseList,
  type BuiltInCourseCovers,
  type CourseDocumentResult,
  type CourseListItem,
} from "./thematic-courses";

export const PUBLIC_CONTENT_REVALIDATE_SECONDS = 3_600;

const PUBLIC_CONTENT_TIMEOUT_MS = 5_000;
const EDITION_CODE_PATTERN = /^[a-z0-9]+(?:[-_][a-z0-9]+)*$/;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export {
  isDuaCategorySlug,
  isDuaCollectionSlug,
} from "./public-route-params";

export class PublicContentNotFoundError extends Error {
  constructor(path: string) {
    super(`Published content was not found: ${path}`);
    this.name = "PublicContentNotFoundError";
  }
}

export function isEditionCode(value: string): boolean {
  return value.length <= 64 && EDITION_CODE_PATTERN.test(value);
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
  async (reciter: Reciter): Promise<Recitation[]> => {
    const sources = reciterSourcesForPerson(await getPublishedReciters(), reciter);
    const recitations = await Promise.all(
      (sources.length > 0 ? sources : [reciter]).map((source) => getPublishedRecitations(source.id)),
    );
    return latestRecitationsByVariant(recitations.flat(), "listen");
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

export type PublishedAudioInitialData = {
  /** Every published reciter source; the page groups them by person. */
  reciters: Reciter[];
  /** The default person and the first of its listening recitations. */
  reciterId: string;
  recitations: Recitation[];
  recitationId: string;
  tracks: AudioTrack[];
  editionCode: string;
  surahs: Surah[];
};

function withoutBiography(reciter: Reciter): Reciter {
  const shown = { ...reciter };
  delete shown.biography_ar;
  delete shown.biography_en;
  delete shown.biography_ru;
  delete shown.biography_tr;
  return shown;
}

export const getPublishedAudioInitialData = cache(
  async (): Promise<PublishedAudioInitialData> => {
    const reciters = await getPublishedReciters();
    const person = recitersWithPortraitsFirst(groupRecitersByPerson(reciters))[0];
    const recitations = person
      ? latestRecitationsByVariant(
          (
            await Promise.all(
              reciterSourcesForPerson(reciters, person).map((source) =>
                getPublishedRecitations(source.id),
              ),
            )
          ).flat(),
          "listen",
        )
      : [];
    const recitation = recitations[0];
    const [tracks, surahs] = recitation
      ? await Promise.all([
          getPublishedSurahTracks(recitation.id),
          getPublishedSurahs(recitation.quran_edition.code),
        ])
      : [[], []];
    return {
      // The page shows no biographies, and they would all travel with its HTML.
      reciters: reciters.map(withoutBiography),
      reciterId: person?.id ?? "",
      recitations,
      recitationId: recitation?.id ?? "",
      tracks,
      editionCode: recitation?.quran_edition.code ?? "",
      surahs,
    };
  },
);

export type PublishedQuranReaderPreview = {
  edition: QuranEdition;
  surahs: Surah[];
  /** The canonical text of Mushaf page 1, shown until the reader mounts. */
  firstPageAyahs: Ayah[];
};

export const getPublishedQuranReaderPreview = cache(
  async (): Promise<PublishedQuranReaderPreview | null> => {
    const editions = await getPublishedEditions();
    const edition = editions.find((item) => item.code === "madani-hafs") ?? editions[0];
    if (!edition) return null;
    const surahs = await getPublishedSurahs(edition.code);
    const firstPageAyahs = (
      await Promise.all(
        surahs
          .filter((surah) => surah.first_page === 1)
          .map((surah) => getPublishedAyahs(edition.code, surah.number)),
      )
    )
      .flat()
      .filter((ayah) => ayah.pages.includes(1));
    return { edition, surahs, firstPageAyahs };
  },
);

export type PublishedHomeInitialData = {
  editions: QuranEdition[];
  featuredSurahs: Surah[];
  featuredReciters: Reciter[];
};

export const getPublishedHomeInitialData = cache(async (): Promise<PublishedHomeInitialData> => {
  const [editions, reciters] = await Promise.all([getPublishedEditions(), getPublishedReciters()]);
  const surahs = editions[0] ? await getPublishedSurahs(editions[0].code) : [];
  return {
    editions,
    featuredSurahs: surahs.slice(0, 6),
    featuredReciters: selectHomePopularReciters(reciters),
  };
});

export const getPublishedSocialProfiles = cache(async (): Promise<SocialProfile[]> => {
  const profiles = await fetchPublishedJson<unknown>("/api/v1/site/social-profiles", [
    "site:social-profiles",
  ]);
  return assertSocialProfiles(profiles);
});

// The same answer for every visitor; read and closed marks are applied in the browser.
export const getPublishedActiveAnnouncements = cache(
  async (locale: SupportedLocale): Promise<Announcement[]> => {
    const payload = await fetchPublishedJson<unknown>(
      `/api/v1/announcements/active?platform=web&locale=${locale}`,
      ["site:announcements"],
    );
    return parseAnnouncements(payload);
  },
);

export const getPublishedAnnouncementFeed = cache(
  async (locale: SupportedLocale): Promise<AnnouncementFeedPage> => {
    const payload = await fetchPublishedJson<unknown>(
      `/api/v1/announcements?platform=web&locale=${locale}`,
      ["site:announcements"],
    );
    return parseAnnouncementFeed(payload);
  },
);

export const getPublishedPlayerBackgrounds = cache(async (): Promise<PlayerBackground[]> => {
  const backgrounds = await fetchPublishedJson<unknown>("/api/v1/player-backgrounds", [
    "audio:player-backgrounds",
  ]);
  return parsePlayerBackgrounds(assertArray(backgrounds as unknown[], "player background list"));
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
  async (
    locale: SupportedLocale,
    collection?: string,
  ): Promise<DuaCategory[]> => {
    const query = new URLSearchParams({ language: locale });
    if (collection) query.set("collection", collection);
    const categories = await fetchPublishedJson<DuaCategory[]>(
      `/api/v1/dua/categories?${query.toString()}`,
      [
        "dua:catalog",
        `dua:locale:${locale}`,
        ...(collection ? [`dua:collection:${collection}`] : []),
      ],
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
  async (
    locale: SupportedLocale,
    categorySlug: string,
    collectionSlug?: string,
  ): Promise<PublishedDuaCategoryData> => {
    const [collections, categories] = await Promise.all([
      fetchPublishedJson<DuaCollection[]>(
        `/api/v1/dua/collections?language=${encodeURIComponent(locale)}`,
        ["dua:catalog", `dua:locale:${locale}`],
      ),
      getPublishedDuaCategories(locale, collectionSlug),
    ]);
    const matchingCategories = categories.filter(
      (item) =>
        item.slug === categorySlug &&
        (!collectionSlug || item.collection === collectionSlug),
    );
    if (matchingCategories.length !== 1) {
      throw new PublicContentNotFoundError(`/api/v1/dua/categories/${categorySlug}`);
    }
    const category = matchingCategories[0]!;

    const entryQuery = new URLSearchParams({
      language: locale,
      collection: category.collection,
      category: categorySlug,
    });
    const entries = await fetchAllPublishedPages<DuaEntry>(
      "/api/v1/dua/entries",
      entryQuery,
      [
        "dua:catalog",
        `dua:locale:${locale}`,
        `dua:collection:${category.collection}`,
        `dua:category:${category.collection}:${categorySlug}`,
      ],
      "Dua category entry",
      100,
    );
    return {
      collection:
        assertArray(collections, "Dua collection list").find(
          (item) => item.slug === category.collection,
        ) ?? null,
      category,
      entries,
    };
  },
);

export const getPublishedDuaEntryByReference = cache(
  async (
    locale: SupportedLocale,
    collection: string,
    sourceNumber: number,
  ): Promise<DuaEntry> => {
    const query = new URLSearchParams({
      language: locale,
      collection,
      source_number: String(sourceNumber),
    });
    return fetchPublishedJson<DuaEntry>(
      `/api/v1/dua/entries/resolve?${query.toString()}`,
      [
        "dua:catalog",
        `dua:locale:${locale}`,
        `dua:collection:${collection}`,
        `dua:entry:${collection}:${sourceNumber}`,
      ],
    );
  },
);

export const getPublishedSalahCourse = cache(
  async (locale: SupportedLocale, slug: string): Promise<SalahCourseDocument> => {
    const document = await fetchPublishedJson<unknown>(
      `/api/v1/salah/courses/${encodeURIComponent(slug)}?language=${encodeURIComponent(locale)}`,
      [`salah:course:${slug}`, `salah:locale:${locale}`],
    );
    return parseSalahCourseDocument(document);
  },
);

export const getPublishedTajweedCourse = cache(
  async (locale: SupportedLocale, slug: string): Promise<TajweedCourseDocument> => {
    const document = await fetchPublishedJson<unknown>(
      `/api/v1/tajweed/courses/${encodeURIComponent(slug)}?language=${encodeURIComponent(locale)}`,
      [`tajweed:course:${slug}`, `tajweed:locale:${locale}`],
    );
    return parseTajweedCourseDocument(document);
  },
);

export const getPublishedCourseCatalog = cache(
  async (locale: SupportedLocale): Promise<{ courses: CourseListItem[]; builtIn: BuiltInCourseCovers }> => {
    const list = await fetchPublishedJson<unknown>(
      `/api/v1/courses?language=${encodeURIComponent(locale)}`,
      ["courses:catalog"],
    );
    return { courses: parseCourseList(list), builtIn: parseBuiltInCovers(list) };
  },
);

export const getPublishedCourse = cache(
  async (locale: SupportedLocale, slug: string): Promise<CourseDocumentResult> => {
    const document = await fetchPublishedJson<unknown>(
      `/api/v1/courses/${encodeURIComponent(slug)}?language=${encodeURIComponent(locale)}`,
      [`courses:course:${slug}`],
    );
    return parseCourseDocument(document);
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

export async function getPublishedPlayerBackgroundsOrEmpty(): Promise<PlayerBackground[]> {
  try {
    return await getPublishedPlayerBackgrounds();
  } catch (error) {
    // The bundled backgrounds keep the player usable while the catalog is unavailable.
    if (!(error instanceof PublicContentNotFoundError)) {
      console.error("Player backgrounds are temporarily unavailable", error);
    }
    return [];
  }
}
