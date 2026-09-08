import { access, stat } from "node:fs/promises";
import path from "node:path";
import { expect, test } from "@playwright/test";
import { groupRecitersByPerson, selectHomePopularReciters } from "../lib/reciter-catalog";
import { RECITER_PORTRAITS } from "../lib/reciter-portraits";

const productionReciterSlugs = [
  "qf-1-abdulbaset-abdulsamad-mujawwad",
  "qf-2-abdul-baset-abdul-samad",
  "qf-3-abdur-rahman-as-sudais",
  "qf-4-abu-bakr-al-shatri",
  "qf-5-hani-ar-rifai",
  "qf-6-mahmoud-khaleel-al-husary",
  "qf-7-mishari-rashid-al-afasy",
  "qf-9-muhammad-siddiq-al-minshawi",
  "qf-10-saud-ash-shuraym",
  "qf-12-mahmoud-khaleel-al-husary",
  "qf-13-saad-al-ghamdi",
  "qf-19-ahmed-ibn-ali-al-ajmy",
  "qf-158-abdullah-ali-jabir",
  "qf-159-maher-al-muaiqly",
  "qf-160-bandar-baleela",
  "qf-174-yasser-ad-dussary",
  "qf-175-abdullah-hamad-abu-sharida",
  "qf-176-ahmed-tahoun",
];

const reciters = [
  {
    id: "00000000-0000-7000-8000-000000000002",
    slug: "qf-2-abdul-baset-abdul-samad",
    name_ar: "عبد الباسط عبد الصمد",
    name_en: "Abdul Baset Abdul Samad",
    name_ru: "Абдуль-Басит Абдус-Самад",
    country_code: "EG",
    portrait_url: null,
  },
  {
    id: "00000000-0000-7000-8000-000000000001",
    slug: "qf-1-abdulbaset-abdulsamad-mujawwad",
    name_ar: "عبد الباسط عبد الصمد - مجود",
    name_en: "AbdulBaset AbdulSamad [Mujawwad]",
    name_ru: "Абдуль-Басит Абдус-Самад",
    country_code: "EG",
    portrait_url: null,
  },
  {
    id: "00000000-0000-7000-8000-000000000158",
    slug: "qf-158-abdullah-ali-jabir",
    name_ar: "عبدالله علي جابر",
    name_en: "Abdullah Ali Jabir",
    name_ru: "Абдуллах Али Джабир",
    country_code: "SA",
    portrait_url: null,
  },
  {
    id: "00000000-0000-7000-8000-000000000175",
    slug: "qf-175-abdullah-hamad-abu-sharida",
    name_ar: "عبدالله حمد أبو شريدة",
    name_en: "Abdullah Hamad Abu Sharida",
    name_ru: "Абдуллах Хамад Абу Шарида",
    country_code: "SA",
    portrait_url: null,
  },
  {
    id: "00000000-0000-7000-8000-000000000003",
    slug: "qf-3-abdur-rahman-as-sudais",
    name_ar: "عبدالرحمن السديس",
    name_en: "Abdur-Rahman as-Sudais",
    name_ru: "Абдур-Рахман ас-Судайс",
    country_code: "SA",
    portrait_url: null,
  },
  {
    id: "00000000-0000-7000-8000-000000000004",
    slug: "qf-4-abu-bakr-al-shatri",
    name_ar: "أبو بكر الشاطري",
    name_en: "Abu Bakr al-Shatri",
    name_ru: "Абу Бакр аш-Шатри",
    country_code: "SA",
    portrait_url: null,
  },
  {
    id: "00000000-0000-7000-8000-000000000005",
    slug: "qf-5-hani-ar-rifai",
    name_ar: "هاني الرفاعي",
    name_en: "Hani ar-Rifai",
    name_ru: "Хани ар-Рифаи",
    country_code: "SA",
    portrait_url: null,
  },
  {
    id: "00000000-0000-7000-8000-000000000006",
    slug: "qf-6-mahmoud-khaleel-al-husary",
    name_ar: "محمود خليل الحصري",
    name_en: "Mahmoud Khaleel Al-Husary",
    name_ru: "Махмуд Халиль аль-Хусари",
    country_code: "EG",
    portrait_url: null,
  },
  {
    id: "00000000-0000-7000-8000-000000000007",
    slug: "qf-7-mishari-rashid-al-afasy",
    name_ar: "مشاري راشد العفاسي",
    name_en: "Mishari Rashid al-Afasy",
    name_ru: "Мишари Рашид аль-Афаси",
    country_code: "KW",
    portrait_url: null,
  },
  {
    id: "00000000-0000-7000-8000-000000000009",
    slug: "qf-9-muhammad-siddiq-al-minshawi",
    name_ar: "محمد صديق المنشاوي",
    name_en: "Muhammad Siddiq al-Minshawi",
    name_ru: "Мухаммад Сиддик аль-Миншави",
    country_code: "EG",
    portrait_url: null,
  },
  {
    id: "00000000-0000-7000-8000-000000000010",
    slug: "qf-10-saud-ash-shuraym",
    name_ar: "سعود الشريم",
    name_en: "Saud ash-Shuraym",
    name_ru: "Сауд аш-Шурайм",
    country_code: "SA",
    portrait_url: null,
  },
];

