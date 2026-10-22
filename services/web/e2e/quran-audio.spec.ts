import { devices, expect, Page, test as base } from "@playwright/test";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import {
  alternateReciter,
  alternateRecitation,
  alternateTracks,
  paginated,
  recitation,
  recitationsMatching,
  reciter,
  reciterPeopleCount,
  reciters,
  surahPlayback,
  tracks,
  tracksFor,
} from "./fixtures/audio";
import { syntheticHeadingFont } from "./truetype-fixture";

const test = base.extend<{ nativeMedia: boolean }>({ nativeMedia: [false, { option: true }] });

const edition = {
  id: "00000000-0000-7000-8000-000000000001",
  code: "madani-hafs",
  name_ar: "مصحف المدينة",
  name_en: "Madani Mushaf",
  name_ru: "Мединский мусхаф",
  riwayah: "Hafs 'an Asim",
  source_name: "Test fixture",
  source_url: "https://example.test/quran",
  license_name: "Test fixture",
  license_url: "https://example.test/license",
  active_version: {
    id: "00000000-0000-7000-8000-000000000002",
    version: "1.0.0",
    checksum_sha256: "a".repeat(64),
    page_count: 604,
    surah_count: 114,
    juz_count: 30,
    hizb_count: 60,
    rub_el_hizb_count: 240,
    published_at: "2026-08-23T00:00:00Z",
  },
};

const surah = {
  id: "00000000-0000-7000-8000-000000000006",
  number: 6,
  name_ar: "الأنعام",
  name_en: "Al-An'am",
  name_ru: "Аль-Анам",
  revelation_type: "meccan",
  ayah_count: 165,
  first_page: 128,
};

const surahOne = {
  id: "00000000-0000-7000-8000-000000000001",
  number: 1,
  name_ar: "الفاتحة",
  name_en: "Al-Fatihah",
  name_ru: "Аль-Фатиха",
  revelation_type: "meccan",
  ayah_count: 7,
  first_page: 1,
};

const ayahs = [1, 2].map((number) => ({
  id: `00000000-0000-7000-8200-${String(number).padStart(12, "0")}`,
  edition_code: "madani-hafs",
  content_version: "1.0.0",
  surah_number: 6,
  number,
  text_uthmani: number === 1 ? "ٱلْحَمْدُ لِلَّهِ" : "هُوَ ٱلَّذِى خَلَقَكُم",
  juz_number: 7,
  hizb_number: 13,
  rub_el_hizb_number: 49,
  pages: [128],
}));

const translationEditions = [
  {
    source_id: 20,
    slug: "en-sahih-international",
    language_code: "en",
    language_name: "english",
    name: "Saheeh International",
    author_name: "Saheeh International",
    active_version: {
      sync_sequence: 1408,
      schema_version: "1",
      checksum_sha256: "e".repeat(64),
      ayah_count: 6236,
      published_at: "2026-08-28T00:00:00Z",
    },
    source: {
      name: "Quran.Foundation Content API",
      url: "https://api-docs.quran.foundation/docs/content_apis_versioned/4.0.0/translations/",
      license_name: "Quran.Foundation Developer Terms",
      license_url: "https://api-docs.quran.foundation/legal/developer-terms/",
      attribution: "Quran data provided by Quran Foundation.",
    },
  },
  {
    source_id: 45,
    slug: "quran.ru.kuliev",
    language_code: "ru",
    language_name: "russian",
    name: "Elmir Kuliev",
    author_name: "Elmir Kuliev",
    active_version: {
      sync_sequence: 1408,
      schema_version: "1",
      checksum_sha256: "d".repeat(64),
      ayah_count: 6236,
      published_at: "2026-08-28T00:00:00Z",
    },
    source: {
      name: "Quran.Foundation Content API",
      url: "https://api-docs.quran.foundation/docs/content_apis_versioned/4.0.0/translations/",
      license_name: "Quran.Foundation Developer Terms",
      license_url: "https://api-docs.quran.foundation/legal/developer-terms/",
      attribution: "Quran data provided by Quran Foundation.",
    },
  },
  {
    source_id: 78,
    slug: "ru-ministry-of-awqaf",
    language_code: "ru",
    language_name: "russian",
    name: "Ministry of Awqaf, Egypt",
    author_name: "Ministry of Awqaf, Egypt",
    active_version: {
      sync_sequence: 1408,
      schema_version: "1",
      checksum_sha256: "c".repeat(64),
      ayah_count: 6236,
      published_at: "2026-08-28T00:00:00Z",
    },
    source: {
      name: "Quran.Foundation Content API",
      url: "https://api-docs.quran.foundation/docs/content_apis_versioned/4.0.0/translations/",
      license_name: "Quran.Foundation Developer Terms",
      license_url: "https://api-docs.quran.foundation/legal/developer-terms/",
      attribution: "Quran data provided by Quran Foundation.",
    },
  },
  {
    source_id: 79,
    slug: "ru-abu-adel",
    language_code: "ru",
    language_name: "russian",
    name: "Abu Adel",
    author_name: "Abu Adel",
    active_version: {
      sync_sequence: 1408,
      schema_version: "1",
      checksum_sha256: "b".repeat(64),
      ayah_count: 6236,
      published_at: "2026-08-28T00:00:00Z",
    },
    source: {
      name: "Quran.Foundation Content API",
      url: "https://api-docs.quran.foundation/docs/content_apis_versioned/4.0.0/translations/",
      license_name: "Quran.Foundation Developer Terms",
      license_url: "https://api-docs.quran.foundation/legal/developer-terms/",
      attribution: "Quran data provided by Quran Foundation.",
    },
  },
];

const tafsirEditions = [
  {
    source_id: 16,
    slug: "ar-tafsir-muyassar",
    language_code: "ar",
    language_name: "arabic",
    name: "Tafsir Muyassar",
    author_name: "المیسر",
  },
  {
    source_id: 169,
    slug: "en-tafisr-ibn-kathir",
    language_code: "en",
    language_name: "english",
    name: "Ibn Kathir (Abridged)",
    author_name: "Hafiz Ibn Kathir",
  },
  {
    source_id: 170,
    slug: "ru-tafseer-al-saddi",
    language_code: "ru",
    language_name: "russian",
    name: "Al-Sa'di",
    author_name: "Saddi",
  },
].map((edition) => ({
  ...edition,
  active_version: {
    sync_sequence: 1408,
    schema_version: "1",
    checksum_sha256: "a".repeat(64),
    record_count: 6236,
    covered_ayah_count: 6236,
    published_at: "2026-08-28T00:00:00Z",
  },
  source: {
    name: "Quran.Foundation Content API",
    url: "https://api-docs.quran.foundation/docs/content_apis_versioned/4.0.0/tafsirs/",
    license_name: "Quran.Foundation Developer Terms",
    license_url: "https://api-docs.quran.foundation/legal/developer-terms/",
    attribution: "Quran data provided by Quran Foundation.",
  },
}));

const translatedAyahs = [
  { verse_key: "6:1", surah_number: 6, ayah_number: 1, text: "Хвала Аллаху", foot_notes: [] },
  { verse_key: "6:2", surah_number: 6, ayah_number: 2, text: "Он сотворил вас", foot_notes: [] },
];

const englishTranslatedAyahs = [
  {
    verse_key: "6:1",
    surah_number: 6,
    ayah_number: 1,
    text: "In the name of Allāh, [1] the Entirely Merciful, the Especially Merciful. [2]",
    foot_notes: [
      { id: 1, text: "Allāh is the proper name belonging only to the Almighty God." },
      { id: 2, text: "Ar-Raḥmān and ar-Raḥeem are names derived from mercy." },
    ],
  },
  {
    verse_key: "6:2",
    surah_number: 6,
    ayah_number: 2,
    text: "He created you.",
    foot_notes: [],
  },
];

function divisions(count: number) {
  return Array.from({ length: count }, (_, index) => ({
    id: `00000000-0000-7000-8400-${String(index + 1).padStart(12, "0")}`,
    number: index + 1,
    start_ayah: { id: ayahs[0].id, surah: 6, number: 1 },
    end_ayah: { id: ayahs[1].id, surah: 6, number: 2 },
    start_page: 128,
    end_page: 128,
  }));
}

const juz = divisions(30);
const hizb = divisions(60);
hizb[12] = {
  ...hizb[12],
  start_ayah: { id: ayahs[1].id, surah: 6, number: 2 },
  start_page: 129,
  end_page: 129,
};
const rubElHizb = divisions(240).map((division) => ({
  ...division,
  hizb_number: Math.floor((division.number - 1) / 4) + 1,
  quarter_number: ((division.number - 1) % 4) + 1,
}));

const foundationMushafs = [
  {
    source_id: 1,
    name: "QCF V2",
    default_font_name: "v2",
    rendering: {
      available: true,
      mode: "page-font",
      font_format: "woff2",
      font_url_template: "https://verses.quran.foundation/fonts/quran/hafs/v2/woff2/p{page}.woff2",
    },
  },
  {
    source_id: 5,
    name: "KFGQPC HAFS",
    default_font_name: "qpc-hafs",
    rendering: {
      available: true,
      mode: "unicode-font",
      font_format: "woff2",
      font_url: "https://verses.quran.foundation/fonts/quran/hafs/uthmanic_hafs/UthmanicHafs1Ver18.woff2",
    },
  },
  {
    source_id: 19,
    name: "QCF V4 Tajweed",
    default_font_name: "v4-tajweed",
    rendering: {
      available: true,
      mode: "page-font",
      font_format: "woff2",
      font_url_template: "https://verses.quran.foundation/fonts/quran/hafs/v4/colrv1/woff2/p{page}.woff2",
      color_format: "COLRv1",
    },
  },
].map((mushaf) => ({
  ...mushaf,
  rendering: { ...mushaf.rendering, version: 2 },
  description: `${mushaf.name} fixture`,
  qirat_name: "Hafs",
  pages_count: 604,
  lines_per_page: 15,
  mapping_mode: "reference",
  schema_version: "1",
  sync_sequence: 1,
  source_checksum_sha256: "c".repeat(64),
  last_synced_at: "2026-08-25T00:00:00Z",
  source: {
    name: "Quran.Foundation Content API",
    url: "https://api-docs.quran.foundation/docs/content_apis_versioned/4.0.0/resources-sync/",
    attribution: "Quran data provided by Quran Foundation.",
  },
}));

function foundationPage(sourceId: number, pageNumber: number) {
  const mushaf = foundationMushafs.find((item) => item.source_id === sourceId)!;
  const isUnicode = sourceId === 5;
  const fontUrl = sourceId === 1
    ? `https://verses.quran.foundation/fonts/quran/hafs/v2/woff2/p${pageNumber}.woff2`
    : sourceId === 19
      ? `https://verses.quran.foundation/fonts/quran/hafs/v4/colrv1/woff2/p${pageNumber}.woff2`
      : mushaf.rendering.font_url;
  return {
    mushaf_id: sourceId,
    qirat_name: "Hafs",
    font_name: mushaf.default_font_name,
    rendering: { ...mushaf.rendering, font_url: fontUrl },
    page_number: pageNumber,
    pages_count: 604,
    lines_per_page: 15,
    source_checksum_sha256: mushaf.source_checksum_sha256,
    verse_mapping: { "6": pageNumber === 129 ? "2" : "1-2" },
    first_verse_id: pageNumber === 129 ? 2 : 1,
    last_verse_id: 2,
    first_word_id: 1,
    last_word_id: 6,
    verses_count: pageNumber === 129 ? 1 : 2,
    words: [
      [1, 1, 3, 1, isUnicode ? "ٱلْحَمْدُ" : "ﱁ", "word"],
      [2, 1, 3, 2, isUnicode ? "لِلَّهِ" : "ﱂ", "end"],
      [3, 2, 3, 3, isUnicode ? "هُوَ" : "ﱃ", "word"],
      // A continued ayah can wrap position_in_line while position_in_page remains canonical.
      [4, 2, 4, 4, isUnicode ? "ٱلَّذِى" : "ﱄ", "word"],
      [5, 2, 4, 1, isUnicode ? "خَلَقَكُم" : "ﱅ", "word"],
      [6, 2, 4, 2, isUnicode ? "٢" : "ﱆ", "end"],
    ].filter((word) => pageNumber !== 129 || word[1] === 2)
    .map(([id, verseId, lineNumber, positionInLine, text, charType]) => ({
      id,
      word_id: id,
      verse_id: verseId,
      page_number: pageNumber,
      line_number: lineNumber,
      position_in_line: positionInLine,
      position_in_page: id,
      position_in_verse: positionInLine,
      char_type_id: null,
      char_type_name: charType,
      text,
      css_class: "",
      css_style: "",
    })),
  };
}

async function installApiMocks(page: Page, nativeMedia = false) {
  const testFont = await readFile(
    new URL("../node_modules/next/dist/next-devtools/server/font/geist-latin.woff2", import.meta.url),
  );
  await page.addInitScript((nativeMedia) => {
    const mediaSessionHandlers: Record<string, ((details?: { seekOffset?: number }) => void) | null> = {};
    Object.defineProperty(window, "__mediaSessionHandlers", {
      configurable: true,
      value: mediaSessionHandlers,
    });
    Object.defineProperty(window, "MediaMetadata", {
      configurable: true,
      value: class MediaMetadataMock {
        title?: string;
        artist?: string;
        album?: string;

        constructor(init: { title?: string; artist?: string; album?: string }) {
          Object.assign(this, init);
        }
      },
    });
    Object.defineProperty(navigator, "mediaSession", {
      configurable: true,
      value: {
        metadata: null,
        playbackState: "none",
        setActionHandler(action: string, handler: ((details?: { seekOffset?: number }) => void) | null) {
          mediaSessionHandlers[action] = handler;
        },
        setPositionState() {},
      },
    });
    if (nativeMedia) return;
    Object.defineProperty(HTMLMediaElement.prototype, "play", {
      configurable: true,
      value(this: HTMLMediaElement) {
        this.dispatchEvent(new Event("play"));
        return Promise.resolve();
      },
    });
    Object.defineProperty(HTMLMediaElement.prototype, "pause", {
      configurable: true,
      value(this: HTMLMediaElement) {
        this.dispatchEvent(new Event("pause"));
      },
    });
    Object.defineProperty(HTMLMediaElement.prototype, "load", {
      configurable: true,
      value(this: HTMLMediaElement) {
        queueMicrotask(() => this.dispatchEvent(new Event("loadedmetadata")));
      },
    });
    // Setting src still runs the browser's own loading on the empty mocked files;
    // its reset and decode error are not part of the stubbed playback above.
    for (const type of ["emptied", "error"]) {
      window.addEventListener(type, (event) => {
        if (event.target instanceof HTMLMediaElement) event.stopImmediatePropagation();
      }, true);
    }
  }, nativeMedia);

  await page.route("https://audio.example.test/**", (route) =>
    route.fulfill({ status: 200, contentType: "audio/mpeg", body: "" }),
  );
  await page.route("https://verses.quran.foundation/fonts/**", (route) =>
    route.fulfill({ status: 200, contentType: "font/woff2", body: testFont }),
  );
  await page.route("**/api/v1/**", async (route) => {
    const url = new URL(route.request().url());
    const path = url.pathname;

    const recitationPath = /^\/api\/v1\/recitations\/([^/]+)\/(tracks|surahs\/(\d+))$/.exec(path);
    const playback = recitationPath?.[3] ? surahPlayback(recitationPath[1], Number(recitationPath[3])) : undefined;

    if (path === "/api/v1/reciters") {
      await route.fulfill({ json: paginated(reciters) });
    } else if (path === "/api/v1/recitations") {
      await route.fulfill({ json: paginated(recitationsMatching(url.searchParams)) });
    } else if (recitationPath?.[2] === "tracks") {
      await route.fulfill({ json: paginated(tracksFor(recitationPath[1])) });
    } else if (playback) {
      await route.fulfill({ json: playback });
    } else if (path === `/api/v1/recitations/${recitation.id}/ayahs/6/2`) {
      await route.fulfill({
        json: {
          track: tracks[5],
          segment: {
            ayah_id: ayahs[1].id,
            surah_number: 6,
            ayah_number: 2,
            start_ms: 1_000,
            end_ms: 2_000,
          },
        },
      });
    } else if (path === "/api/v1/quran/translations") {
      const language = url.searchParams.get("language");
      await route.fulfill({
        json: translationEditions.filter((edition) => edition.language_code === language),
      });
    } else if (path === "/api/v1/quran/tafsirs") {
      const language = url.searchParams.get("language");
      await route.fulfill({
        json: tafsirEditions.filter((edition) => edition.language_code === language),
      });
    } else if (path === "/api/v1/quran/translations/45/surahs/6") {
      await route.fulfill({ json: translatedAyahs });
    } else if (path === "/api/v1/quran/translations/20/surahs/6") {
      await route.fulfill({ json: englishTranslatedAyahs });
    } else if (path === "/api/v1/quran/editions") {
      await route.fulfill({ json: [edition] });
    } else if (path === "/api/v1/quran/foundation/mushafs") {
      await route.fulfill({ json: foundationMushafs });
    } else if (/^\/api\/v1\/quran\/foundation\/mushafs\/\d+\/page-index$/.test(path)) {
      await route.fulfill({ json: {
        mushaf_id: Number(path.split("/")[6]), pages_count: 604,
        source_checksum_sha256: "c".repeat(64),
        verse_pages: { "1:1": [1], "6:1": [128], "6:2": [128, 129], "7:1": [151] },
      } });
    } else if (/^\/api\/v1\/quran\/editions\/madani-hafs\/ayahs\/\d+\/\d+$/.test(path)) {
      const surahNumber = Number(path.split("/")[7]);
      const ayahNumber = Number(path.split("/")[8]);
      await route.fulfill({ json: { ...ayahs[Math.min(ayahNumber - 1, ayahs.length - 1)],
        surah_number: surahNumber, number: ayahNumber,
        pages: [surahNumber === 1 ? 1 : surahNumber === 7 ? 151 : 128],
      } });
    } else if (/^\/api\/v1\/quran\/foundation\/mushafs\/\d+\/pages\/\d+$/.test(path)) {
      const parts = path.split("/");
      const sourceId = Number(parts[6]);
      const pageNumber = Number(parts[8]);
      await route.fulfill({ json: foundationPage(sourceId, pageNumber) });
    } else if (path === "/api/v1/quran/editions/madani-hafs/surahs") {
      await route.fulfill({ json: [surahOne, surah] });
    } else if (path === "/api/v1/quran/editions/madani-hafs/surahs/6/ayahs") {
      await route.fulfill({ json: ayahs });
    } else if (path === "/api/v1/quran/editions/madani-hafs/surahs/1/ayahs") {
      await route.fulfill({
        json: [{ ...ayahs[0], id: "00000000-0000-7000-8200-000000000001", surah_number: 1, pages: [1] }],
      });
    } else if (path === "/api/v1/quran/editions/madani-hafs/juz") {
      await route.fulfill({ json: juz });
    } else if (path === "/api/v1/quran/editions/madani-hafs/hizb") {
      await route.fulfill({ json: hizb });
    } else if (path === "/api/v1/quran/editions/madani-hafs/rub-el-hizb") {
      await route.fulfill({ json: rubElHizb });
    } else {
      await route.fulfill({
        status: 404,
        contentType: "application/problem+json",
        json: { detail: `Unhandled test endpoint: ${path}` },
      });
    }
  });
}

test.beforeEach(async ({ page, nativeMedia }) => {
  await installApiMocks(page, nativeMedia);
});

