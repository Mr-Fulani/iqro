import { access } from "node:fs/promises";
import path from "node:path";
import { expect, test } from "@playwright/test";
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
];

test("portrait manifest covers the full production reciter catalog", async () => {
  expect(Object.keys(RECITER_PORTRAITS).sort()).toEqual([...productionReciterSlugs].sort());
  expect(new Set(Object.values(RECITER_PORTRAITS)).size).toBe(16);

  for (const portraitUrl of new Set(Object.values(RECITER_PORTRAITS))) {
    expect(portraitUrl).toMatch(/^\/reciters\/[a-z0-9-]+\.webp$/);
    await access(path.join(process.cwd(), "public", portraitUrl.slice(1)));
  }
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
  await expect(section.getByTestId("featured-reciter")).toHaveCount(6);
  await expect(section.getByTestId("reciter-avatar")).toHaveCount(6);
  await expect(section.locator("img")).toHaveCount(6);
  await expect(section.locator("img").nth(0)).toHaveAttribute(
    "src",
    /\/reciters\/abdul-baset-abdul-samad\.webp$/,
  );
  await expect(section.locator("img").nth(1)).toHaveAttribute(
    "src",
    /\/reciters\/abdul-baset-abdul-samad\.webp$/,
  );

  await section.getByRole("link", { name: "Слушать чтение: Абдур-Рахман ас-Судайс" }).click();

  await expect(page).toHaveURL(`/ru/audio?reciter=${reciters[4].id}`, { timeout: 15_000 });
  await expect(page.getByLabel("Чтец (Кари)")).toHaveValue(reciters[4].id);
});