function recitation(
  id: string,
  reciter: (typeof reciters)[number],
  style: "mujawwad" | "murattal",
  publishedAt: string,
) {
  return {
    id,
    code: `${reciter.slug}-${style}`,
    version: publishedAt.slice(0, 10),
    style,
    reciter,
    quran_edition: {
      id: "00000000-0000-7000-8000-000000000999",
      code: "madani-hafs",
      content_version: "1.0.1",
      riwayah: "Hafs 'an Asim",
    },
    coverage: { track_count: 114, surah_count: 114, complete: true },
    timings: { available: true, segment_count: 6236 },
    published_at: publishedAt,
  };
}

test("portrait manifest covers the full production reciter catalog", async () => {
  expect(Object.keys(RECITER_PORTRAITS).sort()).toEqual([...productionReciterSlugs].sort());
  expect(new Set(Object.values(RECITER_PORTRAITS)).size).toBe(16);

  for (const portraitUrl of new Set(Object.values(RECITER_PORTRAITS))) {
    expect(portraitUrl).toMatch(/^\/reciters\/[a-z0-9-]+\.webp$/);
    await access(path.join(process.cwd(), "public", portraitUrl.slice(1)));
  }

  const people = groupRecitersByPerson(reciters);
  expect(people).toHaveLength(10);
  expect(people.filter((reciter) => reciter.slug.includes("abdul-baset"))).toHaveLength(1);
  expect(people[0].slug).toBe("qf-2-abdul-baset-abdul-samad");

  const uploadedPortrait = "https://media.example.test/abdul-baset.png";
  const peopleWithVariantPortrait = groupRecitersByPerson(
    reciters.map((reciter) =>
      reciter.slug === "qf-1-abdulbaset-abdulsamad-mujawwad"
        ? { ...reciter, portrait_url: uploadedPortrait }
        : reciter,
    ),
  );
  expect(peopleWithVariantPortrait[0]).toMatchObject({
    slug: "qf-2-abdul-baset-abdul-samad",
    portrait_url: uploadedPortrait,
  });

  expect(selectHomePopularReciters(reciters)).toHaveLength(8);
  expect(selectHomePopularReciters(reciters).slice(0, 6).map((reciter) => reciter.slug)).toEqual([
    "qf-7-mishari-rashid-al-afasy",
    "qf-3-abdur-rahman-as-sudais",
    "qf-2-abdul-baset-abdul-samad",
    "qf-9-muhammad-siddiq-al-minshawi",
    "qf-6-mahmoud-khaleel-al-husary",
    "qf-10-saud-ash-shuraym",
  ]);
});