test("retired visual preference selects source 5 without requesting old artwork", async ({ page }) => {
  const retiredRequests: string[] = [];
  page.on("request", (request) => {
    if (/\/quran\/editions\/[^/]+\/pages\//.test(request.url())) retiredRequests.push(request.url());
  });
  await page.addInitScript(() => localStorage.setItem("iqro_quran_mushaf_variant_v1", "image"));
  await page.goto("/ru/quran?surah=6");
  await expect(page.getByLabel("Вариант Мусхафа")).toHaveValue("5");
  await expect(page.locator(".qf-mushaf-view")).toHaveAttribute("data-page-number", "128");
  await expect(page.locator('.mushaf-image, option[value="image"]')).toHaveCount(0);
  expect(retiredRequests).toEqual([]);
});

test("empty source catalog explains missing data and keeps canonical text accessible", async ({ page }) => {
  await page.route("**/api/v1/quran/foundation/mushafs", (route) => route.fulfill({json: []}));
  await page.goto("/ru/quran?surah=6");
  await expect(page.getByRole("status").filter({hasText: "Мусхафы ещё не загружены"})).toBeVisible();
  await expect(page.locator(".qf-mushaf-view, .mushaf-image")).toHaveCount(0);
  await page.getByRole("button", {name: "📜 Текст", exact: true}).click();
  await expect(page.locator(".ayah-card")).toHaveCount(2);
});

test("canonical text stays accessible while the source page is still loading", async ({ page }) => {
  let releasePage!: () => void;
  const pendingPage = new Promise<void>((resolve) => { releasePage = resolve; });
  const pageUrl = "**/api/v1/quran/foundation/mushafs/5/pages/128";
  await page.route(pageUrl, async (route) => {
    await pendingPage;
    await route.fallback();
  });
  try {
    await page.goto("/ru/quran?surah=6");
    await expect(page.getByLabel("Вариант Мусхафа")).toHaveValue("5");
    const loadingMessage = page.getByText("Загрузка страницы выбранного Мусхафа…", { exact: true });
    // The outgoing initial page can still contain the unavailable-state element.
    // Assert the requested loading state rather than their shared styling class.
    await expect(loadingMessage).toHaveCount(1);
    await expect(loadingMessage).toBeVisible();
    const textMode = page.getByRole("button", { name: "📜 Текст", exact: true });
    await expect(textMode).toBeEnabled();
    await textMode.click();
    await expect(page.locator(".ayah-card")).toHaveCount(2);
    const response = page.waitForResponse((item) => item.url().endsWith("/foundation/mushafs/5/pages/128"));
    releasePage();
    await response;
    await expect(page.locator(".ayah-card")).toHaveCount(2);
    await expect(page.locator(".qf-mushaf-view")).toHaveCount(0);
  } finally {
    releasePage();
  }
});

test("reading position synchronizes desktop fields and prepares the selected ayah without refetching", async ({ page }) => {
  let timingRequests = 0;
  page.on("request", (request) => { if (request.url().endsWith(`/recitations/${recitation.id}/surahs/6`)) timingRequests++; });
  await page.goto("/ru/quran?surah=1&page=128");
  const layout = page.locator(".quran-page-layout").filter({ visible: true });
  const audio = layout.locator("audio");
  await expect(layout.locator("#surah-navigation")).toHaveValue("6");
  await layout.locator('[data-ayah-key="6:2"]').last().click();
  await expect(layout.locator("#ayah-navigation")).toHaveValue("2");
  await expect(layout.locator("#juz-navigation")).toHaveValue("7");
  await expect(layout.locator("#hizb-navigation")).toHaveValue("13");
  await expect(layout.locator(".segmented-audio-summary strong")).toHaveText("Аят 6:2");
  await expect(audio).toHaveAttribute("src", tracks[5].asset.url);
  await expect(audio).toHaveJSProperty("currentTime", 1);
  await expect(layout.locator('select[id^="range-start-"]')).toHaveValue("2");
  await expect(layout.locator('select[id^="range-end-"]')).toHaveValue("2");
  await layout.locator('[data-ayah-key="6:1"]').click();
  await expect(audio).toHaveJSProperty("currentTime", 0);
  await layout.locator('[data-ayah-key="6:2"]').last().click();
  await expect(audio).toHaveJSProperty("currentTime", 1);
  expect(timingRequests).toBe(1);
  await expect(layout.locator(".qf-mushaf-view")).toHaveAttribute("data-page-number", "128");
});

test("reading position survives text and Mushaf switches without a selected ayah", async ({ page }) => {
  await page.goto("/ru/quran?page=129");
  const layout = page.locator(".quran-page-layout").filter({ visible: true });
  await expect(layout.locator(".qf-mushaf-view")).toHaveAttribute("data-page-number", "129");
  await expect(layout.locator("#surah-navigation")).toHaveValue("6");
  await page.getByRole("button", { name: "📜 Текст", exact: true }).click();
  await expect(page.locator("#quran-ayah-6-2")).toBeInViewport();
  await expect(layout.locator("#ayah-navigation")).toHaveValue("2");
  await page.getByRole("button", { name: /📖 Мусхаф/ }).click();
  await expect(layout.locator(".qf-mushaf-view")).toHaveAttribute("data-page-number", "129");
  await expect(layout.locator('[data-ayah-key="6:2"]').last()).toHaveClass(/is-selected/);
  await page.getByRole("button", { name: "📜 Текст", exact: true }).click();
  await layout.locator("#ayah-navigation").selectOption("1");
  await page.getByRole("button", { name: /📖 Мусхаф/ }).click();
  await expect(layout.locator(".qf-mushaf-view")).toHaveAttribute("data-page-number", "128");
  await expect(layout.locator('[data-ayah-key="6:1"]')).toHaveClass(/is-selected/);
});

test("an interrupted old play promise cannot report an error over the new selection", async ({ page }) => {
  await page.goto("/ru/quran?surah=6");
  const layout = page.locator(".quran-page-layout").filter({ visible: true });
  await layout.locator('[data-ayah-key="6:2"]').last().click();
  await page.evaluate(() => {
    let first = true;
    Object.defineProperty(HTMLMediaElement.prototype, "play", { configurable: true, value(this: HTMLMediaElement) {
      this.dispatchEvent(new Event("play"));
      if (!first) return Promise.resolve();
      first = false;
      return new Promise<void>((_resolve, reject) => {
        (window as unknown as { rejectOldPlay: () => void }).rejectOldPlay = () => reject(new DOMException("Interrupted by pause", "AbortError"));
      });
    } });
  });
  await layout.getByRole("button", { name: "▶ Аят 6:2", exact: true }).click();
  await layout.locator('[data-ayah-key="6:1"]').click();
  await layout.getByRole("button", { name: "▶ Аят 6:1", exact: true }).click();
  await page.evaluate(() => (window as unknown as { rejectOldPlay: () => void }).rejectOldPlay());
  await expect(layout.locator(".alert-error")).toHaveCount(0);
  await expect(layout.locator(".segmented-audio-summary .status-chip")).toHaveClass(/ok/);
  await expect(layout.locator("audio")).toHaveJSProperty("currentTime", 0);
});

test.describe("rotation recovery and native media", () => {
  test.use({ viewport: devices["Pixel 7"].viewport, userAgent: devices["Pixel 7"].userAgent,
    deviceScaleFactor: devices["Pixel 7"].deviceScaleFactor, isMobile: true, hasTouch: true, nativeMedia: true });

  test("rotation restores portrait sheet, glyphs and settings dimensions", async ({ page }) => {
    await page.addInitScript(() => localStorage.setItem("iqro_quran_mushaf_variant_v1", "1"));
    await page.goto("/ru/quran?surah=6");
    const layout = page.locator(".quran-page-layout").filter({ visible: true });
    const sheet = layout.locator(".qf-mushaf-sheet");
    const line = sheet.locator(".qf-mushaf-line").first();
    await expect(layout.locator(".qf-mushaf-view")).toHaveAttribute("data-font-status", "ready");
    const before = await sheet.boundingBox();
    const fontBefore = await line.evaluate((element) => getComputedStyle(element).fontSize);
    const portrait = page.viewportSize()!;
    for (let turn = 0; turn < 2; turn++) {
      await page.setViewportSize({ width: portrait.height, height: portrait.width });
      await expect(layout).toHaveAttribute("data-reader-orientation", "landscape");
      await expect.poll(async () => (await sheet.boundingBox())!.width).toBeCloseTo(portrait.height, 0);
      await page.setViewportSize(portrait);
      await expect(layout).toHaveAttribute("data-reader-orientation", "portrait");
      await expect.poll(async () => (await sheet.boundingBox())!.width).toBeCloseTo(before!.width, 0);
      await expect(line).toHaveCSS("font-size", fontBefore);
    }
    await page.getByRole("button", { name: "Настройки чтения", exact: true }).click();
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(portrait.width);
    await expect(page.locator(".mobile-navigation")).toBeVisible();
    await expect(layout).toHaveCSS("text-size-adjust", "100%");
  });

  test("native media starts a prepared ayah on the first landscape tap and stays usable after rotation", async ({ page }) => {
    // A real, decodable WAV exercises play/seek promises; only the catalogue is mocked.
    const samples = 8_000 * 4;
    const wav = Buffer.alloc(44 + samples * 2);
    wav.write("RIFF", 0); wav.writeUInt32LE(wav.length - 8, 4); wav.write("WAVEfmt ", 8);
    wav.writeUInt32LE(16, 16); wav.writeUInt16LE(1, 20); wav.writeUInt16LE(1, 22);
    wav.writeUInt32LE(8_000, 24); wav.writeUInt32LE(16_000, 28); wav.writeUInt16LE(2, 32); wav.writeUInt16LE(16, 34);
    wav.write("data", 36); wav.writeUInt32LE(samples * 2, 40);
    await page.route("https://audio.example.test/**", (route) => {
      const range = /bytes=(\d+)-(\d*)/.exec(route.request().headers().range ?? "");
      const start = range ? Number(range[1]) : 0;
      const end = range?.[2] ? Math.min(Number(range[2]), wav.length - 1) : wav.length - 1;
      return route.fulfill({ status: range ? 206 : 200, contentType: "audio/wav",
        headers: { "Accept-Ranges": "bytes", ...(range ? { "Content-Range": `bytes ${start}-${end}/${wav.length}` } : {}) },
        body: wav.subarray(start, end + 1) });
    });
    await page.setViewportSize({ width: 839, height: 393 });
    await page.goto("/ru/quran?surah=6");
    const layout = page.locator(".quran-page-layout").filter({ visible: true });
    const audio = layout.locator("audio");
    const actions = page.getByRole("toolbar");
    await expect.poll(() => audio.evaluate((element) => (element as HTMLAudioElement).readyState)).toBeGreaterThanOrEqual(1);
    await layout.locator('[data-ayah-key="6:2"]').first().tap();
    await expect(audio).toHaveJSProperty("currentTime", 1);
    await actions.getByRole("button", { name: "Воспроизвести аят 6:2", exact: true }).tap();
    await expect.poll(() => audio.evaluate((element) => (element as HTMLAudioElement).currentTime)).toBeGreaterThan(1.08);
    await expect(audio).toHaveJSProperty("paused", false);
    await page.setViewportSize({ width: 393, height: 839 });
    await expect(layout).toHaveAttribute("data-reader-orientation", "portrait");
    await expect(layout.locator(".alert-error")).toHaveCount(0);
    await expect.poll(() => audio.evaluate((element) => (element as HTMLAudioElement).paused)).toBe(true);
    await actions.getByRole("button", { name: "Воспроизвести аят 6:2", exact: true }).tap();
    await expect(audio).toHaveJSProperty("paused", false);
    await expect(layout.locator(".alert-error")).toHaveCount(0);
  });
});

test("reader shows a saved semantic translation in text and Mushaf modes", async ({ page }) => {
  await page.goto("/ru/quran?surah=6");
  await page.getByRole("button", { name: "📜 Текст", exact: true }).click();

  const translationToggle = page.locator("#translation-enabled").filter({ visible: true });
  await expect(translationToggle).toBeChecked();
  const translationSelect = page.getByLabel("Перевод и автор");
  await expect(translationSelect).toHaveValue("45");
  await expect(translationSelect.locator("option")).toHaveCount(3);
  await expect(translationSelect.locator('option[value="20"]')).toHaveCount(0);
  const tafsirSelect = page.getByLabel("Тафсир и автор");
  await expect(tafsirSelect).toHaveValue("170");
  await expect(tafsirSelect.locator("option")).toHaveCount(1);
  await expect(page.getByText("Хвала Аллаху", { exact: true })).toBeVisible();
  await expect(page.getByText("Он сотворил вас", { exact: true })).toBeVisible();

  await translationToggle.uncheck();
  await expect(page.getByText("Хвала Аллаху", { exact: true })).toHaveCount(0);
  await translationToggle.check();
  await page.getByRole("button", { name: /Мусхаф/ }).click();

  const translationPanel = page.locator(".mushaf-translation-panel");
  await expect(translationPanel.getByText("Хвала Аллаху", { exact: true })).toBeVisible();
  await expect(translationPanel.getByText("Он сотворил вас", { exact: true })).toBeVisible();
  await expect(translationPanel).toHaveAttribute("translate", "no");

  await page.setViewportSize({ width: 320, height: 760 });
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(
    await page.evaluate(() => document.documentElement.clientWidth),
  );
});

test("English reader keeps English translations and footnotes isolated", async ({ page }) => {
  await page.goto("/en/quran?surah=6");
  await page.getByRole("button", { name: "📜 Text", exact: true }).click();

  const translationSelect = page.getByLabel("Translation and author");
  await expect(translationSelect).toHaveValue("20");
  await expect(translationSelect.locator("option")).toHaveCount(1);
  await expect(translationSelect.locator('option[value="45"]')).toHaveCount(0);
  const firstAyah = page.locator(".ayah-card").first();
  await expect(
    firstAyah.getByText(
      "In the name of Allāh, [1] the Entirely Merciful, the Especially Merciful. [2]",
      { exact: true },
    ),
  ).toBeVisible();
  await firstAyah.getByText("Translator notes (2)", { exact: true }).click();
  await expect(
    firstAyah.getByText("Allāh is the proper name belonging only to the Almighty God.", {
      exact: true,
    }),
  ).toBeVisible();
});

test("arabic reader does not select an English translation automatically", async ({ page }) => {
  await page.goto("/ar/quran?surah=6");

  const translationToggle = page.locator("#translation-enabled").filter({ visible: true });
  const translationSelect = page.locator("#translation-edition").filter({ visible: true });
  await expect(translationToggle).not.toBeChecked();
  await expect(translationToggle).toBeDisabled();
  await expect(translationSelect).toHaveValue("");
  await expect(translationSelect).toBeDisabled();
  await expect(
    page
      .getByText(
        "النص العربي هو الأصل. الشرح العربي متاح بشكل مستقل في قسم التفسير، لذلك لا نختار ترجمة إنجليزية تلقائيًا.",
        { exact: true },
      )
      .filter({ visible: true }),
  ).toBeVisible();

  const tafsirSelect = page.getByLabel("التفسير والمؤلف");
  await expect(tafsirSelect).toHaveValue("16");
  await expect(tafsirSelect.locator("option")).toHaveCount(1);
  await expect(tafsirSelect.locator('option[value="169"]')).toHaveCount(0);
});

test("catalog loads all 114 surahs and starts the first track on one click", async ({ page }) => {
  await page.goto("/audio");

  await expect(page.getByRole("heading", { name: "Популярные чтецы" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Расширенный аудиоплеер" })).toHaveCount(0);
  const reciterCards = page.getByTestId("audio-reciter");
  await expect(reciterCards).toHaveCount(reciterPeopleCount);
  await expect(reciterCards.first()).toHaveAttribute("aria-pressed", "true");
  await expect(reciterCards.first().getByTestId("reciter-avatar")).toBeVisible();
  const player = page.getByTestId("global-audio-player");
  await expect(player.getByText("Сейчас в плеере", { exact: true })).toHaveCount(0);
  await expect(player.getByText("Расширенный аудиоплеер", { exact: true })).toHaveCount(0);
  await expect(player.getByLabel("Быстрая смена чтеца")).toHaveValue(reciter.id);
  expect((await player.boundingBox())!.height).toBeLessThan(130);
  await expect(player.getByRole("button", { name: "Развернуть плеер", exact: true })).toBeVisible();
  await expect(player.getByLabel("Режим повтора")).toBeHidden();

  await player.getByRole("button", { name: "Развернуть плеер", exact: true }).click();
  await expect(page.getByLabel("Режим повтора")).toBeVisible();
  await expect(page.getByLabel("Режим повтора")).toBeDisabled();
  await expect(page.getByLabel("Скорость воспроизведения")).toBeVisible();
  await expect(page.getByLabel("Таймер сна")).toBeVisible();
  await expect(page.getByRole("button", { name: "▶ Воспроизвести диапазон" })).toBeDisabled();
  await player.getByRole("button", { name: "Свернуть плеер", exact: true }).click();

  await expect(page.getByText("Найдено треков: 114")).toBeVisible();
  // The Mushaf calligraphy replaces the text once the heading font loads.
  const firstRow = page.locator(".track-row").first();
  await expect(
    firstRow
      .getByText("الفاتحة", { exact: true })
      .or(firstRow.getByRole("img", { name: "الفاتحة", exact: true })),
  ).toBeVisible();
  const listenButtons = page.getByRole("button", { name: "Слушать", exact: true });
  await expect(listenButtons).toHaveCount(114);

  await listenButtons.first().click();

  await expect(player.locator(".audio-player-bar")).toBeVisible();
  await expect(player.locator(".audio-player-bar audio")).toHaveAttribute(
    "src",
    tracks[0].asset.url,
  );
  await expect(page.getByRole("button", { name: "▶ Играет", exact: true })).toBeVisible();

  expect((await player.boundingBox())!.height).toBeLessThan(130);
  await expect(player.getByRole("button", { name: "Развернуть плеер", exact: true })).toBeVisible();
  await expect(player.getByRole("link", { name: "Открыть аудио", exact: true })).toHaveCount(0);

  await player.getByRole("button", { name: "Развернуть плеер", exact: true }).click();
  await expect(player.getByLabel("Режим повтора")).toBeVisible();
  expect((await player.boundingBox())!.height).toBeGreaterThan(200);
});

test("switching the reciter stops the old source and prepares the same surah for the new voice", async ({ page }) => {
  await page.goto("/audio");
  await page.getByRole("button", { name: "Слушать", exact: true }).first().click();

  const player = page.getByTestId("global-audio-player");
  const audio = player.locator("audio");
  await expect(audio).toHaveAttribute("src", tracks[0].asset.url);
  await expect(player.getByText("Воспроизводится", { exact: true })).toBeVisible();

  await page.locator("#audio-reciter-select").selectOption(alternateReciter.id);

  await expect(player.getByLabel("Быстрая смена чтеца")).toHaveValue(alternateReciter.id);
  await expect(audio).toHaveAttribute("src", alternateTracks[0].asset.url);
  await expect(player.getByText("Готово к воспроизведению", { exact: true })).toBeVisible();
  await expect(player.locator(".segmented-audio-summary .kpi-desc")).toContainText(
    "Махмуд Халиль Аль-Хусари",
  );

  await audio.evaluate((element) => void (element as HTMLAudioElement).play());
  await expect(player.getByText("Воспроизводится", { exact: true })).toBeVisible();

  await player.getByLabel("Быстрая смена чтеца").selectOption(reciter.id);
  await expect(page.locator("#audio-reciter-select")).toHaveValue(reciter.id);
  await expect(audio).toHaveAttribute("src", tracks[0].asset.url);
  await expect(player.getByText("Готово к воспроизведению", { exact: true })).toBeVisible();
});

test("audio keeps playing on ordinary navigation and pauses when opening Quran", async ({ page }) => {
  await page.goto("/audio");
  await page.getByRole("button", { name: "Слушать", exact: true }).first().click();

  const player = page.getByTestId("global-audio-player");
  const audio = player.locator("audio");
  await expect(player).toBeVisible();
  await expect(page.getByLabel("Режим повтора")).toBeHidden();
  const compactAudioPagePlayerBox = await player.boundingBox();
  expect(compactAudioPagePlayerBox).not.toBeNull();
  expect(compactAudioPagePlayerBox!.height).toBeLessThan(130);
  await expect(page.getByText("Воспроизводится", { exact: true })).toBeVisible();
  await audio.evaluate((element) => {
    (element as HTMLAudioElement).currentTime = 12.5;
  });

  await page.locator('.brand-link[href="/ru"]').click();

  await expect(page).toHaveURL("/ru");
  await expect(player).toBeVisible();
  const compactPlayerBox = await player.boundingBox();
  expect(compactPlayerBox).not.toBeNull();
  expect(compactPlayerBox!.height).toBeLessThan(130);
  await expect(player.getByText("Воспроизводится", { exact: true })).toBeVisible();
  await expect(audio).toHaveAttribute("src", tracks[0].asset.url);
  expect(await audio.evaluate((element) => (element as HTMLAudioElement).currentTime)).toBe(12.5);

  await page.locator('.app-menu a[href="/ru/quran"]').click();
  await expect(page).toHaveURL("/ru/quran");
  await expect(player.getByText("Пауза при переходе · позиция сохранена", { exact: true })).toBeVisible();
  expect(await audio.evaluate((element) => (element as HTMLAudioElement).currentTime)).toBe(12.5);

  await audio.evaluate((element) => void (element as HTMLAudioElement).play());
  await expect(player.getByText("Воспроизводится", { exact: true })).toBeVisible();
  await page.locator('.brand-link[href="/ru"]').click();
  await expect(page).toHaveURL("/ru");
  await expect(player.getByText("Воспроизводится", { exact: true })).toBeVisible();

  await player.getByRole("button", { name: "Развернуть плеер", exact: true }).click();
  await expect(player.getByLabel("Режим повтора")).toBeVisible();
  expect((await player.boundingBox())!.height).toBeGreaterThan(200);
  await expect(player.getByRole("link", { name: "Открыть аудио", exact: true })).toHaveCount(0);

  await player.getByRole("button", { name: "Свернуть плеер", exact: true }).click();
  await expect.poll(async () => (await player.boundingBox())!.height).toBeLessThan(130);
  await expect(player.getByRole("link", { name: "Открыть аудио", exact: true })).toBeVisible();

  await expect(player.getByText("Воспроизводится", { exact: true })).toBeVisible();
});

test("global recitation and Dua audio take turns without overlapping", async ({ page }) => {
  // Keep the Dua media request pending: an empty or aborted body makes Chromium
  // fire a trusted media error right after the mocked play(), which resets the
  // Dua button and races the assertions below.
  await page.route("**/audio/ar/1.mp3", () => {});
  await page.goto("/audio");
  await page.getByRole("button", { name: "Слушать", exact: true }).first().click();

  const player = page.getByTestId("global-audio-player");
  await expect(player.getByText("Воспроизводится", { exact: true })).toBeVisible();
  await page.locator('.app-menu a[href="/ru/dua"]').click();
  await expect(page).toHaveURL("/ru/dua");
  await expect(player.getByText("Пауза при переходе · позиция сохранена", { exact: true })).toBeVisible();

  await page.locator(".dua-topic-card").click();
  await expect(page).toHaveURL("/ru/dua/topics/sleep");
  // The topic lists its chapters; a chapter reads as cards with their audio.
  await page.locator(".dua-chapter-row").first().click();
  await expect(page).toHaveURL("/ru/dua/hisn-al-muslim/categories/waking-up");
  const duaAudio = page.locator("audio.dua-audio");
  const duaButton = page.locator(".dua-action-play").first();
  await duaButton.click();
  await expect(duaAudio).toHaveAttribute(
    "src",
    "https://www.hisnmuslim.com/audio/ar/1.mp3",
  );
  await duaAudio.evaluate((element) => void (element as HTMLAudioElement).play());
  await expect(duaButton).toHaveAccessibleName("Приостановить аудио");
  await expect(player.getByText("Воспроизводится", { exact: true })).toHaveCount(0);

  const globalAudio = player.locator("audio");
  await globalAudio.evaluate((element) => void (element as HTMLAudioElement).play());
  await expect(player.getByText("Воспроизводится", { exact: true })).toBeVisible();
  await expect(duaButton).toHaveAccessibleName("Прослушать ду’а");

  await duaButton.click();
  await expect(duaButton).toHaveAccessibleName("Приостановить аудио");
  await expect(player.getByText("Воспроизводится", { exact: true })).toHaveCount(0);
});

test("expanded player sound bars sway while the recitation plays and fade out otherwise", async ({ page }) => {
  await page.goto("/audio");
  await page.getByRole("button", { name: "Слушать", exact: true }).first().click();

  const player = page.getByTestId("global-audio-player");
  const audio = player.locator("audio");
  await expect(player.getByText("Воспроизводится", { exact: true })).toBeVisible();
  // The bars belong to the expanded player only.
  await expect(player.getByTestId("player-equalizer")).toHaveCount(0);

  await player.getByRole("button", { name: "Развернуть плеер", exact: true }).click();
  const equalizer = player.getByTestId("player-equalizer");
  const playStates = () => equalizer.evaluate((element) =>
    [...new Set(element.getAnimations({ subtree: true }).map((animation) => animation.playState))]);
  await expect.poll(() => equalizer.evaluate((element) => element.getAnimations({ subtree: true }).length))
    .toBe(9);
  await expect(equalizer).toHaveCSS("opacity", "1");
  await expect.poll(playStates).toEqual(["running"]);

  // As in the app: a 400 ms fade on pause, then the sway stops.
  await audio.evaluate((element) => (element as HTMLAudioElement).pause());
  await expect(equalizer).toHaveCSS("transition-duration", "0.4s");
  await expect(equalizer).toHaveCSS("opacity", "0");
  await expect.poll(playStates).toEqual(["paused"]);

  await audio.evaluate((element) => void (element as HTMLAudioElement).play());
  await expect(equalizer).toHaveCSS("opacity", "1");
  await expect.poll(playStates).toEqual(["running"]);
  await audio.evaluate((element) => element.dispatchEvent(new Event("waiting")));
  await expect(equalizer).toHaveCSS("opacity", "0");
  await expect.poll(playStates).toEqual(["paused"]);
  await audio.evaluate((element) => element.dispatchEvent(new Event("playing")));
  await expect(equalizer).toHaveCSS("opacity", "1");
  await expect.poll(playStates).toEqual(["running"]);

  await player.getByRole("button", { name: "Свернуть плеер", exact: true }).click();
  await expect(player.getByTestId("player-equalizer")).toHaveCount(0);
});

test.describe("sound bars with native media", () => {
  test.use({ nativeMedia: true });

  test("sound bars fade out when the next surah's file fails to load", async ({ page }) => {
    // The first surah is a real, decodable WAV; the second one is missing. Switching
    // calls load(), which drops the pending pause event, and the broken file never plays.
    const samples = 8_000 * 30;
    const wav = Buffer.alloc(44 + samples * 2);
    wav.write("RIFF", 0); wav.writeUInt32LE(wav.length - 8, 4); wav.write("WAVEfmt ", 8);
    wav.writeUInt32LE(16, 16); wav.writeUInt16LE(1, 20); wav.writeUInt16LE(1, 22);
    wav.writeUInt32LE(8_000, 24); wav.writeUInt32LE(16_000, 28); wav.writeUInt16LE(2, 32); wav.writeUInt16LE(16, 34);
    wav.write("data", 36); wav.writeUInt32LE(samples * 2, 40);
    await page.route("https://audio.example.test/**", (route) => {
      if (route.request().url() === tracks[1].asset.url) return route.fulfill({ status: 404, body: "" });
      const range = /bytes=(\d+)-(\d*)/.exec(route.request().headers().range ?? "");
      const start = range ? Number(range[1]) : 0;
      const end = range?.[2] ? Math.min(Number(range[2]), wav.length - 1) : wav.length - 1;
      return route.fulfill({ status: range ? 206 : 200, contentType: "audio/wav",
        headers: { "Accept-Ranges": "bytes", ...(range ? { "Content-Range": `bytes ${start}-${end}/${wav.length}` } : {}) },
        body: wav.subarray(start, end + 1) });
    });
    await page.goto("/audio");
    await page.getByRole("button", { name: "Слушать", exact: true }).first().click();

    const player = page.getByTestId("global-audio-player");
    const audio = player.locator("audio");
    await expect.poll(() => audio.evaluate((element) => (element as HTMLAudioElement).paused)).toBe(false);
    await player.getByRole("button", { name: "Развернуть плеер", exact: true }).click();
    const equalizer = player.getByTestId("player-equalizer");
    const playStates = () => equalizer.evaluate((element) =>
      [...new Set(element.getAnimations({ subtree: true }).map((animation) => animation.playState))]);
    await expect(equalizer).toHaveCSS("opacity", "1");
    await expect.poll(playStates).toEqual(["running"]);

    // The expanded player covers the list, so the click goes to the button directly.
    await page.locator(".track-row").nth(1).getByRole("button", { name: "Слушать", exact: true })
      .dispatchEvent("click");
    await expect(audio).toHaveAttribute("src", tracks[1].asset.url);
    await expect.poll(() => audio.evaluate((element) => (element as HTMLAudioElement).error?.code)).toBe(4);
    await expect(audio).toHaveJSProperty("paused", true);
    await expect(equalizer).toHaveCSS("opacity", "0");
    await expect.poll(playStates).toEqual(["paused"]);
  });
});

test("persistent player is the app's mini player on phones and tablets and the dock on desktop", async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 812 });
  await page.goto("/audio");
  await page.getByRole("button", { name: "Слушать", exact: true }).first().click();

  const bar = page.getByTestId("mobile-audio-player");
  const audio = bar.locator("audio");
  await expect(bar).toBeVisible();
  await expect(page.getByTestId("global-audio-player")).toHaveCount(0);
  await expect(audio).toHaveAttribute("src", tracks[0].asset.url);
  await expect(bar.getByRole("button", { name: "Поставить на паузу", exact: true })).toBeVisible();
  expect((await bar.boundingBox())!.height).toBe(66);
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(
    await page.evaluate(() => document.documentElement.clientWidth),
  );
  await audio.evaluate((element) => {
    (element as HTMLAudioElement).currentTime = 12.5;
  });

  await page.locator('.brand-link[href="/ru"]').click();
  await expect(page).toHaveURL("/ru");
  await expect(bar).toBeVisible();
  expect((await bar.boundingBox())!.y + 66)
    .toBeLessThanOrEqual((await page.locator(".mobile-navigation").boundingBox())!.y - 5);
  expect(await audio.evaluate((element) => (element as HTMLAudioElement).currentTime)).toBe(12.5);

  // Tablets show the bottom navigation, so they get the bar as well.
  await page.setViewportSize({ width: 768, height: 1024 });
  await expect(bar).toBeVisible();
  expect((await bar.boundingBox())!.height).toBe(66);
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(768);

  // The desktop dock takes over around the same <audio> element.
  await page.setViewportSize({ width: 900, height: 900 });
  const dock = page.getByTestId("global-audio-player");
  await expect(dock).toBeVisible();
  await expect(bar).toHaveCount(0);
  const dockAudio = dock.locator("audio");
  await expect(dockAudio).toHaveAttribute("src", tracks[0].asset.url);
  expect(await dockAudio.evaluate((element) => (element as HTMLAudioElement).currentTime)).toBe(12.5);
  const settingsButton = dock.getByRole("button", { name: "Повтор, диапазон и таймер", exact: true });
  const audioLink = dock.getByRole("link", { name: "Открыть аудио", exact: true });
  await expect(audioLink).toBeVisible();
  expect((await settingsButton.boundingBox())!.width).toBeGreaterThan(100);
  expect(Math.abs((await settingsButton.boundingBox())!.y - (await dockAudio.boundingBox())!.y)).toBeLessThan(12);
});

test("reader defaults to Mushaf, selects every fragment and starts ayah playback", async ({ page }) => {
  await page.goto("/quran?surah=6");
  await expect(page.getByRole("button", { name: /Мусхаф/ })).toHaveClass(/btn-primary/);

  const recitationSelect = page.getByLabel("Чтец Quran.Foundation");
  await expect(recitationSelect.locator("option")).toHaveCount(2);
  const ayahRegions = page.getByRole("button", { name: "Аят 6:2", exact: true });
  await expect(ayahRegions).toHaveCount(2);

  await ayahRegions.first().click();
  await expect(ayahRegions.first()).toHaveClass(/is-selected/);
  await expect(ayahRegions.nth(1)).toHaveClass(/is-selected/);

  await page.getByRole("button", { name: "▶ Аят 6:2", exact: true }).click();

  await expect(page.locator('[data-ayah-key="6:2"].is-playing')).toHaveCount(2);
  await expect(ayahRegions.first()).toHaveClass(/is-playing/);
  await expect(ayahRegions.nth(1)).toHaveClass(/is-playing/);
  await expect(page.locator(".mushaf-audio-now-playing audio[src]")).toHaveAttribute(
    "src",
    tracks[5].asset.url,
  );
  await expect(page.getByText(/Махер аль-Муайкли · Мурратталь · аят 6:2/)).toBeVisible();
  await expect(page.getByText("Воспроизводится", { exact: true })).toBeVisible();
});

test("Quran review deep link opens and highlights its first ayah", async ({ page }) => {
  await page.goto("/quran?surah=6&ayah=2");

  await expect(page.getByRole("button", { name: /Мусхаф/ })).toHaveClass(/btn-primary/);
  await expect(page.locator(".qf-mushaf-view")).toHaveAttribute("data-page-number", "128");
  const linkedAyah = page.getByRole("button", { name: "Аят 6:2", exact: true });
  await expect(linkedAyah).toHaveCount(2);
  await expect(linkedAyah.first()).toHaveClass(/is-selected/);
  await expect(linkedAyah.last()).toHaveClass(/is-selected/);
});

test("legacy Quran bookmark deep link opens its saved Mushaf page", async ({ page }) => {
  await page.goto("/quran?page=128");

  await expect(page.getByRole("button", { name: /Мусхаф/ })).toHaveClass(/btn-primary/);
  await expect(page.locator(".qf-mushaf-view")).toHaveAttribute("data-page-number", "128");
});

test("displayed source page saves canonical position before server debounce and restores it", async ({ page }) => {
  const storageKey = "iqro_quran_reading_position_v1:madani-hafs";
  await page.route("**/api/v1/quran/foundation/mushafs/5/pages/151", (route) =>
    route.fulfill({ json: { ...foundationPage(5, 151), verse_mapping: { "7": "1" },
      words: foundationPage(5, 151).words.filter((word) => word.verse_id === 1) } }),
  );
  await page.clock.install({ time: new Date("2026-08-28T08:00:00Z") });
  await page.goto("/ru/quran?surah=6");
  await expect(page.locator(".qf-mushaf-view")).toHaveAttribute("data-page-number", "128");
  await page.clock.pauseAt(new Date("2026-08-28T09:00:00Z"));
  const pageJump = page.getByRole("spinbutton", { name: /Страница Мусхафа/ });
  await pageJump.fill("151");
  await pageJump.press("Enter");
  await expect(page.locator(".qf-mushaf-view")).toHaveAttribute("data-page-number", "151");
  await expect.poll(() => page.evaluate((key) => JSON.parse(localStorage.getItem(key) || "null"), storageKey))
    .toMatchObject({ pageNumber: 151, surahNumber: 7, ayahNumber: 1 });
  await page.clock.resume();
  await page.goto("/ru");
  await page.goto("/ru/quran");
  await expect(pageJump).toHaveValue("151");
  await expect(page.locator(".qf-mushaf-view")).toHaveAttribute("data-page-number", "151");
});

test("after-prayer reader resumes the Mushaf and saves the actual page count once", async ({ page }) => {
  let checkInPayload: Record<string, unknown> | null = null;
  const automaticSessionPayloads: Record<string, unknown>[] = [];
  const session = {
    token_type: "Bearer",
    access_token: "after-prayer-access-token",
    expires_in: 900,
    access_expires_at: "2026-08-28T12:15:00Z",
    user: {
      id: "00000000-0000-7000-8000-000000000611",
      status: "active",
      preferred_locale: "ru",
      email: "reader@example.com",
      deletion_requested_at: null,
      deletion_scheduled_for: null,
    },
    device: {
      id: "00000000-0000-7000-8000-000000000612",
      platform: "web",
      locale: "ru",
      app_version: "1.0.0",
      bootstrap_generation: 1,
    },
  };
  const position = {
    id: "00000000-0000-7000-8000-000000000613",
    edition_code: "madani-hafs",
    page_number: 128,
    ayah: { id: ayahs[0].id, surah_number: 6, ayah_number: 1 },
    progress_percent: "21.19",
    revision: 3,
    last_read_at: "2026-08-28T09:00:00Z",
    client_updated_at: "2026-08-28T09:00:00Z",
  };

  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ json: session }));
  await page.route("**/api/v1/me/reading-position/madani-hafs", async (route) => {
    if (route.request().method() === "GET") {
      return route.fulfill({ json: position });
    }
    const payload = route.request().postDataJSON() as Record<string, unknown>;
    return route.fulfill({ json: { ...position, ...payload, revision: 4 } });
  });
  await page.route("**/api/v1/me/prayer-reading-check-ins", (route) => {
    checkInPayload = route.request().postDataJSON() as Record<string, unknown>;
    return route.fulfill({
      status: 201,
      json: {
        id: checkInPayload.id,
        prayer: checkInPayload.prayer,
        local_date: checkInPayload.local_date,
        timezone_name: checkInPayload.timezone_name,
        pages: checkInPayload.amount,
        metric: checkInPayload.metric, amount: String(checkInPayload.amount),
        reading_session_id: checkInPayload.session_id,
        revision: 1,
        client_updated_at: checkInPayload.client_updated_at,
        device_id: session.device.id,
        created_at: "2026-08-28T09:10:00Z",
        updated_at: "2026-08-28T09:10:00Z",
      },
    });
  });
  await page.route("**/api/v1/me/reading-sessions/automatic", (route) => {
    automaticSessionPayloads.push(route.request().postDataJSON() as Record<string, unknown>);
    return route.fulfill({ status: 201, json: {} });
  });

  await page.clock.install({ time: new Date("2026-08-28T09:00:00Z") });
  await page.clock.pauseAt(new Date("2026-08-28T09:00:01Z"));
  await page.goto(
    "/quran?surah=6&mode=after-prayer&prayer=fajr&prayer_date=2026-08-28"
      + "&prayer_timezone=Europe%2FIstanbul&prayer_target=2&prayer_credited=0",
  );

  const guided = page.getByTestId("prayer-reading-session");
  await expect(guided.getByRole("heading", { name: "После намаза Фаджр" })).toBeVisible();
  await expect(page.locator(".qf-mushaf-view")).toHaveAttribute("data-page-number", "128");
  await expect(guided.getByLabel("Прочитано — стр.")).toHaveValue("1");
  await expect(guided.getByTestId("prayer-reading-active-time")).toContainText("0:00");
  await page.clock.runFor(60_000);
  await expect(guided.getByTestId("prayer-reading-active-time")).toContainText("1:00");
  expect(automaticSessionPayloads).toHaveLength(0);
  await guided.getByLabel("Прочитано — стр.").fill("3");
  await guided.getByRole("button", { name: "Завершить и сохранить" }).click();

  await expect(guided.getByText("Сохранено: 3 стр. после намаза Фаджр.")).toBeVisible();
  expect(checkInPayload).toMatchObject({
    prayer: "fajr",
    local_date: "2026-08-28",
    timezone_name: "Europe/Istanbul",
    metric: "pages", amount: 3,
  });
  expect(automaticSessionPayloads).toHaveLength(0);
  await page.clock.runFor(60_000);
  expect(automaticSessionPayloads).toHaveLength(0);

  await page.setViewportSize({ width: 320, height: 760 });
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(
    await page.evaluate(() => document.documentElement.clientWidth),
  );
});

