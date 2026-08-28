import { readFile } from "node:fs/promises";
import { expect, Page, test } from "@playwright/test";

const activeSession = {
  token_type: "Bearer",
  access_token: "memorization-access-token",
  expires_in: 900,
  access_expires_at: "2026-08-28T12:15:00Z",
  user: {
    id: "00000000-0000-7000-8000-000000000901",
    status: "active",
    preferred_locale: "ru",
    email: "memorizer@example.com",
    deletion_requested_at: null,
    deletion_scheduled_for: null,
  },
  device: {
    id: "00000000-0000-7000-8000-000000000902",
    platform: "web",
    locale: "ru",
    app_version: "1.0.0",
    bootstrap_generation: 1,
  },
};

const surah = {
  id: "00000000-0000-7000-8000-000000000911",
  number: 1,
  name_ar: "الفاتحة",
  name_en: "Al-Fatihah",
  name_ru: "Аль-Фатиха",
  revelation_type: "meccan",
  ayah_count: 2,
  first_page: 1,
};

const ayahs = [
  {
    id: "00000000-0000-7000-8000-000000000912",
    edition_code: "madani-hafs",
    content_version: "1.0.0",
    surah_number: 1,
    number: 1,
    text_uthmani: "بِسْمِ اللَّهِ",
    juz_number: 1,
    hizb_number: 1,
    rub_el_hizb_number: 1,
    pages: [1],
  },
  {
    id: "00000000-0000-7000-8000-000000000913",
    edition_code: "madani-hafs",
    content_version: "1.0.0",
    surah_number: 1,
    number: 2,
    text_uthmani: "الْحَمْدُ لِلَّهِ",
    juz_number: 1,
    hizb_number: 1,
    rub_el_hizb_number: 1,
    pages: [1],
  },
];

const recitation = {
  id: "00000000-0000-7000-8000-000000000914",
  code: "test-murattal",
  version: "1.0.0",
  style: "murattal",
  reciter: {
    id: "00000000-0000-7000-8000-000000000915",
    slug: "test-reciter",
    name_ar: "قارئ الاختبار",
    name_en: "Test Reciter",
    name_ru: "Тестовый чтец",
    country_code: "SA",
  },
  quran_edition: {
    id: "00000000-0000-7000-8000-000000000916",
    code: "madani-hafs",
    content_version: "1.0.0",
    riwayah: "Hafs 'an Asim",
  },
  source: { name: "Test", url: "", version: "1", checksum_sha256: "a".repeat(64) },
  license: { rights_holder: "Test", name: "Test", url: "", spdx_id: "", attribution: "" },
  rights: { stream: true, offline_download: false },
  coverage: { track_count: 1, surah_count: 1, complete: false },
  timings: { available: true, segment_count: 2 },
  published_at: "2026-08-28T00:00:00Z",
};

const tajweedMushaf = {
  source_id: 19,
  name: "QCF V4 Tajweed",
  description: "Color-coded Tajweed Mushaf",
  qirat_name: "Hafs",
  pages_count: 604,
  lines_per_page: 15,
  default_font_name: "v4-tajweed",
  mapping_mode: "reference",
  schema_version: "1",
  sync_sequence: 1,
  source_checksum_sha256: "c".repeat(64),
  last_synced_at: "2026-08-28T00:00:00Z",
  rendering: {
    available: true,
    mode: "page-font",
    font_format: "woff2",
    font_url_template: "https://verses.quran.foundation/fonts/quran/hafs/v4/colrv1/woff2/p{page}.woff2",
    color_format: "COLRv1",
  },
  source: {
    name: "Quran.Foundation Content API",
    url: "https://api-docs.quran.foundation/",
    attribution: "Quran data provided by Quran Foundation.",
  },
};

const tajweedPage = {
  mushaf_id: 19,
  qirat_name: "Hafs",
  font_name: "v4-tajweed",
  rendering: {
    ...tajweedMushaf.rendering,
    font_url: "https://verses.quran.foundation/fonts/quran/hafs/v4/colrv1/woff2/p1.woff2",
  },
  page_number: 1,
  verse_mapping: { "1": "1-2" },
  first_verse_id: 1,
  last_verse_id: 2,
  first_word_id: 1,
  last_word_id: 4,
  verses_count: 2,
  words: [
    [1, 1, 1, "ﱁ", "word"],
    [2, 1, 2, "ﱂ", "end"],
    [3, 2, 3, "ﱃ", "word"],
    [4, 2, 4, "ﱄ", "end"],
  ].map(([id, verseId, position, text, charType]) => ({
    id,
    word_id: id,
    verse_id: verseId,
    page_number: 1,
    line_number: 1,
    position_in_line: position,
    position_in_page: position,
    position_in_verse: position,
    char_type_id: null,
    char_type_name: charType,
    text,
    css_class: "",
    css_style: "",
  })),
};

function planSnapshot() {
  return {
    id: "00000000-0000-7000-8000-000000000920",
    edition_code: "madani-hafs",
    content_version: "1.0.0",
    start_ayah: {
      id: ayahs[0].id,
      surah_number: 1,
      ayah_number: 1,
      text_uthmani: ayahs[0].text_uthmani,
    },
    end_ayah: {
      id: ayahs[1].id,
      surah_number: 1,
      ayah_number: 2,
      text_uthmani: ayahs[1].text_uthmani,
    },
    recitation_id: recitation.id,
    reciter: recitation.reciter,
    daily_repetitions: 5,
    pause_seconds: 2,
    timezone_name: "Europe/Istanbul",
    revision: 1,
    client_updated_at: "2026-08-28T10:00:00Z",
    device_id: activeSession.device.id,
    created_at: "2026-08-28T10:00:00Z",
    updated_at: "2026-08-28T10:00:00Z",
  };
}