test("home hero links Quran, audio, Dua and prayer with optimized landmark slides", async ({ page }) => {
  const heroImages = [
    "hero-kaaba.webp",
    "hero-prophets-mosque.webp",
    "hero-quba-mosque.webp",
  ];
  for (const imageName of heroImages) {
    const imagePath = path.join(process.cwd(), "public", "images", "home", imageName);
    await access(imagePath);
    expect((await stat(imagePath)).size).toBeLessThan(150_000);
  }

  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ status: 401 }));
  await page.goto("/ru");

  const hero = page.getByTestId("home-hero");
  await expect(hero.getByText("Мединский Мусхаф Хафс · 604 страницы")).toBeVisible();
  await expect(hero.getByRole("link", { name: "📖 Читать Коран" })).toHaveAttribute("href", "/ru/quran");
  await expect(hero.getByRole("link", { name: "🎵 Слушать Коран" })).toHaveAttribute("href", "/ru/audio");
  await expect(hero.getByRole("link", { name: "🤲 Ду’а" })).toHaveAttribute("href", "/ru/dua");
  await expect(hero.getByRole("link", { name: "🕌 Время намаза" })).toHaveAttribute("href", "/ru/prayer");
  expect(await hero.evaluate((element) => element.getBoundingClientRect().height)).toBeGreaterThanOrEqual(440);

  await hero.getByTestId("hero-slide-1").click();
  await expect(hero.getByTestId("hero-media")).toHaveAttribute(
    "style",
    /hero-prophets-mosque\.webp/,
  );

  await page.setViewportSize({ width: 320, height: 760 });
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(
    await page.evaluate(() => document.documentElement.clientWidth),
  );
  const carouselTop = await hero.locator(".hero-carousel").evaluate(
    (element) => element.getBoundingClientRect().top,
  );
  const actionsBottom = await hero.locator(".hero-actions").evaluate(
    (element) => element.getBoundingClientRect().bottom,
  );
  expect(carouselTop).toBeGreaterThanOrEqual(actionsBottom);
  expect((await hero.getByTestId("hero-slide-1").boundingBox())!.height).toBeGreaterThanOrEqual(44);
});