test("mushaf switcher renders all supported Quran.Foundation font variants", async ({ page }) => {
  await page.goto("/quran?surah=6");
  await page.getByRole("button", { name: /Мусхаф/ }).click();

  const variant = page.getByLabel("Вариант Мусхафа");
  await expect(variant.locator("option")).toHaveCount(3);
  await expect(variant.locator("option")).toHaveText([
    "QCF V2 · Hafs",
    "KFGQPC HAFS · Hafs",
    "QCF V4 Tajweed · Hafs",
  ]);

  for (const sourceId of ["1", "5", "19"]) {
    await variant.selectOption(sourceId);
    const view = page.locator(`.qf-mushaf-view[data-mushaf-id="${sourceId}"]`);
    await expect(view).toHaveAttribute("data-page-number", "128");
    await expect(view).toHaveAttribute("data-font-status", "ready");
    const sheet = view.locator(".qf-mushaf-sheet");
    await expect(sheet).toHaveAttribute("dir", "rtl");
    await expect(sheet).toHaveAttribute("lang", "ar");
    await expect(sheet).toHaveAttribute("translate", "no");
    await expect(sheet.locator(".qf-mushaf-line")).toHaveCount(2);
    await expect(sheet.locator('.qf-mushaf-line[data-line-number="3"]'))
      .toHaveAttribute("data-display-line-number", "3");
    await expect(sheet.locator('.qf-mushaf-line[data-line-number="4"]'))
      .toHaveAttribute("data-display-line-number", "4");
    await expect(view.getByText("سُورَةُ الأنعام", { exact: true })).toBeVisible();
    await expect(view.getByText("بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ", { exact: true })).toBeVisible();
    const secondAyahWords = view.getByRole("button", { name: "Аят 6:2", exact: true });
    await expect(secondAyahWords).toHaveCount(2);
    await secondAyahWords.first().click();
    await expect(secondAyahWords.first()).toHaveClass(/is-selected/);
    await expect(secondAyahWords.last()).toHaveClass(/is-selected/);
    if (sourceId === "5") {
      await expect(sheet.locator('.qf-mushaf-line[data-line-number="4"] .qf-mushaf-word'))
        .toHaveText(["ٱلَّذِى", "خَلَقَكُم", "٢"]);
    }
  }

  await page.reload();
  const restoredVariant = page.getByLabel("Вариант Мусхафа");
  await expect(restoredVariant).toHaveValue("19");
  await page.getByRole("button", { name: /Мусхаф/ }).click();
  await expect(page.locator('.qf-mushaf-view[data-mushaf-id="19"]')).toHaveAttribute(
    "data-page-number",
    "128",
  );

  await restoredVariant.selectOption("5");
  await page.reload();
  await expect(page.getByLabel("Вариант Мусхафа")).toHaveValue("5");
  await page.getByRole("button", { name: /Мусхаф/ }).click();
  await expect(page.locator(".qf-mushaf-view")).toBeVisible();
});

const tajweedTexts = (ru: string, en: string) => ({ ru, en, ar: en, tr: en });
const tajweedReference = {
  version: "test",
  review_status: "pending_teacher_review",
  languages: ["ru", "en", "ar", "tr"],
  rules: [
    {
      code: "idgham_wo_ghunnah",
      arabic_name: "الإدغام بغير غنة",
      color: "#A3A5A5",
      name: tajweedTexts("Идгам без гунны", "Idgham without ghunnah"),
      why: tajweedTexts("Нун с сукуном перед ل или ر.", "A noon with sukun before ل or ر."),
      how: tajweedTexts("Сразу читайте удвоенную ل.", "Go straight to a doubled ل."),
      variants: [],
    },
    {
      code: "qalaqah",
      arabic_name: "القلقلة",
      color: "#2FADFF",
      name: tajweedTexts("Калькаля", "Qalqalah"),
      why: tajweedTexts("Буква калькали с сукуном.", "A qalqalah letter with sukun."),
      how: tajweedTexts("Лёгкий отскок.", "A light bounce."),
      variants: [{
        code: "stop",
        name: tajweedTexts("при остановке", "when stopping"),
        why: tajweedTexts("Буква в конце слова.", "The letter ends the word."),
        how: tajweedTexts("Отскок отчётливее.", "A clearer bounce."),
      }],
    },
    {
      code: "madda_normal",
      arabic_name: "المد الطبيعي",
      color: "#CE9E00",
      name: tajweedTexts("Мадд табии", "Natural madd"),
      why: tajweedTexts("Буква мадда.", "A madd letter."),
      how: tajweedTexts("2 хараката.", "2 counts."),
      variants: [{
        code: "silah_sughra",
        name: tajweedTexts("Мадд силя сугра", "Minor silah"),
        why: tajweedTexts("Хаъ местоимения между огласованными буквами.", "The pronoun ha."),
        how: tajweedTexts("2 хараката при слитном чтении.", "2 counts when reading on."),
      }],
    },
  ],
};

// 112:4 markup on the fixture page: the idgham runs from word 3 into word 4.
const tajweedPage128 = {
  page_number: 128,
  rules: ["idgham_wo_ghunnah", "qalaqah", "madda_normal"],
  ayahs: [
    {
      verse_key: "6:1", surah_number: 6, ayah_number: 1, page_number: 128, rules: ["qalaqah"],
      words: [{ position: 1, text: "أَحَدُۢ", rules: [{ code: "qalaqah", start: 4, end: 5, variant: "stop" }] }],
    },
    {
      verse_key: "6:2", surah_number: 6, ayah_number: 2, page_number: 128,
      rules: ["idgham_wo_ghunnah", "madda_normal"],
      words: [
        { position: 3, text: "يَكُن", rules: [{ code: "idgham_wo_ghunnah", start: 3, end: 5, joins_next: true }] },
        {
          position: 4,
          text: "لَّهُۥ",
          rules: [
            { code: "idgham_wo_ghunnah", start: 0, end: 1, joins_previous: true },
            { code: "madda_normal", start: 5, end: 6, variant: "silah_sughra" },
          ],
        },
      ],
    },
  ],
  source: foundationMushafs[2].source,
};

