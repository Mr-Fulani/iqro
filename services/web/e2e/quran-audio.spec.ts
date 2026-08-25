import { expect, Page, test } from "@playwright/test";
import { readFile } from "node:fs/promises";

const reciter = {
  id: "00000000-0000-7000-8000-000000000159",
  slug: "qf-159-maher-al-muaiqly",
  name_ar: "ماهر المعيقلي",
  name_en: "Maher al-Muaiqly",
  name_ru: "Махер аль-Муайкли",
  country_code: "SA",
};

const recitation = {
  id: "00000000-0000-7000-8000-000000001159",
  code: "qf-159-murattal",
  version: "2026.08.23-production",
  style: "murattal",
  reciter,
  quran_edition: {
    id: "00000000-0000-7000-8000-000000000001",
    code: "madani-hafs",
    content_version: "1.0.0",
    riwayah: "Hafs 'an Asim",
  },
  rights: { stream: true, offline_download: false },
  coverage: { track_count: 114, surah_count: 114, complete: true },
  timings: { available: true, segment_count: 6236 },
};

const tracks = Array.from({ length: 114 }, (_, index) => {
  const surah = index + 1;
  const asset = {
    url: `https://audio.example.test/${String(surah).padStart(3, "0")}.mp3`,
    content_type: "audio/mpeg",
    codec: "mp3",
    bitrate_kbps: 96,
    bytes: 720_000,
    sha256: null,
    etag: null,
    range_supported: false,
    immutable: false,
  };
  return {
    id: `00000000-0000-7000-8100-${String(surah).padStart(12, "0")}`,
    recitation_id: recitation.id,
    scope: "surah",
    surah_number: surah,
    juz_number: null,
    duration_ms: 60_000,
    offline_download_allowed: false,
    asset,
    renditions: [
      {
        id: `00000000-0000-7000-8200-${String(surah).padStart(12, "0")}`,
        quality: "standard",
        is_default: true,
        asset,
      },
    ],
  };
});

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

const page128 = {
  id: "00000000-0000-7000-8300-000000000128",
  edition_code: "madani-hafs",
  content_version: "1.0.0",
  number: 128,
  image_width: 900,
  image_height: 1400,
  checksum_sha256: "b".repeat(64),
  assets: [
    {
      url: "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='900' height='1400'/%3E",
      width: 900,
      height: 1400,
      format: "webp",
      bytes: 100,
    },
  ],
  regions: [
    {
      id: "region-6-1",
      ayah: { id: ayahs[0].id, surah: 6, number: 1 },
      reading_order: 1,
      polygon: [[0.1, 0.1], [0.9, 0.1], [0.9, 0.25], [0.1, 0.25]],
      x: 0.1,
      y: 0.1,
      width: 0.8,
      height: 0.15,
    },
    {
      id: "region-6-2-a",
      ayah: { id: ayahs[1].id, surah: 6, number: 2 },
      reading_order: 2,
      polygon: [[0.1, 0.3], [0.9, 0.3], [0.9, 0.45], [0.1, 0.45]],
      x: 0.1,
      y: 0.3,
      width: 0.8,
      height: 0.15,
    },
    {
      id: "region-6-2-b",
      ayah: { id: ayahs[1].id, surah: 6, number: 2 },
      reading_order: 3,
      polygon: [[0.1, 0.46], [0.6, 0.46], [0.6, 0.55], [0.1, 0.55]],
      x: 0.1,
      y: 0.46,
      width: 0.5,
      height: 0.09,
    },
  ],
};