test("home prayer preview reuses the saved prayer location and profile", async ({ page }) => {
  const userId = "00000000-0000-7000-8000-000000000102";
  const methodId = "01992d87-6c00-7000-8000-000000000601";
  let calculation: Record<string, unknown> | null = null;
  await page.addInitScript(
    ({ storageKey, methodConfigId }) => {
      window.localStorage.setItem(
        storageKey,
        JSON.stringify({
          latitude: "41.0082",
          longitude: "28.9784",
          timezone: "Europe/Istanbul",
          method_config_id: methodConfigId,
          asr_method: "hanafi",
          updated_at: new Date().toISOString(),
        }),
      );
    },
    { storageKey: `quran_prayer_location_v1:${userId}`, methodConfigId: methodId },
  );
  await page.route("**/api/web-auth/refresh", (route) =>
    route.fulfill({
      json: {
        token_type: "Bearer",
        access_token: "home-prayer-access-token",
        expires_in: 900,
        access_expires_at: "2026-08-28T12:00:00Z",
        user: { id: userId, status: "active", preferred_locale: "ru", email: "reader@example.com" },
        device: {
          id: "00000000-0000-7000-8000-000000000201",
          platform: "web",
          locale: "ru",
          app_version: "1.0.0",
          bootstrap_generation: 1,
        },
      },
    }),
  );
  await page.route("**/api/v1/**", (route) => {
    const request = route.request();
    const url = new URL(request.url());
    if (url.pathname === "/api/v1/prayer/methods") {
      return route.fulfill({
        json: {
          catalog_version: "2026.1",
          configuration_schema_version: 1,
          checksum_sha256: "b".repeat(64),
          methods: [{
            id: methodId,
            code: "muslim-world-league",
            available: true,
            name: { ar: "", en: "MWL", ru: "Всемирная исламская лига" },
            description: { ar: "", en: "", ru: "" },
            checksum_sha256: "a".repeat(64),
          }],
        },
      });
    }
    if (url.pathname === "/api/v1/me/prayer-profile") {
      return route.fulfill({
        json: {
          id: "01992d87-6c00-7000-8000-000000000602",
          method_config: { id: methodId, code: "muslim-world-league", catalog_version: "2026.1", checksum_sha256: "a".repeat(64) },
          method_available: true,
          asr_method: "standard",
          high_latitude_rule: "seventh_of_night",
          polar_resolution: "aqrab_balad",
          adjustments: { fajr: -3, sunrise: 0, dhuhr: 0, asr: 0, maghrib: 0, isha: 2 },
          timezone_mode: "fixed",
          fixed_timezone: "Europe/Istanbul",
          revision: 3,
          client_updated_at: "2026-08-28T08:00:00Z",
          device_id: null,
          created_at: "2026-08-28T08:00:00Z",
          updated_at: "2026-08-28T08:00:00Z",
        },
      });
    }
    if (url.pathname === "/api/v1/prayer/calculate") {
      calculation = request.postDataJSON() as Record<string, unknown>;
      return route.fulfill({
        json: {
          date: "2026-08-28",
          timezone: "Europe/Istanbul",
          method: { id: methodId, code: "muslim-world-league" },
          times: {
            fajr: { local: "2026-08-28T05:42:00+03:00" },
            sunrise: { local: "2026-08-28T07:10:00+03:00" },
            dhuhr: { local: "2026-08-28T13:08:00+03:00" },
            asr: { local: "2026-08-28T17:12:00+03:00" },
            maghrib: { local: "2026-08-28T19:49:00+03:00" },
            isha: { local: "2026-08-28T21:15:00+03:00" },
          },
        },
      });
    }
    if (url.pathname === "/api/v1/me/today") {
      return route.fulfill({
        json: {
          local_date: "2026-08-28",
          timezone_name: "Europe/Istanbul",
          continue_reading: null,
          goal: null,
          progress: null,
          streak: { current_count: 0, longest_count: 0, last_qualifying_date: null },
        },
      });
    }
    if (url.pathname === "/api/v1/reciters") {
      return route.fulfill({ json: { next: null, previous: null, results: [] } });
    }
    if (url.pathname === "/api/v1/quran/editions") {
      return route.fulfill({ json: [] });
    }
    return route.fulfill({ status: 404, json: { detail: `Unhandled ${url.pathname}` } });
  });

  await page.goto("/ru");

  await expect.poll(() => calculation).toMatchObject({
    timezone: "Europe/Istanbul",
    location: { latitude: 41.0082, longitude: 28.9784 },
    method_config_id: methodId,
    asr_method: "hanafi",
    high_latitude_rule: "seventh_of_night",
    adjustments: { fajr: -3, isha: 2 },
  });
  const schedule = page.getByTestId("home-prayer-schedule");
  await expect(schedule.getByText("Часовой пояс: Europe/Istanbul")).toBeVisible();
  await expect(schedule.getByText("05:42")).toBeVisible();
});