async function installTajweedMocks(page: Page) {
  await page.addInitScript(() => localStorage.setItem("iqro_quran_mushaf_variant_v1", "19"));
  await page.route("**/api/v1/quran/tajweed/**", (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path === "/api/v1/quran/tajweed/rules") return route.fulfill({ json: tajweedReference });
    if (path === "/api/v1/quran/tajweed/pages/128") return route.fulfill({ json: tajweedPage128 });
    // Once imported, every Mushaf page has markup; a 404 would mean none is imported.
    const pageNumber = Number(path.split("/").at(-1));
    return route.fulfill({ json: { ...tajweedPage128, page_number: pageNumber, rules: [], ayahs: [] } });
  });
  await page.route(`**/api/v1/recitations/${recitation.id}/ayahs/6/2`, (route) => route.fulfill({
    json: {
      track: tracks[5],
      segment: {
        ayah_id: ayahs[1].id,
        surah_number: 6,
        ayah_number: 2,
        start_ms: 1_000,
        end_ms: 2_000,
        words: [[3, 1_000, 1_400], [4, 1_400, 1_900]],
      },
    },
  }));
}

test("tajweed Mushaf explains a tapped word, its letters and its sound", async ({ page }) => {
  await installTajweedMocks(page);
  await page.goto("/ru/quran?surah=6");
  const view = page.locator('.qf-mushaf-view[data-mushaf-id="19"]');
  await expect(view).toHaveAttribute("data-font-status", "ready");
  const legend = page.getByTestId("tajweed-legend");
  await expect(legend.getByRole("button")).toHaveText(["Идгам без гунны", "Калькаля", "Мадд табии"]);

  await view.locator('.qf-mushaf-word.has-tajweed[data-word-position="3"]').click();
  await expect(view.getByRole("button", { name: "Аят 6:2", exact: true }).first()).toHaveClass(/is-selected/);
  const card = page.getByRole("dialog", { name: "Таджвид в слове" });
  await expect(card).toBeVisible();
  const idgham = card.locator('.tajweed-rule[data-rule="idgham_wo_ghunnah"]');
  await expect(idgham.getByRole("heading", { name: "Идгам без гунны" })).toBeVisible();
  // Zero-width joiners keep the coloured letters connected; the words are unchanged.
  expect((await idgham.locator(".tajweed-letters").textContent())?.replaceAll("\u200d", "")).toBe("يَكُن لَّهُۥ");
  await expect(idgham.getByText("Нун с сукуном перед ل или ر.")).toBeVisible();
  await expect(idgham.getByText("Сразу читайте удвоенную ل.")).toBeVisible();
  await expect(card.getByText("Пояснения проходят проверку у преподавателя таджвида.")).toBeVisible();

  const slow = card.getByRole("button", { name: "Медленнее, 0,75×" });
  await slow.click();
  await expect(slow).toHaveAttribute("aria-pressed", "true");
  await card.getByRole("button", { name: "Послушать фрагмент" }).click();
  await expect(card.getByRole("button", { name: "Остановить" })).toBeVisible();
  expect(await card.locator("audio").evaluate((audio: HTMLAudioElement) => ({
    rate: audio.playbackRate,
    start: audio.currentTime,
    src: audio.getAttribute("src"),
  }))).toEqual({ rate: 0.75, start: 1, src: tracks[5].asset.url });

  await page.keyboard.press("Escape");
  await expect(card).toHaveCount(0);
  await expect(view.locator('.qf-mushaf-ayah-fragment[data-ayah-key="6:2"]').first()).toBeFocused();

  // The second word shows the same idgham and its own silah.
  await view.locator('.qf-mushaf-word.has-tajweed[data-word-position="4"]').click();
  await expect(card.getByRole("heading", { name: "Мадд табии · Мадд силя сугра" })).toBeVisible();
  expect((await card.locator('.tajweed-rule[data-rule="idgham_wo_ghunnah"] .tajweed-letters').textContent())
    ?.replaceAll("\u200d", "")).toBe("يَكُن لَّهُۥ");
  await page.keyboard.press("Escape");

  await legend.getByRole("button", { name: "Калькаля" }).click();
  const ruleCard = page.getByRole("dialog", { name: "Правило таджвида" });
  await expect(ruleCard.getByText("Где на этой странице")).toBeVisible();
  await expect(ruleCard.getByText("Буква калькали с сукуном.")).toBeVisible();
  await ruleCard.getByRole("button", { name: /6:1/ }).click();
  const wordCard = page.getByRole("dialog", { name: "Таджвид в слове" });
  await expect(wordCard.getByRole("heading", { name: "Калькаля · при остановке" })).toBeVisible();
  await expect(wordCard.getByText("Буква в конце слова.")).toBeVisible();
  // This reciter has no word timing for 6:1, so the card offers nothing to play.
  await expect(wordCard.getByTestId("tajweed-listen")).toHaveCount(0);
  // A tap on the shade around the card closes it.
  await page.mouse.click(4, 4);
  await expect(wordCard).toHaveCount(0);
});

// The media stubs above never leave `paused`; these tests follow it through play and pause.
async function trackPausedMedia(page: Page) {
  await page.evaluate(() => {
    const playing = new WeakSet<HTMLMediaElement>();
    const play = HTMLMediaElement.prototype.play;
    const pause = HTMLMediaElement.prototype.pause;
    Object.defineProperty(HTMLMediaElement.prototype, "paused", {
      configurable: true,
      get(this: HTMLMediaElement) { return !playing.has(this); },
    });
    HTMLMediaElement.prototype.play = function (this: HTMLMediaElement) {
      playing.add(this);
      return play.call(this);
    };
    HTMLMediaElement.prototype.pause = function (this: HTMLMediaElement) {
      playing.delete(this);
      pause.call(this);
    };
  });
}

async function openBreakdown(page: Page, path: string, name: RegExp) {
  await installTajweedMocks(page);
  await page.goto(path);
  const view = page.locator('.qf-mushaf-view[data-mushaf-id="19"]');
  await expect(view).toHaveAttribute("data-font-status", "ready");
  await trackPausedMedia(page);
  // The ayah number selects the ayah; its menu offers the breakdown.
  await view.locator('.qf-mushaf-ayah-fragment[data-ayah-key="6:2"] .qf-mushaf-word.is-ayah-end').click();
  const open = page.getByTestId("tajweed-breakdown-open");
  await open.click();
  const breakdown = page.getByRole("dialog", { name });
  await expect(breakdown).toBeVisible();
  return { open, breakdown };
}

test("tajweed breakdown walks an ayah rule by rule and sums it up", async ({ page }) => {
  const { open, breakdown } = await openBreakdown(page, "/ru/quran?surah=6", /^Разбор таджвида/);
  await expect(open).toHaveAccessibleName("Разбор таджвида: Аят 6:2");
  const counter = breakdown.getByTestId("tajweed-step-counter");
  const lit = breakdown.locator(".tajweed-breakdown-word.is-step");

  // Step 1: the idgham joins two words, lit together in the ayah.
  await expect(counter).toHaveText("1 из 2: Идгам без гунны");
  await expect(counter).toHaveAttribute("aria-live", "polite");
  await expect(lit).toHaveCount(2);
  await expect(lit.nth(0)).toHaveAttribute("data-word-position", "3");
  await expect(lit.nth(1)).toHaveAttribute("data-word-position", "4");
  const step = breakdown.locator(".tajweed-step");
  await expect(step.getByRole("heading", { name: "Идгам без гунны" })).toBeVisible();
  expect((await step.locator(".tajweed-letters").textContent())?.replaceAll("\u200d", "")).toBe("يَكُن لَّهُۥ");
  await expect(step.getByText("Нун с сукуном перед ل или ر.")).toBeVisible();
  await expect(step.getByText("Сразу читайте удвоенную ل.")).toBeVisible();
  await expect(breakdown.getByRole("button", { name: "Назад" })).toBeDisabled();

  // The fragment plays both words of the rule, slowed down when asked.
  await breakdown.getByRole("button", { name: "Медленнее, 0,75×" }).click();
  await breakdown.getByRole("button", { name: "Послушать фрагмент" }).click();
  await expect(breakdown.getByRole("button", { name: "Остановить" })).toBeVisible();
  const fragment = breakdown.locator(".tajweed-audio audio");
  expect(await fragment.evaluate((audio: HTMLAudioElement) => ({
    rate: audio.playbackRate,
    start: audio.currentTime,
    paused: audio.paused,
  }))).toEqual({ rate: 0.75, start: 1, paused: false });

  // The next step stops the sound and starts its own from the beginning.
  await page.keyboard.press("ArrowRight");
  await expect(counter).toHaveText("2 из 2: Мадд табии");
  expect(await fragment.evaluate((audio: HTMLAudioElement) => audio.paused)).toBe(true);
  await expect(breakdown.getByRole("button", { name: "Послушать фрагмент" })).toBeVisible();
  await expect(step.getByRole("heading", { name: "Мадд табии · Мадд силя сугра" })).toBeVisible();
  await expect(lit).toHaveCount(1);
  await expect(lit).toHaveAttribute("data-word-position", "4");
  await expect(breakdown.getByRole("button", { name: "Медленнее, 0,75×" })).toHaveAttribute("aria-pressed", "true");

  // The whole ayah lights the word being recited.
  await breakdown.getByRole("button", { name: "Прослушать весь аят" }).click();
  const ayahAudio = breakdown.getByTestId("tajweed-ayah-audio");
  expect(await ayahAudio.evaluate((audio: HTMLAudioElement) => [audio.currentTime, audio.paused])).toEqual([1, false]);
  await ayahAudio.evaluate((audio: HTMLAudioElement) => { audio.currentTime = 1.5; });
  await expect(breakdown.locator(".tajweed-breakdown-word.is-reading")).toHaveAttribute("data-word-position", "4");
  await ayahAudio.evaluate((audio: HTMLAudioElement) => { audio.currentTime = 2; });
  await expect(breakdown.getByRole("button", { name: "Прослушать весь аят" })).toBeVisible();
  await expect(breakdown.locator(".tajweed-breakdown-word.is-reading")).toHaveCount(0);

  // The summary lists the rules met; each opens its card, whose places lead back to their steps.
  await breakdown.getByRole("button", { name: "Итог" }).click();
  await expect(counter).toHaveText("Итог");
  const summary = breakdown.getByTestId("tajweed-summary");
  await expect(summary.getByRole("button")).toHaveText(["Идгам без гунны", "Мадд табии", "Начать сначала"]);
  await summary.getByRole("button", { name: "Идгам без гунны" }).click();
  await expect(breakdown.getByText("Когда действует")).toBeVisible();
  await expect(breakdown.getByText("Где в этом аяте")).toBeVisible();
  await breakdown.getByRole("button", { name: /Шаг 1/ }).click();
  await expect(counter).toHaveText("1 из 2: Идгам без гунны");

  await page.keyboard.press("Escape");
  await expect(breakdown).toHaveCount(0);
  await expect(open).toBeFocused();
});

test("tajweed breakdown in Arabic turns steps with the left arrow", async ({ page }) => {
  const { breakdown } = await openBreakdown(page, "/ar/quran?surah=6", /^شرح التجويد/);
  await expect(breakdown).toHaveAttribute("dir", "rtl");
  const counter = breakdown.getByTestId("tajweed-step-counter");
  const first = await counter.textContent();
  await page.keyboard.press("ArrowLeft");
  await expect(counter).not.toHaveText(first ?? "");
  await expect(breakdown.locator(".tajweed-step")).toHaveAttribute("data-step", "2");
  await page.keyboard.press("ArrowRight");
  await expect(breakdown.locator(".tajweed-step")).toHaveAttribute("data-step", "1");
  await expect(breakdown.getByRole("button", { name: "التالي" })).toBeVisible();
});

test("tajweed chips float in the phone reader and open a bottom sheet", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await installTajweedMocks(page);
  await page.goto("/ru/quran?surah=6");
  await expect(page.locator('.qf-mushaf-view[data-mushaf-id="19"]')).toHaveAttribute("data-font-status", "ready");
  // A development server hydrates the reader before it turns immersive; production opens it directly.
  const enterReader = page.getByRole("button", { name: "Открыть читалку" });
  if (await enterReader.isVisible()) await enterReader.click();
  const legend = page.getByTestId("tajweed-legend");
  // Like the page labels in the app, the chips give way to the open reader menu.
  await expect(legend).toBeHidden();
  await page.getByRole("button", { name: "Свернуть меню читалки" }).click();
  await expect(legend).toBeVisible();
  const legendBox = await legend.boundingBox();
  expect((legendBox?.y ?? 0) + (legendBox?.height ?? 0)).toBeLessThanOrEqual(844);
  await legend.getByRole("button", { name: "Мадд табии" }).click();
  const card = page.getByRole("dialog", { name: "Правило таджвида" });
  await expect(card).toBeVisible();
  const box = await card.boundingBox();
  expect(box?.width).toBe(390);
  expect(Math.round((box?.y ?? 0) + (box?.height ?? 0))).toBe(844);
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
});

// More rules than a phone row holds, so the legend has to scroll.
const extraRules = [
  ["ikhafa", "Ихфа", "#09B000"],
  ["ghunnah", "Гунна", "#09B000"],
  ["ham_wasl", "Хамзату-ль-васль", "#9FA5A5"],
  ["laam_shamsiyah", "Лям шамсия", "#9FA5A5"],
].map(([code, name, color]) => ({
  code, arabic_name: name, color, name: tajweedTexts(name, name), why: tajweedTexts("—", "—"),
  how: tajweedTexts("—", "—"), variants: [],
}));

async function openPhoneReader(page: Page, path: string) {
  await installTajweedMocks(page);
  await page.route("**/api/v1/quran/tajweed/rules", (route) => route.fulfill({
    json: { ...tajweedReference, rules: [...tajweedReference.rules, ...extraRules] },
  }));
  await page.route("**/api/v1/quran/tajweed/pages/128", (route) => route.fulfill({
    json: { ...tajweedPage128, rules: [...tajweedPage128.rules, ...extraRules.map((rule) => rule.code)] },
  }));
  await page.goto(path);
  await expect(page.locator('.qf-mushaf-view[data-mushaf-id="19"]')).toHaveAttribute("data-font-status", "ready");
  // A development server hydrates the reader before it turns immersive; production opens it directly.
  const enterReader = page.locator(".reader-launch").filter({ visible: true });
  if (await enterReader.count()) await enterReader.click();
  await foldReaderMenu(page);
}

/** The chips and the breakdown float over the page once the reader menu folds. */
async function foldReaderMenu(page: Page) {
  const fold = page.locator(".reader-actions:not(.is-folded) .reader-action-buttons > button:last-child")
    .filter({ visible: true });
  if (await fold.count()) await fold.click();
}

/** Every box stays inside the screen; nothing scrolls the page sideways. */
async function expectInsideScreen(page: Page, selector: string) {
  const boxes = await page.locator(selector).evaluateAll((elements) => elements.map((element) => {
    const rect = element.getBoundingClientRect();
    return { left: Math.round(rect.left), right: Math.round(rect.right), width: window.innerWidth };
  }));
  expect(boxes.length).toBeGreaterThan(0);
  for (const box of boxes) {
    expect(box.left).toBeGreaterThanOrEqual(0);
    expect(box.right).toBeLessThanOrEqual(box.width);
  }
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
}

/** A real touch drag, so the sheet sees touch pointer events. */
async function swipeDown(page: Page, x: number, y: number, distance: number) {
  const client = await page.context().newCDPSession(page);
  await client.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x, y }] });
  for (let step = 1; step <= 6; step += 1) {
    await client.send("Input.dispatchTouchEvent", {
      type: "touchMove", touchPoints: [{ x, y: y + (distance * step) / 6 }],
    });
  }
  await client.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
}

for (const [width, height] of [[360, 740], [390, 844], [412, 915], [740, 360]]) {
  test.describe(`tajweed on a ${width}×${height} phone`, () => {
    test.use({ viewport: { width, height }, isMobile: true, hasTouch: true });

    test("the legend scrolls inside the screen and the sheets fit and close", async ({ page }) => {
      await openPhoneReader(page, "/ru/quran?surah=6");
      const legend = page.getByTestId("tajweed-legend");
      // A short landscape screen keeps the reader menu over the page and no chips.
      if (!(await legend.isVisible())) {
        expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
        return;
      }
      const list = legend.locator(".tajweed-legend-list");
      await expectInsideScreen(page, ".mushaf-tajweed-legend .tajweed-legend-list");
      const hidden = await list.evaluate((element) => element.scrollWidth - element.clientWidth);
      if (hidden > 1) {
        // The row fades where chips are hidden, and every chip can be scrolled to.
        await expect(list).toHaveAttribute("data-overflow", "end");
        expect(await list.evaluate((element) => getComputedStyle(element).maskImage)).toContain("gradient");
        await list.evaluate((element) => element.scrollTo({ left: element.scrollWidth }));
        await expect(list).toHaveAttribute("data-overflow", "start");
        await expectInsideScreen(page, ".mushaf-tajweed-legend .tajweed-chip[data-rule='laam_shamsiyah']");
      }

      await legend.getByRole("button", { name: "Лям шамсия" }).click();
      const card = page.getByRole("dialog", { name: "Правило таджвида" });
      await expect(card).toBeVisible();
      await expectInsideScreen(page, "[data-testid='tajweed-card']");
      // A swipe down from the handle closes the sheet, as in the app.
      const handle = await card.getByTestId("tajweed-sheet-handle").boundingBox();
      await swipeDown(page, handle!.x + 40, handle!.y + handle!.height / 2, 200);
      await expect(card).toHaveCount(0);
    });
  });
}

test.describe("tajweed breakdown on a narrow phone", () => {
  test.use({ viewport: { width: 360, height: 740 }, isMobile: true, hasTouch: true });

  test("fits the screen in Arabic and keeps its buttons in reach", async ({ page }) => {
    await openPhoneReader(page, "/ar/quran?surah=6");
    await page.locator('.qf-mushaf-ayah-fragment[data-ayah-key="6:2"] .qf-mushaf-word.is-ayah-end')
      .filter({ visible: true }).first().click();
    await foldReaderMenu(page);
    await page.getByTestId("tajweed-breakdown-open-reader").click();
    const breakdown = page.getByTestId("tajweed-breakdown");
    await expect(breakdown).toBeVisible();
    await expectInsideScreen(page, "[data-testid='tajweed-breakdown'], .tajweed-breakdown-ayah, .tajweed-step-nav");
    const next = breakdown.locator(".tajweed-step-nav .btn-primary");
    await expect(next).toBeInViewport();
    await page.keyboard.press("Escape");
    await expect(breakdown).toHaveCount(0);
  });
});

test("source surah headings are filled from the pinned QUL heading font", async ({ page }) => {
  const font = syntheticHeadingFont();
  const checksum = createHash("sha256").update(font).digest("hex");
  const fontUrl = "https://static-cdn.tarteel.ai/qul/fonts/surah-names/surah-header/QCF_SurahHeader_COLOR-Regular.ttf";
  await page.route(fontUrl, (route) => route.fulfill({
    body: Buffer.from(font),
    contentType: "font/ttf",
    headers: { "access-control-allow-origin": "*" },
  }));
  const serve = async (sha256: string) => {
    await page.route("**/api/v1/quran/foundation/mushafs/5/pages/128", (route) => route.fulfill({ json: {
      ...foundationPage(5, 128),
      surah_header: { font_url: fontUrl, font_sha256: sha256, glyph_ids: { "6": 1 } },
    } }));
    await page.goto("/quran?surah=6");
    return page.locator(".qf-mushaf-view").filter({ visible: true }).locator(".qf-mushaf-chapter-title");
  };

  const heading = await serve(checksum);
  await expect(heading).toHaveClass(/has-source-header/);
  await expect(heading).toHaveAttribute("role", "img");
  await expect(heading).toHaveAttribute("aria-label", "سُورَةُ الأنعام");
  await expect(heading.locator("svg")).toHaveAttribute("viewBox", "0 -100 200 100");
  await expect(heading.locator("path")).toHaveAttribute("d", "M0 0L200 0Q200 -100 0 -100L0 0Z");
  await expect(heading).toHaveCSS("border-image-source", "none");

  // A changed file never maps glyph ids to surahs: the plain text title remains.
  await page.unroute("**/api/v1/quran/foundation/mushafs/5/pages/128");
  const fallback = await serve("0".repeat(64));
  await expect(fallback).toHaveText("سُورَةُ الأنعام");
  await expect(fallback).toBeVisible();
  await expect(fallback).not.toHaveClass(/has-source-header|is-header-loading/);
  await expect(fallback.locator("svg")).toHaveCount(0);
  await expect(fallback).toHaveCSS("border-image-source", "none");
});

