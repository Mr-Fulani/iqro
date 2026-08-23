import { expect, Page, test } from "@playwright/test";

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
  return {
    id: `00000000-0000-7000-8100-${String(surah).padStart(12, "0")}`,
    recitation_id: recitation.id,
    scope: "surah",
    surah_number: surah,
    juz_number: null,
    duration_ms: 60_000,
    offline_download_allowed: false,
    asset: {
      url: `https://audio.example.test/${String(surah).padStart(3, "0")}.mp3`,
      content_type: "audio/mpeg",
      codec: "mp3",
      bitrate_kbps: 96,
      bytes: 720_000,
      sha256: null,
      etag: null,
      range_supported: false,
      immutable: false,
    },
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

function paginated<T>(results: T[]) {
  return { next: null, previous: null, results };
}

async function installApiMocks(page: Page) {
  await page.addInitScript(() => {
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
  await page.route("**/api/v1/**", async (route) => {
    const url = new URL(route.request().url());
    const path = url.pathname;

    if (path === "/api/v1/reciters") {
      await route.fulfill({ json: paginated([reciter]) });
    } else if (path === "/api/v1/recitations") {
      await route.fulfill({ json: paginated([recitation]) });
    } else if (path === `/api/v1/recitations/${recitation.id}/tracks`) {
      await route.fulfill({ json: paginated(tracks) });
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

  await expect(page.getByText("Найдено треков: 114")).toBeVisible();
  const listenButtons = page.getByRole("button", { name: "Слушать", exact: true });
  await expect(listenButtons).toHaveCount(114);

  await listenButtons.first().click();

  await expect(page.locator(".audio-player-bar")).toBeVisible();
  await expect(page.locator(".audio-player-bar audio")).toHaveAttribute(
    "src",
    tracks[0].asset.url,
  );
  await expect(page.getByRole("button", { name: "▶ Играет", exact: true })).toBeVisible();
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
  await expect(page.getByText(/Махер аль-Муайкли · Мурратталь · воспроизводится/)).toBeVisible();
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
