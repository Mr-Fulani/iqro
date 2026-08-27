import { access, stat } from "node:fs/promises";
import path from "node:path";
import { expect, test } from "@playwright/test";
import { groupRecitersByPerson } from "../lib/reciter-catalog";
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
  const eyebrowTop = await hero.locator(".hero-content .eyebrow").evaluate(
    (element) => element.getBoundingClientRect().top,
  );
  expect(carouselBottom).toBeLessThanOrEqual(eyebrowTop);
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
  await expect(section.getByRole("heading", { name: "Слушайте любимых чтецов" })).toBeVisible();
  await expect(section.getByTestId("featured-reciter")).toHaveCount(10);
  await expect(section.getByTestId("reciter-avatar")).toHaveCount(10);
  await expect(section.locator("img")).toHaveCount(10);
  await expect(section.locator("img").nth(0)).toHaveAttribute(
    "src",
    /\/reciters\/abdul-baset-abdul-samad\.webp$/,
  );
  const portraitSources = await section.locator("img").evaluateAll((images) =>
    images.map((image) => image.getAttribute("src")),
  );
  expect(new Set(portraitSources).size).toBe(10);
  expect(
    await section.locator(".reciter-grid").evaluate((grid) =>
      getComputedStyle(grid).gridTemplateColumns.split(" ").length,
    ),
  ).toBe(5);

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