test("Quran favorite uses an animated bookmark and toggles the saved ayah", async ({ page }) => {
  const session = {
    token_type: "Bearer",
    access_token: "quran-favorite-access-token",
    expires_in: 900,
    access_expires_at: "2026-08-29T10:15:00Z",
    user: {
      id: "00000000-0000-7000-8000-000000000701",
      status: "active",
      preferred_locale: "ru",
      email: "reader@example.com",
    },
    device: {
      id: "00000000-0000-7000-8000-000000000702",
      platform: "web",
      locale: "ru",
      app_version: "1.0.0",
      bootstrap_generation: 1,
    },
  };
  let savedBookmark: Record<string, unknown> | null = null;
  let deleteRequested = false;

  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ json: session }));
  await page.route("**/api/v1/me/bookmarks**", async (route) => {
    const request = route.request();
    const url = new URL(request.url());
    if (url.pathname === "/api/v1/me/bookmarks" && request.method() === "GET") {
      return route.fulfill({
        json: { next: null, previous: null, results: savedBookmark ? [savedBookmark] : [] },
      });
    }
    if (url.pathname === "/api/v1/me/bookmarks" && request.method() === "POST") {
      savedBookmark = {
        id: "00000000-0000-7000-8000-000000000703",
        edition_code: "madani-hafs",
        page_number: 128,
        ayah: {
          id: ayahs[0].id,
          surah_number: 6,
          ayah_number: 1,
          surah_name_ar: surah.name_ar,
          surah_name_en: surah.name_en,
          surah_name_ru: surah.name_ru,
        },
        label: "Сура 6:1 (стр. 128)",
        color_key: "emerald",
        note: "",
        revision: 1,
        deleted_at: null,
      };
      return route.fulfill({ status: 201, json: savedBookmark });
    }
    if (request.method() === "DELETE") {
      deleteRequested = true;
      const deleted = { ...savedBookmark, revision: 2, deleted_at: "2026-08-29T10:00:00Z" };
      savedBookmark = null;
      return route.fulfill({ json: deleted });
    }
    return route.fallback();
  });

  await page.goto("/quran?surah=6");
  const addFavorite = page.getByRole("button", { name: "Добавить в закладки" }).first();
  await page.getByRole("button", { name: "📜 Текст", exact: true }).click();
  await expect(addFavorite.locator(".favorite-bookmark-icon")).toBeVisible();
  await expect(addFavorite).toHaveAttribute("aria-pressed", "false");

  await addFavorite.click();
  const removeFavorite = page.getByRole("button", { name: "Удалить из закладок" }).first();
  await expect(removeFavorite).toHaveAttribute("aria-pressed", "true");
  await expect(removeFavorite).toHaveClass(/is-saved/);
  await expect(removeFavorite).toHaveClass(/is-animating/);

  await removeFavorite.click();
  await expect(page.getByRole("button", { name: "Добавить в закладки" }).first()).toHaveAttribute(
    "aria-pressed",
    "false",
  );
  expect(deleteRequested).toBe(true);
});

function annotationSession(userId: string) {
  return {
    token_type: "Bearer",
    access_token: "ayah-annotation-access-token",
    expires_in: 900,
    access_expires_at: "2026-10-20T10:15:00Z",
    user: { id: userId, status: "active", preferred_locale: "ru", email: "reader@example.com" },
    device: {
      id: "00000000-0000-7000-8000-000000000722",
      platform: "web",
      locale: "ru",
      app_version: "1.0.0",
      bootstrap_generation: 1,
    },
  };
}

test("ayah notes and highlights sync with the app in Mushaf, text and notes views", async ({ page }) => {
  await page.route("**/api/web-auth/refresh", (route) =>
    route.fulfill({ json: annotationSession("00000000-0000-7000-8000-000000000721") }));
  const fromApp = {
    id: "01992d87-6c00-7000-8000-000000000731",
    entity_type: "ayah_annotation",
    edition_code: "madani-hafs",
    page_number: 128,
    ayah: {
      id: ayahs[1].id,
      surah_number: 6,
      ayah_number: 2,
      surah_name_ar: surah.name_ar,
      surah_name_en: surah.name_en,
      surah_name_ru: surah.name_ru,
    },
    color_key: "pink",
    note: "Из приложения",
    client_updated_at: "2026-10-19T10:00:00Z",
    revision: 3,
    deleted_at: null,
    device_id: null,
    created_at: "2026-10-19T10:00:00Z",
    updated_at: "2026-10-19T10:00:00Z",
  };
  const pushed: Record<string, unknown>[] = [];
  let pulls = 0;
  await page.route("**/api/v1/sync/**", async (route) => {
    const url = new URL(route.request().url());
    if (url.pathname === "/api/v1/sync/pull") {
      pulls += 1;
      return route.fulfill({
        json: pulls === 1
          ? {
              mode: "incremental",
              changes: [{
                cursor: 5,
                entity_type: "ayah_annotation",
                entity_id: fromApp.id,
                action: "upsert",
                revision: 3,
                entity: fromApp,
                server_updated_at: fromApp.updated_at,
              }],
              next_cursor: 5,
              has_more: false,
            }
          : { mode: "incremental", changes: [], next_cursor: 5, has_more: false },
      });
    }
    const { operations } = route.request().postDataJSON() as { operations: Record<string, unknown>[] };
    pushed.push(...operations);
    return route.fulfill({
      json: {
        results: operations.map((operation) => {
          const payload = operation.payload as Record<string, unknown>;
          return {
            operation_id: operation.operation_id,
            outcome: "accepted",
            replayed: false,
            entity: operation.action === "delete"
              ? { ...fromApp, revision: 4, deleted_at: "2026-10-20T10:01:00Z" }
              : {
                  ...fromApp,
                  id: operation.entity_id,
                  ayah: { ...fromApp.ayah, id: ayahs[0].id, ayah_number: payload.ayah_number },
                  color_key: payload.color_key,
                  note: payload.note,
                  revision: 1,
                  updated_at: "2026-10-20T10:00:00Z",
                },
            cursor: 6,
          };
        }),
        cursor: 6,
      },
    });
  });

  await page.goto("/ru/quran?surah=6");
  const fragment = (key: string) => page.locator(`.qf-mushaf-ayah-fragment[data-ayah-key="${key}"]`).first();
  await expect(fragment("6:2")).toHaveAttribute("data-highlight", "pink");

  await fragment("6:1").click();
  await page.locator(".mushaf-ayah-actions").getByRole("button", { name: /Заметка и выделение/ }).click();
  const dialog = page.getByRole("dialog", { name: "Аят 6:1" });
  await dialog.getByText("Голубой", { exact: true }).click();
  await dialog.getByLabel("Ваша заметка").fill("Заметка с сайта");
  await dialog.getByRole("button", { name: "Сохранить" }).click();
  await expect(dialog).toBeHidden();
  await expect(page.getByText("Заметка сохранена")).toBeVisible();
  await expect(fragment("6:1")).toHaveAttribute("data-highlight", "blue");
  expect(pushed[0]).toMatchObject({
    entity_type: "ayah_annotation",
    action: "upsert",
    base_revision: 0,
    payload: {
      edition_code: "madani-hafs",
      surah_number: 6,
      ayah_number: 1,
      page_number: 128,
      color_key: "blue",
      note: "Заметка с сайта",
    },
  });

  await page.getByRole("button", { name: "📜 Текст", exact: true }).click();
  await expect(page.locator("#quran-ayah-6-2")).toHaveAttribute("data-highlight", "pink");
  await page.getByRole("button", { name: "Заметка и выделение: Аят 6:2" }).click();
  const appDialog = page.getByRole("dialog", { name: "Аят 6:2" });
  await expect(appDialog.getByLabel("Ваша заметка")).toHaveValue("Из приложения");
  await appDialog.getByRole("button", { name: "Убрать выделение" }).click();
  await expect(appDialog.getByText("Заметка к этому аяту тоже будет удалена.")).toBeVisible();
  await appDialog.getByRole("button", { name: "Удалить" }).click();
  await expect(appDialog).toBeHidden();
  await expect(page.locator("#quran-ayah-6-2")).not.toHaveAttribute("data-highlight", /.+/);
  expect(pushed.at(-1)).toMatchObject({
    entity_type: "ayah_annotation",
    entity_id: fromApp.id,
    action: "delete",
    base_revision: 3,
  });

  await page.goto("/ru/notes");
  const notes = page.locator(".notes-item");
  await expect(notes).toHaveCount(1);
  await expect(notes).toContainText("Заметка с сайта");
  await expect(notes).toHaveAttribute("href", "/ru/quran?surah=6&ayah=1");
});

test("a note from the app that arrives while the dialog is open is kept, not overwritten", async ({ page }) => {
  await page.route("**/api/web-auth/refresh", (route) =>
    route.fulfill({ json: annotationSession("00000000-0000-7000-8000-000000000751") }));
  const fromApp = {
    id: "01992d87-6c00-7000-8000-000000000752",
    entity_type: "ayah_annotation",
    edition_code: "madani-hafs",
    page_number: 128,
    ayah: { id: ayahs[0].id, surah_number: 6, ayah_number: 1 },
    color_key: "pink",
    note: "Из приложения",
    client_updated_at: "2026-10-19T10:00:00Z",
    revision: 3,
    deleted_at: null,
    device_id: null,
    created_at: "2026-10-19T10:00:00Z",
    updated_at: "2026-10-19T10:00:00Z",
  };
  let releasePull!: () => void;
  const pullReleased = new Promise<void>((resolve) => { releasePull = resolve; });
  let pulls = 0;
  const pushed: Record<string, unknown>[] = [];
  await page.route("**/api/v1/sync/**", async (route) => {
    const url = new URL(route.request().url());
    if (url.pathname === "/api/v1/sync/pull") {
      pulls += 1;
      if (pulls === 1) await pullReleased;
      return route.fulfill({
        json: {
          mode: "incremental",
          changes: pulls === 1
            ? [{
                cursor: 5,
                entity_type: "ayah_annotation",
                entity_id: fromApp.id,
                action: "upsert",
                revision: 3,
                entity: fromApp,
                server_updated_at: fromApp.updated_at,
              }]
            : [],
          next_cursor: 5,
          has_more: false,
        },
      });
    }
    const { operations } = route.request().postDataJSON() as { operations: Record<string, unknown>[] };
    pushed.push(...operations);
    return route.fulfill({
      json: {
        results: operations.map((operation) => ({
          operation_id: operation.operation_id,
          outcome: "accepted",
          replayed: false,
          entity: { ...fromApp, ...(operation.payload as object), revision: 4, ayah: fromApp.ayah },
          cursor: 6,
        })),
        cursor: 6,
      },
    });
  });

  await page.goto("/ru/quran?surah=6");
  await page.getByRole("button", { name: "📜 Текст", exact: true }).click();
  const opener = page.getByRole("button", { name: /^Заметка и выделение: Аят 6:1/ });
  await opener.click();
  const dialog = page.getByRole("dialog", { name: "Аят 6:1" });
  const save = dialog.getByRole("button", { name: "Загрузка…" });
  await expect(save).toBeDisabled();
  await expect(dialog.getByLabel("Ваша заметка")).toHaveValue("");

  releasePull();
  await expect(dialog.getByLabel("Ваша заметка")).toHaveValue("Из приложения");
  await expect(dialog.getByRole("radio", { name: "Розовый" })).toBeChecked();
  await dialog.getByText("Жёлтый", { exact: true }).click();
  await dialog.getByRole("button", { name: "Сохранить" }).click();
  await expect(dialog).toBeHidden();
  await expect(opener).toBeFocused();
  await expect(opener).toHaveAccessibleName("Заметка и выделение: Аят 6:1 · Выделено: Жёлтый, есть заметка");
  expect(pushed).toEqual([
    expect.objectContaining({
      entity_type: "ayah_annotation",
      entity_id: fromApp.id,
      action: "upsert",
      base_revision: 3,
      payload: expect.objectContaining({ color_key: "yellow", note: "Из приложения" }),
    }),
  ]);
});

test("a server error after the note is queued reports it as saved for a later sync", async ({ page }) => {
  await page.route("**/api/web-auth/refresh", (route) =>
    route.fulfill({ json: annotationSession("00000000-0000-7000-8000-000000000761") }));
  await page.route("**/api/v1/sync/**", (route) => {
    const url = new URL(route.request().url());
    if (url.pathname === "/api/v1/sync/pull") {
      return route.fulfill({ json: { mode: "incremental", changes: [], next_cursor: 0, has_more: false } });
    }
    return route.fulfill({ status: 503, json: { detail: "Service unavailable." } });
  });

  await page.goto("/ru/quran?surah=6");
  await page.getByRole("button", { name: "📜 Текст", exact: true }).click();
  await page.getByRole("button", { name: /^Заметка и выделение: Аят 6:1/ }).click();
  const dialog = page.getByRole("dialog", { name: "Аят 6:1" });
  await dialog.getByLabel("Ваша заметка").fill("Сохранить позже");
  await dialog.getByRole("button", { name: "Сохранить" }).click();
  await expect(dialog).toBeHidden();
  await expect(page.getByText("Сохранено на устройстве. Синхронизация завершится позже.")).toBeVisible();
  await expect(page.locator("#quran-ayah-6-1")).toHaveAttribute("data-highlight", "lime");
});

test("an ayah note saved offline stays highlighted and waits in the outbox", async ({ page }) => {
  const userId = "00000000-0000-7000-8000-000000000741";
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ json: annotationSession(userId) }));
  await page.route("**/api/v1/sync/**", (route) => route.abort("internetdisconnected"));

  await page.goto("/ru/quran?surah=6");
  await page.getByRole("button", { name: "📜 Текст", exact: true }).click();
  await page.getByRole("button", { name: "Заметка и выделение: Аят 6:1" }).click();
  const dialog = page.getByRole("dialog", { name: "Аят 6:1" });
  await dialog.getByLabel("Ваша заметка").fill("Без сети");
  await dialog.getByRole("button", { name: "Сохранить" }).click();
  await expect(page.getByText(/Сеть недоступна. Изменение сохранено/)).toBeVisible();
  await expect(page.locator("#quran-ayah-6-1")).toHaveAttribute("data-highlight", "lime");
  const state = await page.evaluate(
    (key) => JSON.parse(localStorage.getItem(key) || "{}"),
    `quran_platform_sync_v1:${userId}`,
  );
  expect(state.outbox).toEqual([
    expect.objectContaining({
      entity_type: "ayah_annotation",
      action: "upsert",
      base_revision: 0,
      payload: expect.objectContaining({ surah_number: 6, ayah_number: 1, note: "Без сети" }),
    }),
  ]);
});

test("text mode ends ayahs with the app's marker and shares an ayah picture through Web Share", async ({ page }) => {
  await page.addInitScript(() => {
    const target = window as unknown as { sharedAyah?: unknown };
    Object.defineProperty(navigator, "canShare", {
      configurable: true,
      value: (data: ShareData) => Boolean(data.files?.length),
    });
    Object.defineProperty(navigator, "share", {
      configurable: true,
      async value(data: ShareData) {
        const file = data.files?.[0];
        const picture = file ? await createImageBitmap(file) : null;
        target.sharedAyah = {
          title: data.title,
          text: data.text,
          file: file && { name: file.name, type: file.type, width: picture?.width, height: picture?.height },
        };
      },
    });
  });
  await page.goto("/ru/quran?surah=6");
  await page.getByRole("button", { name: "📜 Текст", exact: true }).click();
  await expect(page.locator("#quran-ayah-6-2 .ayah-end-marker")).toHaveText("﴿٢﴾");
  await expect(page.locator("#quran-ayah-6-2 .quran-arabic-text"))
    .toHaveJSProperty("textContent", `${ayahs[1].text_uthmani}\u00A0\uFD3F\u0662\uFD3E`);

  // The reader hides the translation; the picture still carries it, as in the app.
  await expect(page.getByText("Хвала Аллаху", { exact: true })).toBeVisible();
  await page.locator("#translation-enabled").filter({ visible: true }).uncheck();
  await expect(page.getByText("Хвала Аллаху", { exact: true })).toHaveCount(0);
  await page.getByRole("button", { name: "Поделиться аятом: Аят 6:1" }).click();
  const dialog = page.getByRole("dialog", { name: "Поделиться аятом" });
  await expect(dialog.getByText("Аль-Анам · 6:1")).toBeVisible();
  await expect(dialog.getByRole("img", { name: "Картинка аята 6:1" })).toBeVisible();
  await dialog.getByRole("button", { name: "Поделиться", exact: true }).click();

  const link = new URL("/ru/quran/madani-hafs/surah/6/ayah/1", page.url()).href;
  await expect.poll(() => page.evaluate(() => (window as unknown as { sharedAyah?: unknown }).sharedAyah))
    .toEqual({
      title: "Аль-Анам · 6:1",
      text: `Аль-Анам · 6:1\n\n${ayahs[0].text_uthmani}\n\n«Хвала Аллаху»\n\nElmir Kuliev\n\nЧитать в IQRO: ${link}`,
      file: { name: "iqro-6-1.png", type: "image/png", width: 1080, height: 1350 },
    });
  await dialog.getByRole("button", { name: "Закрыть" }).click();
  await expect(dialog).toBeHidden();
});

test("without Web Share the Mushaf ayah picture downloads and the link is copied", async ({ page }) => {
  await page.addInitScript(() => {
    const target = window as unknown as { copiedLink?: string };
    Object.defineProperty(navigator, "share", { configurable: true, value: undefined });
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText: async (text: string) => { target.copiedLink = text; } },
    });
  });
  await page.goto("/ru/quran?surah=6");
  // Linux has neither Times New Roman nor Arial, the local() metric fallbacks
  // next/font lists after Amiri and Inter; the card must not depend on them.
  await page.addStyleTag({
    content: `@font-face { font-family: "Missing Fallback"; src: local("IQRO Missing Font"); }
      html:root { --font-amiri: "Amiri", "Missing Fallback"; --font-inter: "Inter", "Missing Fallback"; }`,
  });
  await page.locator('.qf-mushaf-ayah-fragment[data-ayah-key="6:2"]').first().click();
  await page.locator(".mushaf-ayah-actions").getByRole("button", { name: "Поделиться аятом: Аят 6:2" }).click();
  const dialog = page.getByRole("dialog", { name: "Поделиться аятом" });
  await expect(dialog.getByRole("img", { name: "Картинка аята 6:2" })).toBeVisible();
  await expect(dialog.getByRole("button", { name: "Поделиться", exact: true })).toHaveCount(0);

  const [download] = await Promise.all([
    page.waitForEvent("download"),
    dialog.getByRole("link", { name: "Скачать картинку" }).click(),
  ]);
  expect(download.suggestedFilename()).toBe("iqro-6-2.png");
  const png = await readFile(await download.path());
  expect(png.subarray(1, 4).toString("ascii")).toBe("PNG");
  expect([png.readUInt32BE(16), png.readUInt32BE(20)]).toEqual([1080, 1350]);

  await dialog.getByRole("button", { name: "Скопировать ссылку" }).click();
  await expect(dialog.getByRole("status").filter({ hasText: "Ссылка скопирована" })).toBeVisible();
  expect(await page.evaluate(() => (window as unknown as { copiedLink?: string }).copiedLink))
    .toBe(new URL("/ru/quran/madani-hafs/surah/6/ayah/2", page.url()).href);
});

async function captureWebShare(page: Page) {
  await page.addInitScript(() => {
    const target = window as unknown as { sharedAyah?: unknown };
    Object.defineProperty(navigator, "share", {
      configurable: true,
      async value(data: ShareData) {
        target.sharedAyah = { title: data.title, text: data.text, files: data.files?.length ?? 0 };
      },
    });
  });
  return () => page.evaluate(() => (window as unknown as { sharedAyah?: unknown }).sharedAyah);
}

test("sharing while another translation loads uses that translation and its translator", async ({ page }) => {
  const shared = await captureWebShare(page);
  let release = () => {};
  const arrived = new Promise<void>((resolve) => { release = resolve; });
  await page.route("**/api/v1/quran/translations/79/surahs/6", async (route) => {
    await arrived;
    await route.fulfill({ json: translatedAyahs.map((verse) => ({ ...verse, text: `${verse.text} (Абу Адель)` })) });
  });
  await page.goto("/ru/quran?surah=6");
  await page.getByRole("button", { name: "📜 Текст", exact: true }).click();
  await expect(page.getByText("Хвала Аллаху", { exact: true })).toBeVisible();
  await page.getByLabel("Перевод и автор").selectOption("79");
  await page.getByRole("button", { name: "Поделиться аятом: Аят 6:1" }).click();
  release();
  const dialog = page.getByRole("dialog", { name: "Поделиться аятом" });
  await expect(dialog.getByRole("img", { name: "Картинка аята 6:1" })).toBeVisible();
  await dialog.getByRole("button", { name: "Поделиться", exact: true }).click();
  await expect.poll(shared).toMatchObject({
    text: expect.stringContaining("«Хвала Аллаху (Абу Адель)»\n\nAbu Adel\n\n"),
  });
});

test("an ayah whose text cannot load is still shared as a link", async ({ page }) => {
  const shared = await captureWebShare(page);
  // As offline: the surah's text never arrives and the single ayah fails.
  await page.route("**/api/v1/quran/editions/madani-hafs/surahs/6/ayahs", () => undefined);
  await page.route("**/api/v1/quran/editions/madani-hafs/ayahs/6/2", (route) =>
    route.fulfill({ status: 503, contentType: "application/problem+json", json: { detail: "Offline" } }));
  await page.goto("/ru/quran?surah=6");
  await page.locator('.qf-mushaf-ayah-fragment[data-ayah-key="6:2"]').first().click();
  await page.locator(".mushaf-ayah-actions").getByRole("button", { name: "Поделиться аятом: Аят 6:2" }).click();
  const dialog = page.getByRole("dialog", { name: "Поделиться аятом" });
  await expect(dialog.getByRole("alert")).toHaveText("Не удалось подготовить картинку. Ссылкой поделиться можно.");
  await dialog.getByRole("button", { name: "Поделиться", exact: true }).click();
  const link = new URL("/ru/quran/madani-hafs/surah/6/ayah/2", page.url()).href;
  await expect.poll(shared).toEqual({
    title: "Аль-Анам · 6:2",
    text: `Аль-Анам · 6:2\n\nЧитать в IQRO: ${link}`,
    files: 0,
  });
});

test("an ayah picture is drawn again when its font arrives late", async ({ page }) => {
  await page.addInitScript(() => {
    const load = FontFaceSet.prototype.load;
    FontFaceSet.prototype.load = function (this: FontFaceSet, font: string, text?: string) {
      const faces = load.call(this, font, text);
      return /Amiri/.test(font)
        ? faces.then((loaded) => new Promise<FontFace[]>((resolve) => setTimeout(() => resolve(loaded), 6000)))
        : faces;
    };
  });
  await page.goto("/ru/quran?surah=6");
  await page.getByRole("button", { name: "📜 Текст", exact: true }).click();
  await page.getByRole("button", { name: "Поделиться аятом: Аят 6:1" }).click();
  const picture = page.getByRole("dialog", { name: "Поделиться аятом" })
    .getByRole("img", { name: "Картинка аята 6:1" });
  await expect(picture).toBeVisible({ timeout: 10_000 });
  const first = await picture.getAttribute("src");
  await expect(picture).not.toHaveAttribute("src", first ?? "", { timeout: 10_000 });
});