test("home reciter avatars open the audio catalog with the selected reciter", async ({ page }) => {
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ status: 401 }));
  await page.route("**/api/v1/reciters", (route) =>
    route.fulfill({ json: { next: null, previous: null, results: reciters } }),
  );
  await page.route("**/api/v1/recitations?*", (route) =>
    route.fulfill({ json: { next: null, previous: null, results: [] } }),
  );

  await page.goto("/");

  const section = page.getByTestId("featured-reciters");
  await expect(section.getByRole("heading", { name: "Популярные чтецы" })).toBeVisible();
  await expect(section.getByTestId("featured-reciter")).toHaveCount(8);
  await expect(section.getByTestId("reciter-avatar")).toHaveCount(8);
  await expect(section.locator("img")).toHaveCount(8);
  await expect(section.getByTestId("reciter-avatar").first().locator(".reciter-avatar-initials"))
    .toHaveCount(0);
  await expect(section.locator("img").nth(0)).toHaveAttribute(
    "src",
    /\/reciters\/mishari-rashid-al-afasy\.webp$/,
  );
  const portraitSources = await section.locator("img").evaluateAll((images) =>
    images.map((image) => image.getAttribute("src")),
  );
  expect(new Set(portraitSources).size).toBe(8);
  expect(
    await section.locator(".reciter-grid").evaluate((grid) =>
      getComputedStyle(grid).gridTemplateColumns.split(" ").length,
    ),
  ).toBe(4);
  await expect(section.getByTestId("reciter-avatar").first()).toHaveCSS("width", "112px");
  await expect(section.getByTestId("reciter-avatar").first()).toHaveCSS("height", "112px");

  await page.setViewportSize({ width: 320, height: 760 });
  expect(
    await section.locator(".reciter-grid").evaluate((grid) =>
      getComputedStyle(grid).gridTemplateColumns.split(" ").length,
    ),
  ).toBe(2);
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(
    await page.evaluate(() => document.documentElement.clientWidth),
  );

  await section.getByRole("link", { name: "Слушать чтение: Абдур-Рахман ас-Судайс" }).click();

  await expect(page).toHaveURL(`/ru/audio?reciter=${reciters[4].id}`, { timeout: 15_000 });
  await expect(page.getByLabel("Чтец (Кари)")).toHaveValue(reciters[4].id);

  await page.goto("/ru/audio");
  await expect(page.getByLabel("Чтец (Кари)")).toHaveValue(reciters[4].id);
  await page.getByLabel("Чтец (Кари)").selectOption(reciters[8].id);
  await page.reload();
  await expect(page.getByLabel("Чтец (Кари)")).toHaveValue(reciters[8].id);
});

test("one reciter exposes multiple reading styles without duplicate person options", async ({ page }) => {
  const murattalOld = recitation(
    "00000000-0000-7000-8000-000000001001",
    reciters[0],
    "murattal",
    "2026-08-20T00:00:00Z",
  );
  const murattalCurrent = recitation(
    "00000000-0000-7000-8000-000000001002",
    reciters[0],
    "murattal",
    "2026-08-25T00:00:00Z",
  );
  const mujawwad = recitation(
    "00000000-0000-7000-8000-000000001003",
    reciters[1],
    "mujawwad",
    "2026-08-25T00:00:00Z",
  );

  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ status: 401 }));
  await page.route("**/api/v1/reciters", (route) =>
    route.fulfill({ json: { next: null, previous: null, results: reciters } }),
  );
  await page.route("**/api/v1/recitations?*", (route) => {
    const reciterId = new URL(route.request().url()).searchParams.get("reciter_id");
    const results = reciterId === reciters[0].id
      ? [murattalOld, murattalCurrent]
      : reciterId === reciters[1].id
        ? [mujawwad]
        : [];
    return route.fulfill({ json: { next: null, previous: null, results } });
  });
  await page.route("**/api/v1/recitations/*/tracks?*", (route) =>
    route.fulfill({ json: { next: null, previous: null, results: [] } }),
  );

  await page.goto(`/audio?reciter=${reciters[1].id}`);

  const reciterSelect = page.getByLabel("Чтец (Кари)");
  await expect(reciterSelect.locator("option")).toHaveCount(10);
  await expect(reciterSelect).toHaveValue(reciters[0].id);

  const readingSelect = page.getByLabel("Издание и стиль чтения");
  await expect(readingSelect.locator("option")).toHaveCount(2);
  await expect(readingSelect.locator("option")).toHaveText([
    "MUJAWWAD · Hafs 'an Asim (Треков: 114)",
    "MURATTAL · Hafs 'an Asim (Треков: 114)",
  ]);
});