async function installMocks(page: Page) {
  const testFont = await readFile(
    new URL("../node_modules/next/dist/next-devtools/server/font/geist-latin.woff2", import.meta.url),
  );
  let plan: ReturnType<typeof planSnapshot> | null = null;
  let completed = 0;
  const writes: Array<Record<string, unknown>> = [];

  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ json: activeSession }));
  await page.route("https://verses.quran.foundation/fonts/**", (route) =>
    route.fulfill({ status: 200, contentType: "font/woff2", body: testFont }),
  );
  await page.route("**/api/v1/**", async (route) => {
    const request = route.request();
    const url = new URL(request.url());
    if (url.pathname === "/api/v1/me/memorization" && request.method() === "GET") {
      return route.fulfill({
        headers: { "Cache-Control": "private, no-store" },
        json: {
          timezone_name: "Europe/Istanbul",
          plan,
          today: {
            local_date: "2026-08-28",
            completed_repetitions: completed,
            target_repetitions: plan?.daily_repetitions || 0,
            remaining_repetitions: Math.max((plan?.daily_repetitions || 0) - completed, 0),
            is_completed: Boolean(plan && completed >= plan.daily_repetitions),
            last_assessment: completed ? "memorized" : null,
            sessions: [],
          },
          recent_days: completed
            ? [{ local_date: "2026-08-28", completed_repetitions: completed, session_count: 1, last_assessment: "memorized" }]
            : [],
        },
      });
    }
    if (url.pathname === "/api/v1/me/memorization" && request.method() === "PUT") {
      const payload = request.postDataJSON() as Record<string, unknown>;
      writes.push(payload);
      plan = planSnapshot();
      return route.fulfill({ status: 201, json: plan });
    }
    if (url.pathname === "/api/v1/me/memorization-sessions" && request.method() === "POST") {
      const payload = request.postDataJSON() as Record<string, unknown>;
      writes.push(payload);
      completed += Number(payload.completed_repetitions);
      return route.fulfill({
        status: 201,
        json: {
          id: payload.id,
          plan_id: plan?.id,
          start_ayah: plan?.start_ayah,
          end_ayah: plan?.end_ayah,
          daily_target_repetitions: 5,
          completed_repetitions: payload.completed_repetitions,
          assessment: payload.assessment,
          duration_seconds: payload.duration_seconds,
          timezone_name: payload.timezone_name,
          local_date: payload.local_date,
          client_updated_at: payload.client_updated_at,
          device_id: activeSession.device.id,
          created_at: "2026-08-28T10:05:00Z",
        },
      });
    }
    if (url.pathname === "/api/v1/me/memorization-sessions" && request.method() === "DELETE") {
      completed = 0;
      return route.fulfill({ status: 204 });
    }
    if (url.pathname === "/api/v1/quran/editions/madani-hafs/surahs") {
      return route.fulfill({ json: [surah] });
    }
    if (url.pathname === "/api/v1/quran/editions/madani-hafs/surahs/1/ayahs") {
      return route.fulfill({ json: ayahs });
    }
    if (url.pathname === "/api/v1/recitations") {
      return route.fulfill({ json: { next: null, previous: null, results: [recitation] } });
    }
    if (url.pathname === "/api/v1/quran/foundation/mushafs") {
      return route.fulfill({ json: [tajweedMushaf] });
    }
    if (url.pathname === "/api/v1/quran/foundation/mushafs/19/pages/1") {
      return route.fulfill({ json: tajweedPage });
    }
    return route.fulfill({ status: 404, json: { detail: "Not found" } });
  });
  return writes;
}

test("creates a synced plan, tests recall, and records self-assessment", async ({ page }) => {
  const writes = await installMocks(page);

  await page.goto("/ru/memorization");
  await expect(page.getByRole("heading", { name: "Заучивание Корана" })).toBeVisible();
  await page.getByLabel("Чтец для повторения").selectOption(recitation.id);
  await page.reload();
  await expect(page.getByLabel("Чтец для повторения")).toHaveValue(recitation.id);
  await page.getByLabel("По аят").selectOption("2");
  await page.getByRole("button", { name: "Сохранить план" }).click();

  await expect(page.getByText("Сура 1, аяты 1–2").first()).toBeVisible();
  await expect(page.getByTestId("memorization-tajweed")).toHaveAttribute(
    "data-tajweed-status",
    "ready",
  );
  await page.getByRole("tab", { name: "Проверить себя" }).click();
  await expect(page.getByLabel(ayahs[0].text_uthmani)).toHaveCount(0);
  await page.getByRole("button", { name: "Показать аят 1" }).click();
  await expect(page.getByLabel(ayahs[0].text_uthmani)).toBeVisible();

  await page.getByRole("button", { name: "+ 1 повтор" }).click();
  await page.getByRole("button", { name: "Запомнил" }).click();

  await expect(page.getByText("1 / 5", { exact: true })).toBeVisible();
  page.once("dialog", (dialog) => dialog.accept());
  await page.getByRole("button", { name: "Сбросить счётчики" }).click();
  await expect(page.getByText("0 / 5", { exact: true })).toBeVisible();
  expect(writes).toHaveLength(2);
  expect(writes[0]).toMatchObject({
    start_ayah_id: ayahs[0].id,
    end_ayah_id: ayahs[1].id,
    recitation_id: recitation.id,
    daily_repetitions: 5,
  });
  expect(writes[1]).toMatchObject({ completed_repetitions: 1, assessment: "memorized" });
});