test("without the share dialog's code an ayah still goes as text, and the next press loads it", async ({ page }) => {
  const pageErrors: string[] = [];
  page.on("pageerror", (error) => pageErrors.push(error.message));
  const shared = await captureWebShare(page);
  await page.goto("/ru/quran?surah=6");
  await page.getByRole("button", { name: "📜 Текст", exact: true }).click();
  await expect(page.getByText("Хвала Аллаху", { exact: true })).toBeVisible();

  await page.route("**/_next/static/chunks/**", (route) => route.abort());
  await page.getByRole("button", { name: "Поделиться аятом: Аят 6:1" }).click();
  const link = new URL("/ru/quran/madani-hafs/surah/6/ayah/1", page.url()).href;
  await expect.poll(shared).toEqual({
    title: "Аль-Анам · 6:1",
    text: `Аль-Анам · 6:1\n\n${ayahs[0].text_uthmani}\n\n«Хвала Аллаху»\n\nElmir Kuliev\n\nЧитать в IQRO: ${link}`,
    files: 0,
  });
  await expect(page.getByRole("dialog")).toHaveCount(0);
  await expect(page.locator("#quran-ayah-6-1")).toBeVisible();

  await page.unroute("**/_next/static/chunks/**");
  await page.getByRole("button", { name: "Поделиться аятом: Аят 6:1" }).click();
  await expect(page.getByRole("dialog", { name: "Поделиться аятом" })
    .getByRole("img", { name: "Картинка аята 6:1" })).toBeVisible();
  expect(pageErrors).toEqual([]);
});

test("an ayah picture that cannot be drawn is reported and the link still copies", async ({ page }) => {
  await page.addInitScript(() => {
    const target = window as unknown as { copiedLink?: string };
    HTMLCanvasElement.prototype.toBlob = function (callback: BlobCallback) { callback(null); };
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText: async (text: string) => { target.copiedLink = text; } },
    });
  });
  await page.goto("/ru/quran?surah=6");
  await page.getByRole("button", { name: "📜 Текст", exact: true }).click();
  await page.getByRole("button", { name: "Поделиться аятом: Аят 6:2" }).click();
  const dialog = page.getByRole("dialog", { name: "Поделиться аятом" });
  await expect(dialog.getByRole("alert")).toHaveText("Не удалось подготовить картинку. Ссылкой поделиться можно.");
  await expect(dialog.getByRole("img")).toHaveCount(0);
  await expect(dialog.getByRole("link", { name: "Скачать картинку" })).toHaveCount(0);
  await dialog.getByRole("button", { name: "Скопировать ссылку" }).click();
  await expect(dialog.getByRole("status").filter({ hasText: "Ссылка скопирована" })).toBeVisible();
  expect(await page.evaluate(() => (window as unknown as { copiedLink?: string }).copiedLink))
    .toBe(new URL("/ru/quran/madani-hafs/surah/6/ayah/2", page.url()).href);
});

test("reading place is remembered automatically and retries a revision conflict", async ({ page }) => {
  const session = {
    token_type: "Bearer",
    access_token: "reading-place-access-token",
    expires_in: 900,
    access_expires_at: "2026-08-29T10:15:00Z",
    user: {
      id: "00000000-0000-7000-8000-000000000711",
      status: "active",
      preferred_locale: "ru",
      email: "reader@example.com",
    },
    device: {
      id: "00000000-0000-7000-8000-000000000712",
      platform: "web",
      locale: "ru",
      app_version: "1.0.0",
      bootstrap_generation: 1,
    },
  };
  let revision = 4;
  const putPayloads: Record<string, unknown>[] = [];
  const readingPosition = () => ({
    id: "00000000-0000-7000-8000-000000000713",
    edition_code: "madani-hafs",
    page_number: 128,
    ayah: {
      id: ayahs[0].id,
      surah_number: 6,
      ayah_number: 1,
    },
    progress_percent: "21.19",
    revision,
    last_read_at: "2026-08-29T09:00:00Z",
    client_updated_at: "2026-08-29T09:00:00Z",
  });

  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ json: session }));
  await page.route("**/api/v1/me/reading-position/madani-hafs", async (route) => {
    if (route.request().method() === "GET") {
      return route.fulfill({ json: readingPosition() });
    }
    const payload = route.request().postDataJSON() as Record<string, unknown>;
    putPayloads.push(payload);
    if (putPayloads.length === 1) {
      expect(payload.base_revision).toBe(4);
      revision = 5;
      return route.fulfill({
        status: 409,
        contentType: "application/problem+json",
        json: {
          status: 409,
          code: "sync_revision_conflict",
          detail: "Sync conflict: revision_mismatch.",
        },
      });
    }
    expect(payload.base_revision).toBe(5);
    revision = 6;
    return route.fulfill({ json: {
      ...readingPosition(),
      page_number: Number(payload.page_number),
      ayah: {
        id: ayahs[1].id,
        surah_number: Number(payload.surah_number),
        ayah_number: Number(payload.ayah_number),
      },
    } });
  });

  await page.goto("/quran?surah=6");
  await expect(page.getByRole("button", { name: "📍 Запомнить место" })).toHaveCount(0);
  await page.waitForTimeout(1500);
  expect(putPayloads).toHaveLength(0);

  await page.getByLabel(/Аят суры/).selectOption("2");
  await expect.poll(() => putPayloads.length, { timeout: 7000 }).toBe(2);
  expect(putPayloads[1]).toMatchObject({
    page_number: 128,
    surah_number: 6,
    ayah_number: 2,
    base_revision: 5,
  });
});

test("text Quran exposes the shared reciter controls and plays each ayah", async ({ page }) => {
  await page.goto("/quran?surah=6");
  await page.getByRole("button", { name: "📜 Текст", exact: true }).click();

  const recitationSelect = page.getByLabel("Чтец Quran.Foundation");
  await expect(recitationSelect).toBeVisible();
  await expect(recitationSelect.locator("option")).toHaveCount(2);

  const firstAyah = page.locator(".ayah-card").first();
  const secondAyah = page.locator(".ayah-card").nth(1);
  const playButton = firstAyah.getByRole("button", { name: "Воспроизвести: Аят 6:1" });
  const repeatButton = firstAyah.getByRole("button", { name: "Повтор аята: Аят 6:1" });
  const speedButton = firstAyah.getByRole("button", { name: "Скорость воспроизведения: 1×" });
  await expect(playButton).toHaveText("▶");
  await expect(playButton).not.toHaveClass(/is-active/);
  await expect(repeatButton).toHaveText("🔁");
  await expect(repeatButton).not.toHaveClass(/is-active/);
  await expect(speedButton).toHaveText("1×");
  await expect(speedButton).not.toHaveClass(/is-active/);
  await expect(firstAyah.getByRole("button", { name: "Отметить как прочитанное" })).toHaveCount(0);
  await expect(
    firstAyah.getByRole("button", { name: "Добавить в закладки" }).locator(".favorite-bookmark-icon"),
  ).toBeVisible();

  await speedButton.click();
  const advancedPlayer = page.getByRole("region", { name: "Расширенный аудиоплеер" });
  await expect(advancedPlayer.getByLabel("Скорость воспроизведения", { exact: true }))
    .toHaveValue("1.25");
  const fasterButton = firstAyah.getByRole("button", { name: "Скорость воспроизведения: 1,25×" });
  await expect(fasterButton).toHaveText("1,25×");
  await expect(fasterButton).toHaveClass(/is-active/);

  await playButton.click();
  const audio = page.locator(".mushaf-audio-now-playing audio[src]");
  await expect(audio).toHaveAttribute("src", tracks[5].asset.url);
  await expect(firstAyah).toHaveClass(/is-audio-active/);
  await expect(page.getByText(/Махер аль-Муайкли · Мурратталь · аят 6:1/)).toBeVisible();
  const pauseButton = firstAyah.getByRole("button", { name: "Поставить на паузу: Аят 6:1" });
  await expect(pauseButton).toHaveText("⏸");
  await expect(pauseButton).toHaveClass(/is-active/);

  await pauseButton.click();
  await expect(page.getByText("Пауза · позиция сохранена", { exact: true })).toBeVisible();
  const continueButton = firstAyah.getByRole("button", { name: "Продолжить: Аят 6:1" });
  await expect(continueButton).toHaveText("▶");
  await continueButton.click();
  await expect(page.getByText("Воспроизводится", { exact: true })).toBeVisible();

  await repeatButton.click();
  await expect(advancedPlayer.getByLabel("Режим повтора", { exact: true })).toHaveValue("ayah");
  const activeRepeatButton = firstAyah.getByRole("button", { name: "Режим повтора: Без повтора" });
  await expect(activeRepeatButton).toHaveAttribute("aria-pressed", "true");
  await expect(activeRepeatButton).toHaveClass(/is-active/);

  await secondAyah.getByRole("button", { name: "Повтор аята: Аят 6:2" }).click();
  await expect(secondAyah).toHaveClass(/is-audio-active/);
  await expect(secondAyah.getByRole("button", { name: "Режим повтора: Без повтора" })).toHaveAttribute("aria-pressed", "true");
  await expect(firstAyah.getByRole("button", { name: "Повтор аята: Аят 6:1" })).toHaveAttribute("aria-pressed", "false");
  await expect(page.getByText(/Махер аль-Муайкли · Мурратталь · аят 6:2/)).toBeVisible();

  await secondAyah.getByRole("button", { name: "Режим повтора: Без повтора" }).click();
  await expect(page.getByLabel("Режим повтора", { exact: true })).toHaveValue("off");
  await page.getByLabel("Скорость воспроизведения", { exact: true }).selectOption("1.5");
  await expect(firstAyah.getByRole("button", { name: "Скорость воспроизведения: 1,5×" })).toBeVisible();
});

test("advanced player handles ranges, repeat, learning pauses, speed and sleep", async ({ page }) => {
  await page.goto("/quran?surah=6");
  await page.getByRole("button", { name: /Мусхаф/ }).click();

  await expect(page.getByLabel("Начало диапазона аятов").locator("option")).toHaveCount(2);
  await page.getByLabel("Начало диапазона аятов").selectOption("1");
  await page.getByLabel("Конец диапазона аятов").selectOption("2");
  await page.getByLabel("Скорость воспроизведения").selectOption("1.5");
  await page.getByLabel("Пауза между аятами").selectOption("500");
  await page.getByRole("button", { name: "▶ Воспроизвести диапазон" }).click();

  const audio = page.locator(".mushaf-audio-now-playing audio[src]");
  await expect(page.getByText("Диапазон 6:1–6:2", { exact: true })).toBeVisible();
  await expect(audio).toHaveJSProperty("playbackRate", 1.5);

  await audio.evaluate((element) => {
    const media = element as HTMLAudioElement;
    media.currentTime = 0.97;
    media.dispatchEvent(new Event("timeupdate"));
  });
  await expect(page.getByText("Пауза между аятами · 0,5 с", { exact: true })).toBeVisible();
  await page.waitForTimeout(550);
  expect(await audio.evaluate((element) => (element as HTMLAudioElement).currentTime)).toBe(1);

  await page.getByLabel("Пауза между аятами").selectOption("0");
  await page.getByLabel("Режим повтора").selectOption("selection");
  await audio.evaluate((element) => {
    const media = element as HTMLAudioElement;
    media.currentTime = 1.97;
    media.dispatchEvent(new Event("timeupdate"));
  });
  await expect.poll(() => audio.evaluate((element) => (element as HTMLAudioElement).currentTime)).toBe(0);

  const ayahRegions = page.getByRole("button", { name: "Аят 6:2", exact: true });
  await ayahRegions.first().click();
  await page.getByRole("button", { name: "▶ Аят 6:2", exact: true }).click();
  await page.getByLabel("Режим повтора").selectOption("ayah");
  await audio.evaluate((element) => {
    const media = element as HTMLAudioElement;
    media.currentTime = 1.97;
    media.dispatchEvent(new Event("timeupdate"));
  });
  await expect.poll(() => audio.evaluate((element) => (element as HTMLAudioElement).currentTime)).toBe(1);

  await page.getByLabel("Таймер сна").selectOption("ayah");
  await audio.evaluate((element) => {
    const media = element as HTMLAudioElement;
    media.currentTime = 1.97;
    media.dispatchEvent(new Event("timeupdate"));
  });
  await expect(page.getByText("Таймер сна остановил воспроизведение после аята", { exact: true })).toBeVisible();
});

test("player preserves the cursor after interruption and registers Media Session controls", async ({ page }) => {
  await page.goto("/quran?surah=6");
  await page.getByRole("button", { name: /Мусхаф/ }).click();
  const ayahRegions = page.getByRole("button", { name: "Аят 6:2", exact: true });
  await ayahRegions.first().click();
  await page.getByRole("button", { name: "▶ Аят 6:2", exact: true }).click();

  const audio = page.locator(".mushaf-audio-now-playing audio[src]");
  await audio.evaluate((element) => element.dispatchEvent(new Event("waiting")));
  await expect(page.getByText("Буферизация · позиция сохранена", { exact: true })).toBeVisible();
  await audio.evaluate((element) => element.dispatchEvent(new Event("playing")));
  await expect(page.getByText("Воспроизводится", { exact: true })).toBeVisible();
  await audio.evaluate((element) => {
    const media = element as HTMLAudioElement;
    media.currentTime = 1.4;
    media.dispatchEvent(new Event("pause"));
  });
  await expect(page.getByText("Пауза · позиция сохранена", { exact: true })).toBeVisible();
  await audio.evaluate((element) => void (element as HTMLAudioElement).play());
  expect(await audio.evaluate((element) => (element as HTMLAudioElement).currentTime)).toBe(1.4);
  await expect(page.getByText("Воспроизводится", { exact: true })).toBeVisible();

  const mediaSession = await page.evaluate(() => {
    const handlers = (window as typeof window & {
      __mediaSessionHandlers: Record<string, unknown>;
    }).__mediaSessionHandlers;
    return {
      title: navigator.mediaSession.metadata?.title,
      actions: Object.entries(handlers)
        .filter(([, handler]) => typeof handler === "function")
        .map(([action]) => action)
        .sort(),
    };
  });
  expect(mediaSession.title).toBe("Аят 6:2");
  expect(mediaSession.actions).toEqual([
    "nexttrack",
    "pause",
    "play",
    "previoustrack",
    "seekbackward",
    "seekforward",
    "stop",
  ]);
});

test("minute sleep timer stops playback without losing the current position", async ({ page }) => {
  await page.goto("/audio");
  await page.getByRole("button", { name: "Слушать", exact: true }).first().click();
  await page.getByTestId("global-audio-player")
    .getByRole("button", { name: "Развернуть плеер", exact: true })
    .click();
  const audio = page.locator(".audio-player-bar audio");
  await audio.evaluate((element) => {
    (element as HTMLAudioElement).currentTime = 0.4;
  });

  await page.clock.install();
  await page.getByLabel("Таймер сна").selectOption("5");
  await expect(page.getByText("Осталось 5:00", { exact: true })).toBeVisible();
  await page.clock.fastForward("05:00");
  await expect(page.getByText(/Таймер сна остановил воспроизведение/)).toBeVisible();
  expect(await audio.evaluate((element) => (element as HTMLAudioElement).currentTime)).toBe(0.4);
});

for (const viewport of [
  { name: "mobile", width: 375, height: 812 },
  { name: "tablet", width: 768, height: 1024 },
  { name: "desktop", width: 1440, height: 1000 },
]) {
  test(`source page remains visible and ayahs selectable on ${viewport.name}`, async ({ page }) => {
    await page.setViewportSize({ width: viewport.width, height: viewport.height });
    await page.goto("/ru/quran?surah=6");

    const sheet = page.locator(".qf-mushaf-sheet").filter({ visible: true }).last();
    await expect(sheet).toBeVisible();
    const box = await sheet.boundingBox();
    expect(box?.width).toBeGreaterThan(0);
    expect(box!.width).toBeLessThanOrEqual(viewport.width);
    const fragments = page.getByRole("button", { name: "Аят 6:2", exact: true });
    await expect(fragments).toHaveCount(2);
    await fragments.last().click();
    await expect(fragments.first()).toHaveClass(/is-selected/);
    await expect(fragments.last()).toHaveClass(/is-selected/);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(
      await page.evaluate(() => document.documentElement.clientWidth),
    );
  });
}

test("Mushaf opens by default as a full-width mobile reader with RTL swipe navigation", async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 760 });
  await page.goto("/quran?surah=6");

  const layout = page.locator(".quran-page-layout").filter({ visible: true });
  await expect(layout).toHaveClass(/is-reader-immersive/);
  const reader = layout.locator(".mushaf-reader-surface");
  const stage = reader.locator(".mushaf-page-container");
  const image = reader.locator(".mushaf-page-turn .qf-mushaf-view");
  await expect(image).toHaveAttribute("data-page-number", "128");
  await expect(reader).toBeInViewport();
  await expect(page.locator(".mobile-navigation")).toBeHidden();
  await expect(reader).toHaveCSS("padding-left", "0px");
  await expect(reader).toHaveCSS("padding-right", "0px");
  await expect(reader.locator(".mushaf-reader-toolbar")).toBeHidden();
  await expect(reader.locator(".mushaf-reader-toolbar-button").filter({ visible: true })).toHaveCount(0);
  await expect(reader.locator(".mushaf-page-navigation")).toBeHidden();

  const readerBox = await reader.boundingBox();
  expect(readerBox).not.toBeNull();
  expect(readerBox!.x).toBeLessThanOrEqual(1);
  expect(readerBox!.width).toBeGreaterThanOrEqual(319);
  expect(readerBox!.y).toBe(0);
  expect(readerBox!.height).toBe(760);
  expect(await reader.evaluate((element) => getComputedStyle(element).order)).toBe("2");
  expect(
    await layout.locator(".quran-audio-surface").evaluate((element) => getComputedStyle(element).order),
  ).toBe("3");

  await stage.dispatchEvent("pointerdown", {
    pointerId: 1,
    pointerType: "touch",
    isPrimary: true,
    clientX: 70,
    clientY: 360,
  });
  await stage.dispatchEvent("pointerup", {
    pointerId: 1,
    pointerType: "touch",
    isPrimary: true,
    clientX: 250,
    clientY: 365,
  });
  await expect(image).toHaveAttribute("data-page-number", "129");
  await expect(reader.locator(".mushaf-page-turn")).toHaveAttribute("data-page-turn", "next");

  await stage.dispatchEvent("pointerdown", {
    pointerId: 2,
    pointerType: "touch",
    isPrimary: true,
    clientX: 250,
    clientY: 360,
  });
  await stage.dispatchEvent("pointerup", {
    pointerId: 2,
    pointerType: "touch",
    isPrimary: true,
    clientX: 70,
    clientY: 365,
  });
  await expect(image).toHaveAttribute("data-page-number", "128");
  await expect(reader.locator(".mushaf-page-turn")).toHaveAttribute("data-page-turn", "previous");
  await page.getByRole("toolbar").getByRole("button", { name: "Настройки чтения", exact: true }).click();
  await page.getByRole("button", { name: /Текст/ }).click();
  await expect(page.locator(".mobile-navigation")).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(
    await page.evaluate(() => document.documentElement.clientWidth),
  );
});