const page129 = {
  ...page128,
  id: "00000000-0000-7000-8300-000000000129",
  number: 129,
  regions: page128.regions.filter((region) => region.ayah.number === 2),
};

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
    verse_mapping: { "6": "1-2" },
    first_verse_id: 1,
    last_verse_id: 2,
    first_word_id: 1,
    last_word_id: 6,
    verses_count: 2,
    words: [
      [1, 1, 3, 1, isUnicode ? "ٱلْحَمْدُ" : "ﱁ", "word"],
      [2, 1, 3, 2, isUnicode ? "لِلَّهِ" : "ﱂ", "end"],
      [3, 2, 3, 3, isUnicode ? "هُوَ" : "ﱃ", "word"],
      // A continued ayah can wrap position_in_line while position_in_page remains canonical.
      [4, 2, 4, 4, isUnicode ? "ٱلَّذِى" : "ﱄ", "word"],
      [5, 2, 4, 1, isUnicode ? "خَلَقَكُم" : "ﱅ", "word"],
      [6, 2, 4, 2, isUnicode ? "٢" : "ﱆ", "end"],
    ].map(([id, verseId, lineNumber, positionInLine, text, charType]) => ({
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

function paginated<T>(results: T[]) {
  return { next: null, previous: null, results };
}

async function installApiMocks(page: Page) {
  const testFont = await readFile(
    new URL("../node_modules/next/dist/next-devtools/server/font/geist-latin.woff2", import.meta.url),
  );
  await page.addInitScript(() => {
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
  });

  await page.route("https://audio.example.test/**", (route) =>
    route.fulfill({ status: 200, contentType: "audio/mpeg", body: "" }),
  );
  await page.route("https://verses.quran.foundation/fonts/**", (route) =>
    route.fulfill({ status: 200, contentType: "font/woff2", body: testFont }),
  );
  await page.route("**/api/v1/**", async (route) => {
    const url = new URL(route.request().url());
    const path = url.pathname;

    if (path === "/api/v1/reciters") {
      await route.fulfill({ json: paginated([reciter]) });
    } else if (path === "/api/v1/recitations") {
      await route.fulfill({ json: paginated([recitation]) });
    } else if (path === `/api/v1/recitations/${recitation.id}/tracks`) {
      await route.fulfill({ json: paginated(tracks) });
    } else if (path.startsWith(`/api/v1/recitations/${recitation.id}/surahs/`)) {
      const surahNumber = Number(path.split("/").at(-1));
      const track = tracks[surahNumber - 1];
      await route.fulfill({
        json: {
          track,
          segments: [1, 2].map((ayahNumber) => ({
            ayah_id: `00000000-0000-7000-8500-${String(surahNumber * 10 + ayahNumber).padStart(12, "0")}`,
            surah_number: surahNumber,
            ayah_number: ayahNumber,
            start_ms: (ayahNumber - 1) * 1_000,
            end_ms: ayahNumber * 1_000,
          })),
        },
      });
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
    } else if (path === "/api/v1/quran/editions") {
      await route.fulfill({ json: [edition] });
    } else if (path === "/api/v1/quran/foundation/mushafs") {
      await route.fulfill({ json: foundationMushafs });
    } else if (/^\/api\/v1\/quran\/foundation\/mushafs\/\d+\/pages\/\d+$/.test(path)) {
      const parts = path.split("/");
      const sourceId = Number(parts[6]);
      const pageNumber = Number(parts[8]);
      await route.fulfill({ json: foundationPage(sourceId, pageNumber) });
    } else if (path === "/api/v1/quran/editions/madani-hafs/surahs") {
      await route.fulfill({ json: [surah] });
    } else if (path === "/api/v1/quran/editions/madani-hafs/surahs/6/ayahs") {
      await route.fulfill({ json: ayahs });
    } else if (path === "/api/v1/quran/editions/madani-hafs/juz") {
      await route.fulfill({ json: juz });
    } else if (path === "/api/v1/quran/editions/madani-hafs/hizb") {
      await route.fulfill({ json: hizb });
    } else if (path === "/api/v1/quran/editions/madani-hafs/rub-el-hizb") {
      await route.fulfill({ json: rubElHizb });
    } else if (path === "/api/v1/quran/editions/madani-hafs/pages/128") {
      await route.fulfill({ json: page128 });
    } else if (path === "/api/v1/quran/editions/madani-hafs/pages/129") {
      await route.fulfill({ json: page129 });
    } else {
      await route.fulfill({
        status: 404,
        contentType: "application/problem+json",
        json: { detail: `Unhandled test endpoint: ${path}` },
      });
    }
  });
}

test.beforeEach(async ({ page }) => {
  await installApiMocks(page);
});

test("catalog loads all 114 surahs and starts the first track on one click", async ({ page }) => {
  await page.goto("/audio");

  await expect(page.getByRole("heading", { name: "Расширенный аудиоплеер" })).toBeVisible();
  const player = page.getByTestId("global-audio-player");
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

test("audio widget survives route navigation and pauses at the current position", async ({ page }) => {
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

  await page.locator('.app-menu a[href="/ru"]').click();

  await expect(page).toHaveURL("/ru");
  await expect(player).toBeVisible();
  const compactPlayerBox = await player.boundingBox();
  expect(compactPlayerBox).not.toBeNull();
  expect(compactPlayerBox!.height).toBeLessThan(130);
  await expect(player.getByText("Пауза при переходе · позиция сохранена", { exact: true })).toBeVisible();
  await expect(audio).toHaveAttribute("src", tracks[0].asset.url);
  expect(await audio.evaluate((element) => (element as HTMLAudioElement).currentTime)).toBe(12.5);

  await player.getByRole("button", { name: "Развернуть плеер", exact: true }).click();
  await expect(player.getByLabel("Режим повтора")).toBeVisible();
  expect((await player.boundingBox())!.height).toBeGreaterThan(200);
  await expect(player.getByRole("link", { name: "Открыть аудио", exact: true })).toHaveCount(0);

  await player.getByRole("button", { name: "Свернуть плеер", exact: true }).click();
  await expect.poll(async () => (await player.boundingBox())!.height).toBeLessThan(130);
  await expect(player.getByRole("link", { name: "Открыть аудио", exact: true })).toBeVisible();

  await player.getByRole("button", { name: "▶ Продолжить", exact: true }).click();
  await expect(player.getByText("Воспроизводится", { exact: true })).toBeVisible();
});

test("persistent player actions adapt without overflow on mobile and tablet", async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 812 });
  await page.goto("/audio");
  await page.getByRole("button", { name: "Слушать", exact: true }).first().click();

  const player = page.getByTestId("global-audio-player");
  const resumeButton = player.getByRole("button", { name: "▶ Продолжить", exact: true });
  const settingsButton = player.getByRole("button", { name: "Повтор, диапазон и таймер", exact: true });
  const audio = player.locator("audio");
  await expect(player).toBeVisible();
  await expect(resumeButton).toBeVisible();
  await expect(settingsButton).toBeVisible();
  expect((await resumeButton.boundingBox())!.width).toBeLessThanOrEqual(40);
  expect((await settingsButton.boundingBox())!.width).toBeLessThanOrEqual(40);
  expect((await audio.boundingBox())!.width).toBeGreaterThan(220);
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(
    await page.evaluate(() => document.documentElement.clientWidth),
  );

  await player.getByRole("button", { name: "Развернуть плеер", exact: true }).click();
  expect((await resumeButton.boundingBox())!.width).toBeGreaterThan(40);
  expect((await settingsButton.boundingBox())!.width).toBeGreaterThan(100);
  expect((await audio.boundingBox())!.width).toBeGreaterThan(300);
  await player.getByRole("button", { name: "Свернуть плеер", exact: true }).click();

  await page.locator('.app-menu a[href="/ru"]').click();
  await expect(page).toHaveURL("/ru");
  expect((await resumeButton.boundingBox())!.width).toBeLessThanOrEqual(40);
  expect((await settingsButton.boundingBox())!.width).toBeLessThanOrEqual(40);
  expect((await audio.boundingBox())!.width).toBeGreaterThan(220);
  const audioLink = player.getByRole("link", { name: "Открыть аудио", exact: true });
  await expect(audioLink).toBeVisible();
  expect((await audioLink.boundingBox())!.width).toBeLessThanOrEqual(40);

  await page.setViewportSize({ width: 768, height: 1024 });
  const tabletPlayerBox = await player.boundingBox();
  const tabletAudioBox = await audio.boundingBox();
  const tabletSettingsBox = await settingsButton.boundingBox();
  const tabletAudioLinkBox = await audioLink.boundingBox();
  expect(tabletPlayerBox).not.toBeNull();
  expect(tabletAudioBox).not.toBeNull();
  expect(tabletSettingsBox).not.toBeNull();
  expect(tabletAudioLinkBox).not.toBeNull();
  expect(tabletPlayerBox!.height).toBeLessThan(110);
  expect(tabletAudioBox!.width).toBeGreaterThan(250);
  expect(Math.abs(tabletSettingsBox!.y - tabletAudioBox!.y)).toBeLessThan(12);
  expect(Math.abs(tabletAudioLinkBox!.y - tabletAudioBox!.y)).toBeLessThan(12);
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(
    await page.evaluate(() => document.documentElement.clientWidth),
  );

  await page.setViewportSize({ width: 900, height: 900 });
  const compactDesktopAudioBox = await audio.boundingBox();
  const compactDesktopSettingsBox = await settingsButton.boundingBox();
  expect(compactDesktopAudioBox).not.toBeNull();
  expect(compactDesktopSettingsBox).not.toBeNull();
  expect(compactDesktopSettingsBox!.width).toBeGreaterThan(100);
  expect(Math.abs(compactDesktopSettingsBox!.y - compactDesktopAudioBox!.y)).toBeLessThan(12);
});

test("mushaf selects every fragment of an ayah and starts ayah playback", async ({ page }) => {
  await page.goto("/quran?surah=6");
  await page.getByRole("button", { name: /Мусхаф/ }).click();

  const recitationSelect = page.getByLabel("Чтец Quran.Foundation");
  await expect(recitationSelect.locator("option")).toHaveCount(1);
  const ayahRegions = page.getByRole("button", { name: "Аят 6:2", exact: true });
  await expect(ayahRegions).toHaveCount(2);

  await ayahRegions.first().click();
  await expect(ayahRegions.first()).toHaveClass(/is-selected/);
  await expect(ayahRegions.nth(1)).toHaveClass(/is-selected/);

  await page.getByRole("button", { name: "▶ Аят 6:2", exact: true }).click();

  await expect(page.getByText("Звучит аят 6:2", { exact: true })).toBeVisible();
  await expect(ayahRegions.first()).toHaveClass(/is-playing/);
  await expect(ayahRegions.nth(1)).toHaveClass(/is-playing/);
  await expect(page.locator(".mushaf-audio-now-playing audio")).toHaveAttribute(
    "src",
    tracks[5].asset.url,
  );
  await expect(page.getByText(/Махер аль-Муайкли · Мурратталь · аят 6:2/)).toBeVisible();
  await expect(page.getByText("Воспроизводится", { exact: true })).toBeVisible();
});

test("mushaf switcher renders all supported Quran.Foundation font variants", async ({ page }) => {
  await page.goto("/quran?surah=6");
  await page.getByRole("button", { name: /Мусхаф/ }).click();

  const variant = page.getByLabel("Вариант Мусхафа");
  await expect(variant.locator("option")).toHaveCount(4);
  await expect(variant.locator("option")).toHaveText([
    "Скан страницы · Мединский Hafs",
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

  await variant.selectOption("image");
  await expect(page.locator(".mushaf-image")).toBeVisible();
});

test("text Quran exposes the shared reciter controls and plays each ayah", async ({ page }) => {
  await page.goto("/quran?surah=6");

  const recitationSelect = page.getByLabel("Чтец Quran.Foundation");
  await expect(recitationSelect).toBeVisible();
  await expect(recitationSelect.locator("option")).toHaveCount(1);

  const firstAyah = page.locator(".ayah-card").first();
  const secondAyah = page.locator(".ayah-card").nth(1);
  const playButton = firstAyah.getByRole("button", { name: "Воспроизвести: Аят 6:1" });
  const repeatButton = firstAyah.getByRole("button", { name: "Повтор аята: Аят 6:1" });
  const speedButton = firstAyah.getByRole("button", { name: "Скорость воспроизведения: 1×" });
  await expect(playButton).toHaveText("▶");
  await expect(repeatButton).toHaveText("🔁");
  await expect(speedButton).toHaveText("1×");
  await expect(firstAyah.getByRole("button", { name: "Отметить как прочитанное" })).toHaveText("📍");
  await expect(firstAyah.getByRole("button", { name: "Добавить в закладки" })).toHaveText("🔖");

  await speedButton.click();
  await expect(page.getByLabel("Скорость воспроизведения", { exact: true })).toHaveValue("1.25");
  await expect(firstAyah.getByRole("button", { name: "Скорость воспроизведения: 1,25×" })).toHaveText("1,25×");

  await playButton.click();
  const audio = page.locator(".mushaf-audio-now-playing audio");
  await expect(audio).toHaveAttribute("src", tracks[5].asset.url);
  await expect(firstAyah).toHaveClass(/is-audio-active/);
  await expect(page.getByText(/Махер аль-Муайкли · Мурратталь · аят 6:1/)).toBeVisible();
  const pauseButton = firstAyah.getByRole("button", { name: "Поставить на паузу: Аят 6:1" });
  await expect(pauseButton).toHaveText("⏸");

  await pauseButton.click();
  await expect(page.getByText("Пауза · позиция сохранена", { exact: true })).toBeVisible();
  const continueButton = firstAyah.getByRole("button", { name: "Продолжить: Аят 6:1" });
  await expect(continueButton).toHaveText("▶");
  await continueButton.click();
  await expect(page.getByText("Воспроизводится", { exact: true })).toBeVisible();

  await repeatButton.click();
  await expect(page.getByLabel("Режим повтора", { exact: true })).toHaveValue("ayah");
  await expect(firstAyah.getByRole("button", { name: "Режим повтора: Без повтора" })).toHaveAttribute("aria-pressed", "true");

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

  const audio = page.locator(".mushaf-audio-now-playing audio");
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

  const audio = page.locator(".mushaf-audio-now-playing audio");
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
  await page.getByRole("button", { name: "▶ Продолжить", exact: true }).click();
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
  test(`mushaf overlay remains registered and selectable on ${viewport.name}`, async ({ page }) => {
    await page.setViewportSize({ width: viewport.width, height: viewport.height });
    await page.goto("/quran?surah=6");
    await page.getByRole("button", { name: /Мусхаф/ }).click();

    const image = page.locator(".mushaf-image");
    const overlay = page.locator(".mushaf-regions");
    await expect(image).toBeVisible();
    await expect(overlay).toBeVisible();
    const imageBox = await image.boundingBox();
    const overlayBox = await overlay.boundingBox();
    expect(imageBox).not.toBeNull();
    expect(overlayBox).not.toBeNull();
    expect(Math.abs(imageBox!.x - overlayBox!.x)).toBeLessThan(1);
    expect(Math.abs(imageBox!.y - overlayBox!.y)).toBeLessThan(1);
    expect(Math.abs(imageBox!.width - overlayBox!.width)).toBeLessThan(1);
    expect(Math.abs(imageBox!.height - overlayBox!.height)).toBeLessThan(1);

    const fragments = page.getByRole("button", { name: "Аят 6:2", exact: true });
    await expect(fragments).toHaveCount(2);
    await fragments.last().click();
    await expect(fragments.first()).toHaveClass(/is-selected/);
    await expect(fragments.last()).toHaveClass(/is-selected/);
  });
}

test("quran navigation exposes juz, hizb, rub and exact ayah jumps", async ({ page }) => {
  await page.goto("/quran?surah=6");

  await expect(page.getByLabel("Джуз (1-30)").locator("option")).toHaveCount(31);
  await expect(page.getByLabel("Хизб (1-60)").locator("option")).toHaveCount(61);
  await expect(page.getByLabel("Руб аль-хизб (1-240)").locator("option")).toHaveCount(241);
  await expect(page.getByLabel(/Аят суры/).locator("option")).toHaveCount(3);

  await page.getByLabel("Хизб (1-60)").selectOption("13");
  await expect(page.getByRole("button", { name: /Мусхаф/ })).toHaveClass(/btn-primary/);
  await expect(page.locator(".mushaf-image")).toHaveAttribute("data-page-number", "129");
  await expect(page.getByText("Выбран аят 6:2", { exact: true })).toBeVisible();

  await page.getByLabel(/Аят суры/).selectOption("2");
  await expect(page.locator(".mushaf-image")).toHaveAttribute("data-page-number", "128");
  await expect(page.getByText("Выбран аят 6:2", { exact: true })).toBeVisible();
});
