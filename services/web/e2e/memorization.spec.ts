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
  coverage: {
    track_count: 1,
    surah_count: 1,
    expected_ayahs: 2,
    timed_ayahs: 2,
    complete: false,
    timings_complete: true,
  },
  timings: { available: true, segment_count: 2, complete: true },
  capabilities: {
    listen: true,
    ayah_playback: true,
    memorization: true,
    offline: false,
  },
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

const surahPlayback = {
  track: { asset: { url: "https://audio.example.test/memorization/001.mp3" } },
  segments: ayahs.map((ayah, index) => ({
    ayah_id: ayah.id,
    surah_number: 1,
    ayah_number: ayah.number,
    start_ms: index * 1_000,
    end_ms: (index + 1) * 1_000,
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

  await page.route("https://audio.example.test/**", (route) =>
    route.fulfill({ status: 200, contentType: "audio/mpeg", body: "" }),
  );
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
    if (url.pathname === `/api/v1/recitations/${recitation.id}/surahs/1`) {
      return route.fulfill({ json: surahPlayback });
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

test("highlights the recited ayah while the range plays and repeats", async ({ page }) => {
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
  await installMocks(page);

  await page.goto("/ru/memorization");
  await page.getByLabel("Чтец для повторения").selectOption(recitation.id);
  await page.getByLabel("По аят").selectOption("2");
  await page.getByRole("button", { name: "Сохранить план" }).click();
  await page.getByRole("tab", { name: "Слушать" }).click();

  const audio = page.getByTestId("memorization-audio-loop").locator("audio");
  const cards = page.locator(".memorization-ayah-card");
  const playing = page.locator(".memorization-ayah-card.is-playing");
  const playAt = (seconds: number) => audio.evaluate((media, value) => {
    (media as HTMLAudioElement).currentTime = value;
    media.dispatchEvent(new Event("timeupdate"));
  }, seconds);

  await expect(cards).toHaveCount(2);
  await expect(playing).toHaveCount(0);
  await page.getByRole("button", { name: "Слушать по кругу" }).click();
  await expect(cards.nth(0)).toHaveClass(/is-playing/);
  await expect(playing).toHaveCount(1);

  await playAt(1.5);
  await expect(cards.nth(1)).toHaveClass(/is-playing/);
  await expect(playing).toHaveCount(1);

  // The cycle ends at the last ayah; the next repeat starts from the first.
  await playAt(2);
  await expect(playing).toHaveCount(0);
  await expect(cards.nth(0)).toHaveClass(/is-playing/, { timeout: 5_000 });
  await playAt(1.2);
  await expect(cards.nth(1)).toHaveClass(/is-playing/);

  await page.getByRole("button", { name: "Пауза" }).click();
  await expect(playing).toHaveCount(0);

  // Leaving the Listen tab mid-playback drops the highlight with the player.
  await page.getByRole("button", { name: "Слушать по кругу" }).click();
  await expect(cards.nth(0)).toHaveClass(/is-playing/);
  await page.getByRole("tab", { name: "Читать" }).click();
  await expect(playing).toHaveCount(0);
  await page.getByRole("tab", { name: "Слушать" }).click();
  await expect(playing).toHaveCount(0);
});

const tajweedTexts = (ru: string, en: string) => ({ ru, en, ar: en, tr: en });
const tajweedRules = {
  version: "test",
  review_status: "pending_teacher_review",
  languages: ["ru", "en", "ar", "tr"],
  rules: [
    {
      code: "madda_permissible",
      arabic_name: "المد الجائز",
      color: "#FF7B00",
      name: tajweedTexts("Мадд джаиз", "Permissible madd"),
      why: tajweedTexts("Буква мадда перед остановкой.", "A madd letter before a stop."),
      how: tajweedTexts("При остановке 2, 4 или 6 харакатов.", "2, 4 or 6 counts when stopping."),
      variants: [],
    },
    {
      code: "ham_wasl",
      arabic_name: "همزة الوصل",
      color: "#9FA5A5",
      name: tajweedTexts("Хамзату-ль-васль", "Hamzat al-wasl"),
      why: tajweedTexts("Соединительная хамза в начале слова.", "A connecting hamza."),
      how: tajweedTexts("В связном чтении не произносится.", "Silent when reading on."),
      variants: [],
    },
  ],
};
const tajweedMarkup = {
  page_number: 1,
  rules: ["madda_permissible", "ham_wasl"],
  ayahs: [
    {
      verse_key: "1:1",
      surah_number: 1,
      ayah_number: 1,
      page_number: 1,
      rules: ["ham_wasl"],
      words: [{ position: 1, text: "ٱلْحَمْدُ", rules: [{ code: "ham_wasl", start: 0, end: 1 }] }],
    },
    {
      verse_key: "1:2",
      surah_number: 1,
      ayah_number: 2,
      page_number: 1,
      rules: ["madda_permissible"],
      words: [
        { position: 3, text: "ٱلْعَـٰلَمِينَ", rules: [{ code: "madda_permissible", start: 10, end: 12 }] },
      ],
    },
  ],
  source: tajweedMushaf.source,
};

test("coloured memorization text explains a tapped tajweed word", async ({ page }) => {
  await installMocks(page);
  await page.route("**/api/v1/quran/tajweed/**", (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path === "/api/v1/quran/tajweed/rules") return route.fulfill({ json: tajweedRules });
    if (path === "/api/v1/quran/tajweed/pages/1") return route.fulfill({ json: tajweedMarkup });
    return route.fulfill({ status: 404, json: { detail: "Not found" } });
  });
  await page.route(`**/api/v1/recitations/${recitation.id}/ayahs/1/1`, (route) => route.fulfill({
    json: {
      track: surahPlayback.track,
      segment: { ...surahPlayback.segments[0], words: [[1, 0, 600]] },
    },
  }));

  await page.goto("/ru/memorization");
  await page.getByLabel("Чтец для повторения").selectOption(recitation.id);
  await page.getByLabel("По аят").selectOption("2");
  await page.getByRole("button", { name: "Сохранить план" }).click();
  await expect(page.getByTestId("memorization-tajweed")).toHaveAttribute("data-tajweed-status", "ready");

  const legends = page.getByTestId("tajweed-legend");
  await expect(legends).toHaveCount(2);
  await expect(legends.first().getByRole("button")).toHaveText(["Хамзату-ль-васль"]);
  await expect(legends.first()).toHaveAttribute("dir", "ltr");
  const word = page.getByRole("button", { name: "ٱلْحَمْدُ: Хамзату-ль-васль" });
  await word.click();
  const card = page.getByRole("dialog", { name: "Таджвид в слове" });
  await expect(card).toBeVisible();
  await expect(card.getByRole("heading", { name: "Хамзату-ль-васль" })).toBeVisible();
  await expect(card.getByText("Соединительная хамза в начале слова.")).toBeVisible();
  await expect(card.getByTestId("tajweed-listen")).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(card).toHaveCount(0);
  await expect(word).toBeFocused();

  await legends.last().getByRole("button", { name: "Мадд джаиз" }).click();
  const ruleCard = page.getByRole("dialog", { name: "Правило таджвида" });
  await expect(ruleCard.getByText("Где в этом аяте")).toBeVisible();
  await ruleCard.getByRole("button", { name: /1:2/ }).click();
  await expect(page.getByRole("dialog", { name: "Таджвид в слове" })).toBeVisible();
  // 1:2 has no word timing for this reciter, so there is nothing to play.
  await expect(page.getByTestId("tajweed-listen")).toHaveCount(0);
  await page.keyboard.press("Escape");

  // Each coloured ayah has its step-by-step breakdown with the plan's reciter.
  const breakdowns = page.getByTestId("tajweed-breakdown-open");
  await expect(breakdowns).toHaveCount(2);
  await breakdowns.first().click();
  const breakdown = page.getByRole("dialog", { name: /^Разбор таджвида/ });
  await expect(breakdown.getByTestId("tajweed-step-counter")).toHaveText("1 из 1: Хамзату-ль-васль");
  await expect(breakdown.locator(".tajweed-breakdown-word.is-step")).toHaveAttribute("data-word-position", "1");
  await expect(breakdown.getByTestId("tajweed-listen")).toBeVisible();
  await expect(breakdown.getByRole("button", { name: "Прослушать весь аят" })).toBeVisible();
  await breakdown.getByRole("button", { name: "Итог" }).click();
  await expect(breakdown.getByTestId("tajweed-summary").getByRole("button", { name: "Хамзату-ль-васль" })).toBeVisible();
  await breakdown.getByRole("button", { name: "Готово" }).click();
  await expect(breakdown).toHaveCount(0);
  await expect(breakdowns.first()).toBeFocused();

  // Recall practice hides the ayahs, and with them every tajweed hint.
  await page.getByRole("tab", { name: "Проверить себя" }).click();
  await expect(page.getByTestId("tajweed-legend")).toHaveCount(0);
  await expect(page.getByTestId("tajweed-breakdown-open")).toHaveCount(0);
});