test.describe("Mushaf touch gestures over ayahs", () => {
  test.use({ hasTouch: true, viewport: { width: 390, height: 844 } });

  for (const variant of [
    { value: "5", view: ".qf-mushaf-view" },
  ]) {
    test(`swipes turn ${variant.value} pages while taps still select ayahs`, async ({ page }) => {
      await page.emulateMedia({ reducedMotion: "reduce" });
      await page.goto("/ru/quran?surah=6");
      await page.getByRole("toolbar").getByRole("button", { name: "Настройки чтения", exact: true }).click();
      await page.getByLabel("Вариант Мусхафа").selectOption(variant.value);
      await page.getByRole("button", { name: "Открыть читалку", exact: true }).click();

      const stage = page.locator(".mushaf-page-container").filter({ visible: true });
      const view = stage.locator(variant.view);
      const ayah = stage.locator('[data-ayah-key="6:2"]').last();
      await expect(view).toHaveAttribute("data-page-number", "128");
      const touch = await page.context().newCDPSession(page);
      const swipeAyah = async (dx: number, dy = 0) => {
        await ayah.evaluate((element) => element.scrollIntoView({ block: "center", behavior: "instant" }));
        const box = (await ayah.boundingBox())!;
        const x = box.x + box.width / 2;
        const y = box.y + box.height / 2;
        await touch.send("Input.dispatchTouchEvent", {
          type: "touchStart", touchPoints: [{ x, y }],
        });
        for (let step = 1; step <= 4; step += 1) {
          await touch.send("Input.dispatchTouchEvent", {
            type: "touchMove", touchPoints: [{ x: x + dx * step / 4, y: y + dy * step / 4 }],
          });
        }
        await touch.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
      };

      await swipeAyah(72);
      await expect(view).toHaveAttribute("data-page-number", "129");
      await expect(stage.locator("[data-ayah-key].is-selected")).toHaveCount(0);
      await swipeAyah(-72);
      await expect(view).toHaveAttribute("data-page-number", "128");
      await expect(stage.locator("[data-ayah-key].is-selected")).toHaveCount(0);
      await swipeAyah(8, 72);
      await expect(view).toHaveAttribute("data-page-number", "128");
      await ayah.tap();
      await expect(ayah).toHaveClass(/is-selected/);
      await touch.detach();
    });

    test(`${variant.value} reader retains page and selection across rotation and overlay controls`, async ({ page }) => {
      test.setTimeout(60_000);
      await page.emulateMedia({ reducedMotion: "reduce" });
      await page.goto("/ru/quran?surah=6");
      const layout = page.locator(".quran-page-layout").filter({ visible: true });
      const actions = page.getByRole("toolbar");
      await actions.getByRole("button", { name: "Настройки чтения", exact: true }).click();
      await page.getByLabel("Вариант Мусхафа").selectOption(variant.value);
      await page.getByRole("button", { name: "Открыть читалку", exact: true }).click();
      const stage = layout.locator(".mushaf-page-container");
      const view = stage.locator(variant.view);
      const sheet = stage.locator(".qf-mushaf-sheet");
      const ayah = stage.locator('[data-ayah-key="6:2"]').last();
      await expect(view).toHaveAttribute("data-page-number", "128");
      await ayah.tap();
      await expect(ayah).toHaveClass(/is-selected/);
      const portrait = (await sheet.boundingBox())!;
      expect(portrait.width).toBeCloseTo(390, 0);
      expect(portrait.y).toBeGreaterThanOrEqual(0);
      expect(portrait.y + portrait.height).toBeLessThanOrEqual(844);

      await page.setViewportSize({ width: 844, height: 390 });
      await expect(layout).toHaveClass(/is-reader-immersive/);
      await expect(layout).toHaveAttribute("data-reader-orientation", "landscape");
      await expect(stage).toHaveCSS("height", "390px");
      const landscape = (await sheet.boundingBox())!;
      expect(landscape.width).toBeCloseTo(844, 0);
      expect(landscape.height / landscape.width).toBeCloseTo(portrait.height / portrait.width, 2);
      expect(landscape.height).toBeGreaterThan(390);
      await stage.evaluate((element) => { element.scrollTop = 300; });
      await expect(stage).toHaveJSProperty("scrollTop", 300);
      await expect(view).toHaveAttribute("data-page-number", "128");
      await expect(ayah).toHaveClass(/is-selected/);

      const notes = actions.getByRole("button", { name: "Перевод и тафсир", exact: true });
      await notes.click();
      const dialog = page.getByRole("dialog");
      await expect(dialog).toBeVisible();
      const panelBox = (await dialog.boundingBox())!;
      expect(panelBox.y).toBe(0);
      expect(panelBox.height).toBe(390);
      expect(panelBox.x).toBeGreaterThanOrEqual(0);
      expect(panelBox.x + panelBox.width).toBeLessThanOrEqual(844);
      const close = dialog.getByRole("button", { name: "Закрыть", exact: true });
      await expect(close).toBeFocused();
      const closeBox = await close.boundingBox();
      await dialog.locator(".reader-panel-body").evaluate((element) => { element.scrollTop = element.scrollHeight; });
      expect(await close.boundingBox()).toEqual(closeBox);
      await page.keyboard.press("Shift+Tab");
      expect(await dialog.evaluate((element) => element.contains(document.activeElement))).toBe(true);
      await expect(stage).toHaveJSProperty("inert", true);
      await page.keyboard.press("Escape");
      await expect(notes).toBeFocused();
      await page.setViewportSize({ width: 390, height: 700 });
      await expect(layout).toHaveAttribute("data-reader-orientation", "portrait");
      await expect(stage).toHaveCSS("height", "700px");
      await expect(stage).toHaveJSProperty("scrollTop", 0);
      await expect(view).toHaveAttribute("data-page-number", "128");
      await expect(ayah).toHaveClass(/is-selected/);
      await actions.getByRole("button", { name: "Перевод и тафсир", exact: true }).click();
      await expect(page.getByRole("dialog").getByText("Хвала Аллаху", { exact: true })).toBeVisible();
      await page.keyboard.press("Escape");
      await stage.tap({ position: { x: 5, y: 5 } });
      await expect(actions.getByRole("button")).toHaveCount(1);
      await actions.getByRole("button", { name: "Меню читалки", exact: true }).click();
      await actions.getByRole("button", { name: "Выйти из читалки", exact: true }).click();
      await expect(layout).not.toHaveClass(/is-reader-immersive/);
      await expect(page.locator(".app-header")).toBeVisible();
      await page.getByRole("button", { name: "Открыть читалку", exact: true }).click();
      await expect(layout).toHaveClass(/is-reader-immersive/);
      await expect(view).toHaveAttribute("data-page-number", "128");
      await expect(ayah).toHaveClass(/is-selected/);
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(390);
    });
  }
});

test("quran navigation exposes juz, hizb, rub and exact ayah jumps", async ({ page }) => {
  await page.setViewportSize({ width: 900, height: 600 });
  const nextSurah = {
    ...surah,
    id: "00000000-0000-7000-8000-000000000007",
    number: 7,
    name_ar: "الأعراف",
    name_en: "Al-A'raf",
    name_ru: "Аль-Араф",
    ayah_count: 1,
    first_page: 151,
  };
  const nextSurahAyah = {
    ...ayahs[0],
    id: "00000000-0000-7000-8200-000000000007",
    surah_number: 7,
    text_uthmani: "المص",
    pages: [151],
  };
  await page.route("**/api/v1/quran/editions/madani-hafs/surahs", (route) =>
    route.fulfill({ json: [surah, nextSurah] }),
  );
  await page.route("**/api/v1/quran/editions/madani-hafs/surahs/7/ayahs", (route) =>
    route.fulfill({ json: [nextSurahAyah] }),
  );
  await page.route("**/api/v1/quran/foundation/mushafs/5/pages/151", (route) =>
    route.fulfill({json: {...foundationPage(5, 151), verse_mapping: {"7": "1"},
      words: foundationPage(5, 151).words.filter((word) => word.verse_id === 1)}}),
  );
  await page.goto("/quran?surah=6");

  await expect(page.getByLabel("Джуз (1-30)").locator("option")).toHaveCount(31);
  await expect(page.getByLabel("Хизб (1-60)").locator("option")).toHaveCount(61);
  await expect(page.getByLabel("Руб аль-хизб (1-240)").locator("option")).toHaveCount(241);
  await expect(page.getByLabel(/Аят суры/).locator("option")).toHaveCount(3);

  await page.getByRole("button", { name: "📜 Текст", exact: true }).click();
  await page.getByLabel("Выбор суры (1–114)").selectOption("7");
  await expect(page.getByRole("button", { name: /Текст/ })).toHaveClass(/btn-primary/);
  await expect(page.locator(".qf-mushaf-view")).toHaveCount(0);
  await expect(page.locator("#quran-ayah-7-1")).toHaveClass(/is-navigation-target/);
  await expect(page.locator("#quran-ayah-7-1 .quran-arabic-text")).toContainText("المص");

  await page.getByLabel("Выбор суры (1–114)").selectOption("6");
  await expect(page.getByLabel(/Аят суры/).locator("option")).toHaveCount(3);
  await page.getByLabel(/Аят суры/).selectOption("2");
  await expect(page.getByRole("button", { name: /Текст/ })).toHaveClass(/btn-primary/);
  await expect(page.locator(".qf-mushaf-view")).toHaveCount(0);
  await expect(page.locator("#quran-ayah-6-2")).toHaveClass(/is-navigation-target/);
  await expect(page.locator("#quran-ayah-6-2 .quran-arabic-text")).toContainText(
    "هُوَ ٱلَّذِى خَلَقَكُم",
  );
  await expect.poll(() => page.locator("#quran-ayah-6-2").evaluate((element) => {
    const rect = element.getBoundingClientRect();
    return rect.top < window.innerHeight && rect.bottom > 0;
  })).toBe(true);

  await page.getByRole("button", { name: /Мусхаф/ }).click();
  await page.getByLabel("Выбор суры (1–114)").selectOption("7");
  await expect(page.getByRole("button", { name: /Мусхаф/ })).toHaveClass(/btn-primary/);
  await expect(page.locator(".qf-mushaf-view")).toHaveAttribute("data-page-number", "151");
  const selectedMushafAyah = page.getByRole("button", { name: "Аят 7:1", exact: true });
  await expect(selectedMushafAyah).toHaveClass(/is-selected/);
  await expect(selectedMushafAyah).toHaveAttribute("aria-pressed", "true");
  await expect.poll(() => selectedMushafAyah.evaluate((element) => {
    const rect = element.getBoundingClientRect();
    return rect.top < window.innerHeight && rect.bottom > 0;
  })).toBe(true);

  await page.getByLabel("Выбор суры (1–114)").selectOption("6");
  await expect(page.locator(".qf-mushaf-view")).toHaveAttribute("data-page-number", "128");
  await expect(page.locator('[data-ayah-key="6:1"].is-selected')).toHaveCount(1);
  await page.getByLabel(/Аят суры/).selectOption("2");
  await expect(page.locator(".qf-mushaf-view")).toHaveAttribute("data-page-number", "128");
  await expect(page.locator('[data-ayah-key="6:2"].is-selected')).toHaveCount(2);

  await page.getByLabel("Хизб (1-60)").selectOption("13");
  await expect(page.locator(".qf-mushaf-view")).toHaveAttribute("data-page-number", "129");
  await expect(page.locator('[data-ayah-key="6:2"].is-selected')).toHaveCount(2);
});


test.describe("Selected ayah controls in the mobile reader", () => {
  test.use({ viewport: { width: 390, height: 844 } });

  async function turnPage(page: Page) {
    const stage = page.locator(".mushaf-page-container").filter({ visible: true });
    await stage.dispatchEvent("pointerdown", { pointerId: 9, pointerType: "touch", isPrimary: true, clientX: 70, clientY: 360 });
    await stage.dispatchEvent("pointerup", { pointerId: 9, pointerType: "touch", isPrimary: true, clientX: 250, clientY: 360 });
    await expect(stage.locator(".mushaf-page-turn .qf-mushaf-view")).toHaveAttribute("data-page-number", "129");
  }

  test("plays only the selected ayah, pauses on selection and page changes, and retains audio settings", async ({ page }) => {
    await page.goto("/ru/quran?surah=6");
    const layout = page.locator(".quran-page-layout").filter({ visible: true });
    const actions = page.getByRole("toolbar");
    const audio = layout.locator(".mushaf-audio-now-playing audio");
    await expect(actions.getByRole("button", { name: "Выберите аят на странице" })).toBeDisabled();
    await layout.locator('[data-ayah-key="6:2"]').last().click();
    await actions.getByRole("button", { name: "Воспроизвести аят 6:2", exact: true }).click();
    await expect(actions.getByRole("button", { name: "Пауза — аят 6:2" })).toBeVisible();
    await expect(audio).toHaveAttribute("src", tracks[5].asset.url);
    await expect(audio).toHaveJSProperty("currentTime", 1);
    await audio.evaluate((element) => { (element as HTMLAudioElement).currentTime = 1.4; });
    await actions.getByRole("button", { name: "Пауза — аят 6:2" }).click();
    await actions.getByRole("button", { name: "Воспроизвести аят 6:2" }).click();
    await expect(audio).toHaveJSProperty("currentTime", 1.4);
    await audio.evaluate((element) => { (element as HTMLAudioElement).currentTime = 1.98; element.dispatchEvent(new Event("timeupdate")); });
    await expect(actions.getByRole("button", { name: "Воспроизвести аят 6:2" })).toBeVisible();
    await expect(audio).toHaveJSProperty("currentTime", 2);
    await actions.getByRole("button", { name: "Воспроизвести аят 6:2" }).click();
    await layout.locator('[data-ayah-key="6:1"]').click();
    await expect.poll(() => page.evaluate(() => navigator.mediaSession.playbackState)).toBe("paused");
    await expect(layout.locator(".is-playing[data-ayah-key]")).toHaveCount(0);
    await actions.getByRole("button", { name: "Воспроизвести аят 6:1" }).click();
    await expect(audio).toHaveJSProperty("currentTime", 0);
    await turnPage(page);
    await expect.poll(() => page.evaluate(() => navigator.mediaSession.playbackState)).toBe("paused");
    await expect(actions.getByRole("button", { name: "Выберите аят на странице" })).toBeDisabled();
    await layout.locator('[data-ayah-key="6:2"]').last().click();
    await actions.getByRole("button", { name: "Воспроизвести аят 6:2" }).click();
    await expect(actions.getByRole("button", { name: "Пауза — аят 6:2" })).toBeVisible();
    await expect(layout.locator(".mushaf-page-turn .qf-mushaf-view")).toHaveAttribute("data-page-number", "129");
    await actions.getByRole("button", { name: "Настройки чтения", exact: true }).click();
    await expect.poll(() => page.evaluate(() => navigator.mediaSession.playbackState)).toBe("paused");
    await layout.locator(".reader-settings-navigation").getByRole("button", { name: "Аудио", exact: true }).click();
    const audioPanel = layout.locator(".reader-panel-audio");
    await audioPanel.getByRole("button", { name: "Повтор, диапазон и таймер", exact: true }).click();
    await audioPanel.getByLabel("Скорость").selectOption("1.5");
    await page.getByRole("button", { name: "Открыть читалку", exact: true }).click();
    await actions.getByRole("button", { name: "Воспроизвести аят 6:2" }).click();
    await expect(audio).toHaveJSProperty("playbackRate", 1.5);
    await expect(layout.locator(".mushaf-page-turn .qf-mushaf-view")).toHaveAttribute("data-page-number", "129");
  });

  test("synchronizes a page deep link with the selected ayah and surah settings", async ({ page }) => {
    await page.goto("/ru/quran?surah=1&page=128");
    const layout = page.locator(".quran-page-layout").filter({ visible: true });
    const actions = page.getByRole("toolbar");
    await expect(layout.locator("#surah-navigation")).toHaveValue("6");
    await layout.locator('[data-ayah-key="6:2"]').last().click();
    await actions.getByRole("button", { name: "Воспроизвести аят 6:2" }).click();
    await expect(actions.getByRole("button", { name: "Пауза — аят 6:2" })).toBeVisible();
    await expect(layout.locator("audio")).toHaveAttribute("src", tracks[5].asset.url);
    await expect(layout.locator("audio")).toHaveJSProperty("currentTime", 1);
    await expect(layout.locator(".mushaf-page-turn .qf-mushaf-view")).toHaveAttribute("data-page-number", "128");
    await expect(layout.locator("#surah-navigation")).toHaveValue("6");
  });

  test("a delayed timing preparation stays paused after the reader moves to another page", async ({ page }) => {
    let release!: () => void;
    const held = new Promise<void>((resolve) => { release = resolve; });
    let requested = false;
    await page.route(`**/api/v1/recitations/${recitation.id}/surahs/6`, async (route) => {
      requested = true;
      await held;
      await route.fallback();
    });
    await page.goto("/ru/quran?surah=1&page=128");
    const layout = page.locator(".quran-page-layout").filter({ visible: true });
    await layout.locator('[data-ayah-key="6:2"]').last().click();
    await expect(page.getByRole("toolbar").getByRole("button", { name: "Воспроизвести аят 6:2" })).toBeDisabled();
    await expect.poll(() => requested).toBe(true);
    await turnPage(page);
    const response = page.waitForResponse(`**/api/v1/recitations/${recitation.id}/surahs/6`);
    release();
    await response;
    await expect(page.getByRole("toolbar").getByRole("button", { name: "Выберите аят на странице" })).toBeDisabled();
    await expect(layout.locator("audio")).toHaveAttribute("src", tracks[5].asset.url);
    await expect.poll(() => page.evaluate(() => navigator.mediaSession.playbackState)).not.toBe("playing");
  });

  test("system playback controls follow the selection even with the reader toolbar folded", async ({ page }) => {
    await page.goto("/ru/quran?surah=6");
    const layout = page.locator(".quran-page-layout").filter({ visible: true });
    const actions = page.getByRole("toolbar");
    const systemAction = (name: string) => page.evaluate((action) => {
      const handlers = (window as unknown as { __mediaSessionHandlers: Record<string, (() => void) | null> }).__mediaSessionHandlers;
      handlers[action]?.();
    }, name);
    await layout.locator('[data-ayah-key="6:2"]').last().click();
    await actions.getByRole("button", { name: "Воспроизвести аят 6:2" }).click();
    await expect(actions.getByRole("button", { name: "Пауза — аят 6:2" })).toBeVisible();
    await turnPage(page);
    await systemAction("play");
    await systemAction("nexttrack");
    await expect.poll(() => page.evaluate(() => navigator.mediaSession.playbackState)).toBe("paused");
    await layout.locator('[data-ayah-key="6:2"]').last().click();
    await layout.locator(".mushaf-page-container").click({ position: { x: 5, y: 5 } });
    await expect(actions).toHaveClass(/is-folded/);
    await systemAction("play");
    await expect.poll(() => page.evaluate(() => navigator.mediaSession.playbackState)).toBe("playing");
    await actions.getByRole("button", { name: "Меню читалки", exact: true }).click();
    await expect(actions.getByRole("button", { name: "Пауза — аят 6:2" })).toBeVisible();
    await expect(layout.locator(".mushaf-page-turn .qf-mushaf-view")).toHaveAttribute("data-page-number", "129");
  });

  test("late media metadata cannot restart playback after page navigation", async ({ page }) => {
    await page.goto("/ru/quran?surah=1&page=128");
    const layout = page.locator(".quran-page-layout").filter({ visible: true });
    await expect(layout.locator("audio")).toHaveAttribute("src", tracks[5].asset.url);
    await page.evaluate(() => {
      Object.defineProperty(HTMLMediaElement.prototype, "load", { configurable: true, value() {} });
    });
    await layout.locator("#mushaf-recitation").selectOption(alternateRecitation.id, { force: true });
    await layout.locator('[data-ayah-key="6:2"]').last().click();
    await page.getByRole("toolbar").getByRole("button", { name: "Воспроизвести аят 6:2" }).click();
    await expect(layout.locator("audio")).toHaveAttribute("src", alternateTracks[5].asset.url);
    await turnPage(page);
    await layout.locator("audio").dispatchEvent("loadedmetadata");
    await expect.poll(() => page.evaluate(() => navigator.mediaSession.playbackState)).not.toBe("playing");
    await expect(page.getByRole("toolbar").getByRole("button", { name: "Выберите аят на странице" })).toBeDisabled();
    await expect(layout.locator(".mushaf-page-turn .qf-mushaf-view")).toHaveAttribute("data-page-number", "129");
  });

  test("missing ayah timings never fall back to playing a whole surah", async ({ page }) => {
    await page.route(`**/api/v1/recitations/${recitation.id}/surahs/6`, (route) => route.fulfill({ json: { track: tracks[5], segments: [] } }));
    await page.goto("/ru/quran?surah=6");
    const layout = page.locator(".quran-page-layout").filter({ visible: true });
    await layout.locator('[data-ayah-key="6:2"]').last().click();
    const actions = page.getByRole("toolbar");
    await actions.getByRole("button", { name: "Воспроизвести аят 6:2" }).click();
    await expect(actions.getByText(/Не удалось воспроизвести аят/)).toBeVisible();
    await expect.poll(() => page.evaluate(() => navigator.mediaSession.playbackState)).not.toBe("playing");
    await expect(actions.getByRole("button", { name: "Воспроизвести аят 6:2" })).toBeEnabled();
  });
});

