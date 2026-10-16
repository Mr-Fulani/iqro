import { access, stat } from "node:fs/promises";
import path from "node:path";
import { expect, test } from "@playwright/test";
import { groupRecitersByPerson, selectHomePopularReciters } from "../lib/reciter-catalog";
import { RECITER_PORTRAITS } from "../lib/reciter-portraits";
import { abdulBaset, abdulBasetMujawwad, mishari, reciterPeopleCount, reciters, sudais } from "./fixtures/audio";

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

test("portrait manifest covers the full production reciter catalog", async () => {
  expect(Object.keys(RECITER_PORTRAITS).sort()).toEqual([...productionReciterSlugs].sort());
  expect(new Set(Object.values(RECITER_PORTRAITS)).size).toBe(16);

  for (const portraitUrl of new Set(Object.values(RECITER_PORTRAITS))) {
    expect(portraitUrl).toMatch(/^\/reciters\/[a-z0-9-]+\.webp$/);
    await access(path.join(process.cwd(), "public", portraitUrl.slice(1)));
  }

  const people = groupRecitersByPerson(reciters);
  expect(people).toHaveLength(reciterPeopleCount);
  expect(people.filter((reciter) => reciter.slug.includes("abdul-baset"))).toHaveLength(1);
  expect(people[1].slug).toBe("qf-2-abdul-baset-abdul-samad");

  const uploadedPortrait = "https://media.example.test/abdul-baset.png";
  const peopleWithVariantPortrait = groupRecitersByPerson(
    reciters.map((reciter) =>
      reciter.slug === "qf-1-abdulbaset-abdulsamad-mujawwad"
        ? { ...reciter, portrait_url: uploadedPortrait }
        : reciter,
    ),
  );
  expect(peopleWithVariantPortrait[1]).toMatchObject({
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
    "qf-159-maher-al-muaiqly",
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
  const carouselBottom = await hero.locator(".hero-carousel").evaluate(
    (element) => element.getBoundingClientRect().bottom,
  );
  const contentTop = await hero.locator(".eyebrow").evaluate(
    (element) => element.getBoundingClientRect().top,
  );
  expect(carouselBottom).toBeLessThanOrEqual(contentTop);
  await expect(hero.getByRole("heading", { level: 1 })).toHaveText(
    "Единая исламская платформа: Коран, аудио, Ду’а и время намаза",
  );
  await expect(hero.locator(".hero-content > p:not(.eyebrow)")).toBeVisible();
  await expect(hero.getByTestId("hero-media")).toHaveCSS("opacity", "1");
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

  await expect(page).toHaveURL(`/ru/audio?reciter=${sudais.id}`, { timeout: 15_000 });
  await expect(page.getByLabel("Чтец (Кари)")).toHaveValue(sudais.id);

  await page.goto("/ru/audio");
  await expect(page.getByLabel("Чтец (Кари)")).toHaveValue(sudais.id);
  await page.getByLabel("Чтец (Кари)").selectOption(mishari.id);
  await page.reload();
  await expect(page.getByLabel("Чтец (Кари)")).toHaveValue(mishari.id);
});

test("one reciter exposes multiple reading styles without duplicate person options", async ({ page }) => {
  // The shared catalog publishes two murattal versions and a mujawwad from
  // the person's second source.
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ status: 401 }));

  await page.goto(`/audio?reciter=${abdulBasetMujawwad.id}`);

  const reciterSelect = page.getByLabel("Чтец (Кари)");
  await expect(reciterSelect.locator("option")).toHaveCount(reciterPeopleCount);
  await expect(reciterSelect).toHaveValue(abdulBaset.id);

  const readingSelect = page.getByLabel("Издание и стиль чтения");
  await expect(readingSelect.locator("option")).toHaveCount(2);
  await expect(readingSelect.locator("option")).toHaveText([
    "MUJAWWAD · Hafs 'an Asim (Треков: 114)",
    "MURATTAL · Hafs 'an Asim (Треков: 114)",
  ]);
});
