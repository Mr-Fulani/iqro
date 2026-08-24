import { expect, test } from "@playwright/test";

const reciters = [
  {
    id: "00000000-0000-7000-8000-000000000159",
    slug: "qf-159-maher-al-muaiqly",
    name_ar: "ماهر المعيقلي",
    name_en: "Maher al-Muaiqly",
    name_ru: "Махер аль-Муайкли",
    country_code: "SA",
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
    id: "00000000-0000-7000-8000-000000000174",
    slug: "qf-174-yasser-ad-dussary",
    name_ar: "ياسر الدوسري",
    name_en: "Yasser ad-Dussary",
    name_ru: "Ясир ад-Дусари",
    country_code: "SA",
    portrait_url: null,
  },
];

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
  await expect(section.getByTestId("featured-reciter")).toHaveCount(3);
  await expect(section.getByTestId("reciter-avatar")).toHaveCount(3);
  await expect(section.locator("img")).toHaveCount(3);

  await section.getByRole("link", { name: "Слушать чтение: Мишари Рашид аль-Афаси" }).click();

  await expect(page).toHaveURL(`/ru/audio?reciter=${reciters[1].id}`, { timeout: 15_000 });
  await expect(page.getByLabel("Чтец (Кари)")).toHaveValue(reciters[1].id);
});