test.describe("Mushaf preloading and responsive gestures", () => {
  test.use({ hasTouch: true, viewport: { width: 390, height: 844 } });

  for (const variant of ["1", "5"]) {
    test(`${variant} preloads two pages in both directions and turns without another page request`, async ({ page }) => {
      await page.addInitScript((value) => localStorage.setItem("iqro_quran_mushaf_variant_v1", value), variant);
      const pageRequests = new Map<number, number>();
      const pattern = `**/api/v1/quran/foundation/mushafs/${variant}/pages/*`;
      await page.route(pattern, async (route) => {
        const number = Number(new URL(route.request().url()).pathname.split("/").at(-1));
        pageRequests.set(number, (pageRequests.get(number) || 0) + 1);
        return route.fallback();
      });
      await page.goto("/ru/quran?surah=6&page=128");
      const layout = page.locator(".quran-page-layout").filter({ visible: true });
      const stage = layout.locator(".mushaf-page-container");
      const view = stage.locator(".mushaf-page-turn .qf-mushaf-view");
      await expect(view).toHaveAttribute("data-page-number", "128");
      await expect.poll(() => [...pageRequests.keys()].sort((a, b) => a - b)).toEqual([126, 127, 128, 129, 130]);
        await expect.poll(() => page.evaluate((id) => [...document.fonts].filter((face) => face.status === "loaded" && face.family.startsWith(`qf-mushaf-${id}`)).length, variant)).toBe(variant === "1" ? 5 : 1);
      // A second HTTP request for a warm page would fail rather than mask a cache miss.
      await page.route(pattern, async (route) => {
        const number = Number(new URL(route.request().url()).pathname.split("/").at(-1));
        if (number >= 128 && number <= 130) {
          pageRequests.set(number, (pageRequests.get(number) || 0) + 1);
          return route.fulfill({ status: 503, json: { detail: "Warm navigation must not fetch again" } });
        }
        await route.fallback();
      });
      for (const number of [129, 130, 129, 128]) {
        const current = Number(await view.getAttribute("data-page-number"));
        const dx = number > current ? 32 : -32;
        await stage.dispatchEvent("pointerdown", { pointerId: 91, pointerType: "touch", isPrimary: true, clientX: 180, clientY: 300 });
        await stage.dispatchEvent("pointerup", { pointerId: 91, pointerType: "touch", isPrimary: true, clientX: 180 + dx, clientY: 300 });
        await expect(view).toHaveAttribute("data-page-number", String(number));
        await expect(view).toHaveAttribute("data-font-status", "ready");
        await expect(stage.locator(".qf-mushaf-page-loading, .qf-mushaf-font-loading")).toHaveCount(0);
        expect(pageRequests.get(number)).toBe(1);
      }
    });
  }

  test("landscape settings can collapse and reader controls have an explicit hide action", async ({ page }) => {
    await page.goto("/ru/quran?surah=6");
    const layout = page.locator(".quran-page-layout").filter({ visible: true });
    await page.getByRole("toolbar").getByRole("button", { name: "Настройки чтения", exact: true }).click();
    const settings = layout.locator(".quran-reader-settings");
    await settings.locator("summary").click();
    await page.setViewportSize({ width: 844, height: 390 });
    await expect(settings.locator("summary")).toBeVisible();
    await expect(settings).toHaveJSProperty("open", false);
    await expect(settings.locator("#mushaf-variant")).toBeHidden();
    await settings.locator("summary").click();
    await expect(settings.locator("#mushaf-variant")).toBeVisible();
    await settings.locator("summary").click();
    await page.getByRole("button", { name: "Открыть читалку", exact: true }).click();
    const actions = page.getByRole("toolbar");
    await actions.getByRole("button", { name: "Свернуть меню читалки", exact: true }).click();
    await expect(actions.getByRole("button")).toHaveCount(1);
    await expect(settings).toBeHidden();
    await page.setViewportSize({ width: 390, height: 844 });
    await expect(actions.getByRole("button")).toHaveCount(1);
    await actions.getByRole("button", { name: "Меню читалки", exact: true }).click();
    await expect(actions.getByRole("button", { name: "Настройки чтения", exact: true })).toBeVisible();
  });

  test("short touch flicks respond in landscape while vertical and two-finger gestures do not turn pages", async ({ page }) => {
    await page.emulateMedia({ reducedMotion: "reduce" });
    await page.goto("/ru/quran?surah=6&page=128");
    await page.setViewportSize({ width: 844, height: 390 });
    const layout = page.locator(".quran-page-layout").filter({ visible: true });
    const stage = layout.locator(".mushaf-page-container");
    const view = stage.locator(".mushaf-page-turn .qf-mushaf-view");
    const touch = await page.context().newCDPSession(page);
    const region = stage.locator('[data-ayah-key="6:2"]').last();
    await region.scrollIntoViewIfNeeded();
    const box = (await region.boundingBox())!;
    const x = box.x + box.width / 2;
    const y = Math.min(180, box.y + box.height / 2);
    await touch.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x, y }] });
    await touch.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ x: x + 24, y }] });
    await expect(stage).toHaveAttribute("data-dragging", "true");
    await expect(view).toHaveAttribute("data-page-number", "128");
    await touch.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    await expect(view).toHaveAttribute("data-page-number", "129");
    await expect(stage.locator("[data-ayah-key].is-selected")).toHaveCount(0);
    await touch.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: 300, y: 150 }] });
    await touch.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ x: 306, y: 70 }] });
    await touch.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    await expect(view).toHaveAttribute("data-page-number", "129");
    await touch.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: 250, y: 100, id: 1 }, { x: 350, y: 100, id: 2 }] });
    await touch.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ x: 310, y: 100, id: 1 }, { x: 410, y: 100, id: 2 }] });
    await touch.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
    await expect(view).toHaveAttribute("data-page-number", "129");
    await touch.detach();
  });
});

test.describe("Visible Mushaf page transitions", () => {
  test.use({ hasTouch: true });

  for (const variant of ["1", "5"]) {
    for (const landscape of [false, true]) {
      test(`${variant} slides both sheets in ${landscape ? "landscape" : "portrait"} and accepts an interrupted reverse swipe`, async ({ page }, testInfo) => {
        await page.setViewportSize(landscape ? { width: 844, height: 390 } : { width: 390, height: 844 });
        await page.emulateMedia({ reducedMotion: "no-preference" });
        await page.addInitScript((value) => localStorage.setItem("iqro_quran_mushaf_variant_v1", value), variant);
        const prefetched = page.waitForResponse((response) => response.url().includes(`/foundation/mushafs/${variant}/pages/129`));
        await page.goto("/ru/quran?surah=6&page=128");
        await prefetched;
        const stage = page.locator(".mushaf-page-container").filter({ visible: true });
        const current = stage.locator(".mushaf-page-turn");
        const outgoing = stage.locator(".mushaf-page-outgoing");
        const viewSelector = ".qf-mushaf-view";
        await expect(current.locator(viewSelector)).toHaveAttribute("data-page-number", "128");
        await expect(current).toHaveCSS("animation-name", "none");
        {
          await expect.poll(() => page.evaluate((id) => [...document.fonts].some((font) =>
            font.status === "loaded" && font.family === (id === "1" ? "qf-mushaf-1-page-129" : "qf-mushaf-5")), variant)).toBe(true);
        }

        // Pause the CSS timeline at a visible point before taking measurements.
        await page.addStyleTag({ content: ".mushaf-page-transition[data-turning] > * { animation-play-state: paused !important; }" });
        const swipe = async (dx: number) => {
          await stage.dispatchEvent("pointerdown", { pointerId: 31, pointerType: "touch", isPrimary: true, clientX: 180, clientY: 160 });
          await stage.dispatchEvent("pointerup", { pointerId: 31, pointerType: "touch", isPrimary: true, clientX: 180 + dx, clientY: 160 });
        };
        await swipe(48);
        await expect(current.locator(viewSelector)).toHaveAttribute("data-page-number", "129");
        await expect(outgoing.locator(viewSelector)).toHaveAttribute("data-page-number", "128");
        await expect(outgoing).toHaveJSProperty("inert", true);
        await expect(outgoing).toHaveAttribute("aria-hidden", "true");
        const measure = async () => stage.evaluate((element) => {
          const live = element.querySelector<HTMLElement>(".mushaf-page-turn")!;
          const old = element.querySelector<HTMLElement>(".mushaf-page-outgoing")!;
          for (const sheet of [live, old]) for (const animation of sheet.getAnimations()) animation.currentTime = 100;
          return {
            liveX: new DOMMatrix(getComputedStyle(live).transform).m41,
            oldX: new DOMMatrix(getComputedStyle(old).transform).m41,
            width: live.getBoundingClientRect().width,
          };
        });
        const next = await measure();
        expect(next.liveX).toBeLessThan(-next.width * .1);
        expect(next.oldX).toBeGreaterThan(next.width * .1);
        expect(next.oldX - next.liveX).toBeCloseTo(next.width, 0);
        // Do not wait for this transition: a reverse swipe must replace it now.
        await swipe(-48);
        await expect(current.locator(viewSelector)).toHaveAttribute("data-page-number", "128");
        await expect(outgoing.locator(viewSelector)).toHaveAttribute("data-page-number", "129");
        const previous = await measure();
        expect(previous.liveX).toBeGreaterThan(previous.width * .1);
        expect(previous.oldX).toBeLessThan(-previous.width * .1);
        if (variant === "5") await page.screenshot({ path: testInfo.outputPath("page-turn-midpoint.png") });
        await current.evaluate((element) => { for (const animation of element.getAnimations()) animation.finish(); });
        await expect(outgoing).toHaveCount(0);
        await expect(current).toHaveCSS("transform", "none");
        await current.locator('[data-ayah-key="6:2"]').last().tap();
        await expect(current.locator('[data-ayah-key="6:2"].is-selected')).not.toHaveCount(0);
        await expect(current).toHaveCSS("animation-name", "none");
        expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(landscape ? 844 : 390);

        await page.emulateMedia({ reducedMotion: "reduce" });
        await swipe(48);
        await expect(current.locator(viewSelector)).toHaveAttribute("data-page-number", "129");
        await expect(outgoing).toHaveCount(0);
        await expect(current).toHaveCSS("animation-name", "none");
      });
    }
  }
});

test.describe("Landscape gestures through browser hit testing", () => {
  const android = devices["Pixel 7 landscape"];
  test.use({
    viewport: android.viewport,
    deviceScaleFactor: android.deviceScaleFactor,
    userAgent: android.userAgent,
    isMobile: true,
    hasTouch: true,
  });

  for (const variant of ["5"]) {
    for (const input of ["mouse", "touch"]) {
      test(`${input} drags across ${variant} ayahs turn both ways without selecting`, async ({ page }) => {
        await page.emulateMedia({ reducedMotion: "no-preference" });
        await page.addInitScript((value) => localStorage.setItem("iqro_quran_mushaf_variant_v1", value), variant);
        await page.goto("/ru/quran?surah=6&page=128");
        const stage = page.locator(".mushaf-page-container").filter({ visible: true });
        const current = stage.locator(".mushaf-page-turn");
        const view = current.locator(".qf-mushaf-view");
        await expect(view).toHaveAttribute("data-page-number", "128");
        await page.getByRole("button", { name: "Свернуть меню читалки", exact: true }).click();
        const touch = await page.context().newCDPSession(page);
        const startOnAyah = async () => {
          const ayah = current.locator('[data-ayah-key="6:2"]').last();
          await ayah.evaluate((element) => element.scrollIntoView({ block: "center", behavior: "instant" }));
          const box = (await ayah.boundingBox())!;
          const point = { x: box.x + box.width / 2, y: box.y + box.height / 2 };
          expect(await page.evaluate(({ x, y }) => document.elementFromPoint(x, y)?.closest("[data-ayah-key]")?.getAttribute("data-ayah-key"), point)).toBe("6:2");
          return point;
        };
        const drag = async (dx: number, dy: number, steps = 8, origin?: { x: number; y: number }) => {
          const { x, y } = origin ?? await startOnAyah();
          if (input === "mouse") {
            await page.mouse.move(x, y);
            await page.mouse.down();
          } else {
            await touch.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x, y }] });
          }
          for (let step = 1; step <= steps; step += 1) {
            const point = { x: x + dx * step / steps, y: y + dy * step / steps };
            if (input === "mouse") await page.mouse.move(point.x, point.y);
            else await touch.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [point] });
            await page.waitForTimeout(20);
          }
          if (input === "mouse") await page.mouse.up();
          else await touch.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
        };
        for (const [dx, number] of [[120, 129], [-120, 128], [75, 129], [-75, 128]]) {
          await drag(dx, 20);
          await expect(view).toHaveAttribute("data-page-number", String(number));
          await expect(current.locator("[data-ayah-key].is-selected")).toHaveCount(0);
          await expect(stage.locator(".mushaf-page-outgoing")).toHaveCount(0);
          expect(await page.evaluate(() => window.getSelection()?.toString())).toBe("");
        }
        // Keep the finger at the same screen position and reverse while the
        // first animation is still moving. Do not move a locator into view.
        const origin = await startOnAyah();
        await drag(72, 0, 3, origin);
        await expect(view).toHaveAttribute("data-page-number", "129");
        await drag(-72, 0, 3, origin);
        await expect(view).toHaveAttribute("data-page-number", "128");
        await expect(stage.locator(".mushaf-page-outgoing")).toHaveCount(0);
        await expect(current.locator("[data-ayah-key].is-selected")).toHaveCount(0);
        // A slow movement too short to turn must not fall through into an ayah click.
        await drag(20, 0, 16);
        await expect(view).toHaveAttribute("data-page-number", "128");
        await expect(current.locator("[data-ayah-key].is-selected")).toHaveCount(0);
        if (input === "touch") {
          const scrollBefore = await stage.evaluate((element) => element.scrollTop);
          await drag(6, -80);
          await expect.poll(() => stage.evaluate((element) => element.scrollTop)).toBeGreaterThan(scrollBefore);
          await expect(view).toHaveAttribute("data-page-number", "128");
          await expect(current.locator("[data-ayah-key].is-selected")).toHaveCount(0);
          // A tap during inertial scrolling stops the scroll instead of selecting.
          // Wait for the viewport to settle before testing a fresh ayah tap.
          await expect.poll(async () => {
            const top = await stage.evaluate((element) => element.scrollTop);
            await page.waitForTimeout(150);
            return stage.evaluate((element, previous) => element.scrollTop === previous, top);
          }).toBe(true);
        }
        const point = await startOnAyah();
        if (input === "mouse") await page.mouse.click(point.x, point.y);
        else await page.touchscreen.tap(point.x, point.y);
        await expect(current.locator('[data-ayah-key="6:2"].is-selected')).not.toHaveCount(0);
        await touch.detach();
      });
    }
  }

  test("touch completion survives a cancelled pointer stream and suppresses compatibility clicks", async ({ page }) => {
    await page.goto("/ru/quran?surah=6&page=128");
    const stage = page.locator(".mushaf-page-container").filter({ visible: true });
    const view = stage.locator(".mushaf-page-turn .qf-mushaf-view");
    await expect(view).toHaveAttribute("data-page-number", "128");
    const ayah = stage.locator('.mushaf-page-turn [data-ayah-key="6:2"]').last();
    await ayah.evaluate((target) => {
      // Event-order regression, separate from the native input tests above:
      // mobile browsers may end the pointer stream before touchend arrives.
      const point = (x: number) => ({ identifier: 42, target, clientX: x, clientY: 150 });
      const emitTouch = (type: string, x: number, ended = false) => {
        // WebKit exposes native Touch objects but no public Touch constructor.
        const event = new Event(type, { bubbles: true, cancelable: true });
        Object.defineProperties(event, {
          touches: { value: ended ? [] : [point(x)] },
          changedTouches: { value: [point(x)] },
        });
        target.dispatchEvent(event);
      };
      target.dispatchEvent(new PointerEvent("pointerdown", { bubbles: true, pointerId: 42, pointerType: "touch", isPrimary: true, clientX: 200, clientY: 150 }));
      emitTouch("touchstart", 200);
      target.dispatchEvent(new PointerEvent("pointercancel", { bubbles: true, pointerId: 42, pointerType: "touch", isPrimary: true }));
      emitTouch("touchmove", 320);
      emitTouch("touchend", 320, true);
    });
    await expect(view).toHaveAttribute("data-page-number", "129");
    for (const detail of [0, 1, 0, 1]) {
      await ayah.dispatchEvent("click", { detail });
      await expect(stage.locator(".mushaf-page-turn [data-ayah-key].is-selected")).toHaveCount(0);
    }
    await ayah.focus();
    await page.keyboard.press("Enter");
    await expect(ayah).toHaveClass(/is-selected/);
    await stage.press("ArrowLeft");
    await expect(view).toHaveAttribute("data-page-number", "128");
    await ayah.tap();
    await expect(ayah).toHaveClass(/is-selected/);
  });
});

test("explicit page jump cancels the pending verse after changing layout", async ({ page }) => {
  await page.goto("/ru/quran?surah=6&page=128");
  await expect(page.locator('.qf-mushaf-view[data-mushaf-id="5"]')).toBeVisible();
  await page.locator('[data-ayah-key="6:2"]').last().click();
  await page.locator("#mushaf-variant").selectOption("1");
  await page.locator("#mushaf-page-jump").fill("1");
  await expect(page.locator('.qf-mushaf-view[data-mushaf-id="1"]')).toHaveAttribute("data-page-number", "1");
  await expect(page.locator("#mushaf-page-jump")).toHaveValue("1");
});

test.describe("Landscape Mushaf bottom space", () => {
  test.use({ isMobile: true, hasTouch: true });

  // Below the last line: the sheet's own margin, then only the visible bottom
  // overlays (reader bar, tajweed chips) and a small gap.
  const expectFittedBottom = async (page: Page) => {
    const stage = page.locator(".mushaf-page-container").filter({ visible: true });
    await expect(stage.locator(".qf-mushaf-line").last()).toBeVisible();
    await expect.poll(() => stage.evaluate((element) => {
      element.scrollTop = element.scrollHeight;
      const end = element.getBoundingClientRect().bottom;
      const line = [...element.querySelectorAll(".qf-mushaf-line")].at(-1)!.getBoundingClientRect();
      const sheet = element.querySelector(".qf-mushaf-sheet")!.getBoundingClientRect();
      const overlays = [...document.querySelectorAll(".reader-actions, .mushaf-tajweed-legend")]
        .filter((overlay) => overlay.getClientRects().length > 0)
        .map((overlay) => end - overlay.getBoundingClientRect().top);
      const reserve = Math.max(0, ...overlays);
      const lastLine = end - line.bottom;
      const spareBelowLastLine = Math.round(lastLine - (sheet.bottom - line.bottom) - reserve);
      return {
        clearOfOverlays: lastLine >= reserve,
        spareBelowLastLine,
        withinGap: spareBelowLastLine >= 0 && spareBelowLastLine <= 16,
        horizontalScroll: element.scrollWidth - element.clientWidth
          + document.documentElement.scrollWidth - document.documentElement.clientWidth,
      };
    })).toMatchObject({ clearOfOverlays: true, withinGap: true, horizontalScroll: 0 });
  };

  const expectBothControlStates = async (page: Page) => {
    const layout = page.locator(".quran-page-layout").filter({ visible: true });
    await expect(layout).toHaveAttribute("data-reader-orientation", "landscape");
    await expect(layout).toHaveClass(/is-reader-immersive/);
    await expectFittedBottom(page);
    await layout.locator(".mushaf-page-container").tap({ position: { x: 5, y: 5 } });
    await expect(layout.locator(".reader-actions")).toHaveClass(/is-folded/);
    await expectFittedBottom(page);
    await expect(layout.locator(".mushaf-page-arrow")).toHaveCount(2);
    for (const arrow of await layout.locator(".mushaf-page-arrow").all()) await expect(arrow).toBeHidden();
  };

  for (const viewport of [{ width: 740, height: 360 }, { width: 844, height: 390 }, { width: 915, height: 412 }]) {
    test(`${viewport.width}x${viewport.height} leaves no empty band below the page`, async ({ page }) => {
      await page.setViewportSize(viewport);
      await page.goto("/ru/quran?surah=6&page=128");
      await expectBothControlStates(page);
    });
  }

  test("folded controls leave room for the tajweed legend", async ({ page }) => {
    await installTajweedMocks(page);
    await page.setViewportSize({ width: 844, height: 390 });
    await page.goto("/ru/quran?surah=6&page=128");
    await expectBothControlStates(page);
    await expect(page.getByTestId("tajweed-legend")).toBeVisible();
  });

  test("a portrait reader turned to landscape fits a 16-line RTL page", async ({ page }) => {
    await page.route("**/api/v1/quran/foundation/mushafs", (route) =>
      route.fulfill({ json: foundationMushafs.map((mushaf) => ({ ...mushaf, lines_per_page: 16 })) }));
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto("/ar/quran?surah=6&page=128");
    const stage = page.locator(".mushaf-page-container").filter({ visible: true });
    await expect(stage.locator(".qf-mushaf-sheet")).toHaveAttribute("style", /repeat\(16,/);
    await page.setViewportSize({ width: 844, height: 390 });
    await expectBothControlStates(page);
  });
});

test.describe("Desktop Mushaf page arrows", () => {
  for (const { locale, next, previous } of [
    { locale: "ru", next: "Следующая страница", previous: "Предыдущая страница" },
    { locale: "ar", next: "الصفحة التالية", previous: "الصفحة السابقة" },
  ]) {
    test(`${locale} turns pages with small arrows beside the sheet, next on the left`, async ({ page }) => {
      await page.setViewportSize({ width: 1280, height: 800 });
      await page.goto(`/${locale}/quran?surah=6&page=128`);
      const surface = page.locator(".mushaf-reader-surface");
      const view = surface.locator(".qf-mushaf-view");
      await expect(view).toHaveAttribute("data-page-number", "128");
      await expect(surface.locator(".mushaf-page-navigation button")).toHaveCount(0);
      await expect(surface.locator(".mushaf-page-navigation-status")).toBeVisible();

      const nextArrow = surface.getByRole("button", { name: `${next} (129)`, exact: true });
      const previousArrow = surface.getByRole("button", { name: `${previous} (127)`, exact: true });
      const sheet = (await surface.locator(".qf-mushaf-sheet").boundingBox())!;
      const nextBox = (await nextArrow.boundingBox())!;
      const previousBox = (await previousArrow.boundingBox())!;
      // In the margins, mirrored by the Mushaf rather than by the interface direction.
      expect(nextBox.x + nextBox.width).toBeLessThanOrEqual(sheet.x);
      expect(previousBox.x).toBeGreaterThanOrEqual(sheet.x + sheet.width);
      for (const box of [nextBox, previousBox]) {
        expect(box.width).toBeGreaterThanOrEqual(44);
        expect(box.height).toBeGreaterThanOrEqual(44);
        expect(box.y + box.height / 2).toBeCloseTo(400, 0);
      }
      expect(await nextArrow.evaluate((element) => Number(getComputedStyle(element).opacity))).toBeLessThan(1);

      await nextArrow.click();
      await expect(view).toHaveAttribute("data-page-number", "129");
      await page.keyboard.press("Tab");
      const back = surface.getByRole("button", { name: `${previous} (128)`, exact: true });
      await expect(back).toBeFocused();
      expect(await back.evaluate((element) => element.matches(":focus-visible"))).toBe(true);
      await expect(back).toHaveCSS("outline-style", "solid");
      await page.keyboard.press("Enter");
      await expect(view).toHaveAttribute("data-page-number", "128");

      await surface.locator(".mushaf-page-container").focus();
      await page.keyboard.press("ArrowRight");
      await expect(view).toHaveAttribute("data-page-number", "129");
      await page.keyboard.press("ArrowLeft");
      await expect(view).toHaveAttribute("data-page-number", "128");
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(1280);
    });
  }

  test("the first page hides the arrow toward the previous page", async ({ page }) => {
    await page.setViewportSize({ width: 1280, height: 800 });
    await page.goto("/ru/quran?surah=1&page=1");
    const surface = page.locator(".mushaf-reader-surface");
    await expect(surface.locator(".qf-mushaf-view")).toHaveAttribute("data-page-number", "1");
    await expect(surface.getByRole("button", { name: "Следующая страница (2)", exact: true })).toBeVisible();
    await expect(surface.locator(".mushaf-page-arrow-rail.is-previous button")).toBeDisabled();
    await expect(surface.locator(".mushaf-page-arrow-rail.is-previous button")).toBeHidden();
  });
});
