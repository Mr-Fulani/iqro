import { expect, test } from "@playwright/test";

const RECITER = "Новый чтец: Хани ар-Рифаи";
const FEATURE = "Живой компас Киблы";

test("desktop card: one at a time, closing it is remembered without a flash", async ({ page }) => {
  await page.goto("/ru");
  const card = page.locator("[data-announcement-card]");
  await expect(card).toHaveCount(1);
  await expect(card.getByRole("heading", { name: RECITER })).toBeVisible();
  await expect(card.getByRole("link", { name: "Послушать" })).toHaveAttribute("href", /\/ru\/audio\?reciter=.+&play=1/);
  await expect(page.getByTestId("header-news-link")).toHaveAccessibleName("Что нового, непрочитанных: 2");

  await card.getByRole("button", { name: "Скрыть объявление" }).click();
  await expect(page.locator("[data-announcement-card]").getByRole("heading", { name: FEATURE })).toBeVisible();
  await expect(page.getByTestId("header-news-link")).toHaveAccessibleName("Что нового, непрочитанных: 1");

  await page.reload();
  // The closed card is hidden before hydration: it never shows up again.
  await expect(page.getByRole("heading", { name: RECITER })).toHaveCount(0);
  await expect(page.getByRole("heading", { name: FEATURE })).toBeVisible();
});

test("desktop card explains a feature step by step and marks it read", async ({ page }) => {
  await page.goto("/ru");
  await page.locator("[data-announcement-card]").getByRole("button", { name: "Скрыть объявление" }).click();
  await page.getByRole("button", { name: "Как пользоваться" }).click();
  const dialog = page.getByTestId("announcement-dialog");
  await expect(dialog).toBeVisible();
  await expect(dialog.getByRole("heading", { name: FEATURE })).toBeVisible();
  await expect(dialog.locator(".announcement-steps li")).toHaveCount(2);
  await expect(dialog.getByRole("link", { name: "Открыть компас" })).toHaveAttribute("href", "/ru/prayer?qibla=1");
  await page.keyboard.press("Escape");
  await expect(dialog).toBeHidden();
  await expect(page.locator("[data-announcement-card]")).toHaveCount(0);
});

test("phone bubble pops into the window and then stays away", async ({ page }) => {
  // The bubble bobs forever; with reduced motion it stands still and can be tapped.
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/ru");
  await expect(page.locator("[data-announcement-card]")).toBeHidden();
  const bubble = page.getByTestId("announcement-bubble");
  await expect(bubble).toBeVisible();
  await expect(bubble).toHaveAccessibleName("Новое: 2. Открыть");

  await bubble.click();
  const dialog = page.getByTestId("announcement-dialog");
  await expect(dialog).toBeVisible();
  await expect(dialog).toContainText("1 из 2");
  await expect(dialog.getByRole("heading", { name: RECITER })).toBeVisible();
  await dialog.getByRole("button", { name: "Следующее" }).click();
  await expect(dialog).toContainText("2 из 2");
  await expect(dialog.getByRole("heading", { name: FEATURE })).toBeVisible();
  await dialog.getByRole("button", { name: "Закрыть" }).click();
  await expect(dialog).toBeHidden();
  await expect(bubble).toHaveCount(0);

  await page.reload();
  await expect(page.getByRole("heading", { name: "Единая исламская платформа: Коран, аудио, Ду’а и время намаза" })).toBeVisible();
  await expect(page.getByTestId("announcement-bubble")).toHaveCount(0);
});

test("phone bubble and window in Arabic follow the right-to-left layout", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/ar");
  const bubble = page.getByTestId("announcement-bubble");
  await expect(bubble).toHaveAccessibleName("جديد: 2. افتح");
  await bubble.click();
  const dialog = page.getByTestId("announcement-dialog");
  await expect(dialog.getByRole("heading", { name: "قارئ جديد: هاني الرفاعي" })).toBeVisible();
  await expect(dialog).toContainText("1 من 2");
  const width = await page.evaluate(() => document.documentElement.scrollWidth);
  expect(width).toBeLessThanOrEqual(390);
});

test("the «What's new» feed lists, filters and opens the news", async ({ page }) => {
  await page.goto("/ru/news");
  await expect(page.getByRole("heading", { level: 1, name: "Что нового" })).toBeVisible();
  const items = page.getByTestId("news-item");
  await expect(items).toHaveCount(3);
  await expect(page.getByRole("img", { name: "Не прочитано" })).toHaveCount(3);

  await page.getByRole("button", { name: "Чтецы" }).click();
  await expect(items).toHaveCount(1);
  await expect(items.first()).toContainText(RECITER);

  await page.getByRole("button", { name: "Все" }).click();
  await expect(items).toHaveCount(3);
  await items.filter({ hasText: "Курс намаза обновлён" }).getByRole("button", { name: "Подробнее" }).click();
  const dialog = page.getByTestId("announcement-dialog");
  await expect(dialog.locator("strong", { hasText: "Уроки" })).toBeVisible();
  await expect(dialog.locator(".announcement-body li")).toHaveCount(2);
  await page.keyboard.press("Escape");
  await expect(page.getByRole("img", { name: "Не прочитано" })).toHaveCount(2);
});

test("impressions and closes reach the server as anonymous counters", async ({ page, request }) => {
  await page.goto("/ru");
  await page.locator("[data-announcement-card]").getByRole("button", { name: "Скрыть объявление" }).click();
  await expect
    .poll(
      async () => {
        const response = await request.get("http://127.0.0.1:3199/__test__/announcement-events");
        const { events } = (await response.json()) as { events: { surface: string; event: string }[] };
        return events.map((item) => `${item.surface}:${item.event}`);
      },
      { timeout: 12_000 },
    )
    .toEqual(expect.arrayContaining(["card:impression", "card:dismiss"]));
});

const MOCK_API = `http://127.0.0.1:${process.env.MOCK_PUBLIC_API_PORT || 3199}`;
const RECITER_ID = "019a0000-0000-7000-8000-00000000a001";
const FEATURE_ID = "019a0000-0000-7000-8000-00000000a002";

test.describe("«Показать снова» in the admin", () => {
  test.afterEach(async ({ request }) => {
    await request.post(`${MOCK_API}/__test__/announcements/reset`);
    await refreshHome(request);
  });

  async function refreshHome(request: import("@playwright/test").APIRequestContext) {
    // The admin's change reaches the cached home page through the revalidation event.
    const response = await request.post("/api/internal/content-revalidation", {
      data: { type: "site.announcements.changed", action: "published" },
      headers: { Authorization: "Bearer test-only-content-revalidation-secret-0001" },
    });
    expect(response.ok()).toBe(true);
  }

  async function showAgain(page: import("@playwright/test").Page, id: string) {
    const request = page.request;
    expect((await request.post(`${MOCK_API}/__test__/announcements/show-again?id=${id}`)).ok()).toBe(true);
    await refreshHome(request);
    // Visitors get it once their cached copy of the list expires (5 minutes in production).
    const cdp = await page.context().newCDPSession(page);
    await cdp.send("Network.clearBrowserCache");
  }

  test("a closed card comes back on the home page in the next wave", async ({ page }) => {
    await page.goto("/ru");
    await page.locator("[data-announcement-card]").getByRole("button", { name: "Скрыть объявление" }).click();
    await page.reload();
    await expect(page.getByRole("heading", { name: RECITER })).toHaveCount(0);

    await showAgain(page, RECITER_ID);
    await expect(async () => {
      await page.reload();
      await expect(page.locator("[data-announcement-card]").getByRole("heading", { name: RECITER })).toBeVisible({
        timeout: 1_000,
      });
    }).toPass({ timeout: 15_000 });
    await expect(page.getByTestId("header-news-link")).toHaveAccessibleName("Что нового, непрочитанных: 2");

    // Closed again in the new wave: gone until the admin shows it once more.
    await page.locator("[data-announcement-card]").getByRole("button", { name: "Скрыть объявление" }).click();
    await page.reload();
    await expect(page.getByRole("heading", { name: RECITER })).toHaveCount(0);
    await expect(page.getByRole("heading", { name: FEATURE })).toBeVisible();
  });

  test("the bubble's impression limit starts over in a new wave", async ({ page }) => {
    await page.emulateMedia({ reducedMotion: "reduce" });
    await page.setViewportSize({ width: 390, height: 844 });
    const spent = { shown: 5, last: "2026-01-01T00:00:00.000Z", wave: 1 };
    await page.addInitScript(
      ([key, value]) => window.localStorage.setItem(key, value),
      [
        "iqro_announcements_v1",
        JSON.stringify({ bubble: { [RECITER_ID]: spent, [FEATURE_ID]: spent } }),
      ],
    );
    await page.goto("/ru");
    await expect(page.getByRole("heading", { level: 1 })).toBeVisible();
    await expect(page.getByTestId("announcement-bubble")).toHaveCount(0);

    await showAgain(page, RECITER_ID);
    await page.reload();
    const bubble = page.getByTestId("announcement-bubble");
    await expect(bubble).toHaveAccessibleName("Новое: 1. Открыть");
    await bubble.click();
    await expect(page.getByTestId("announcement-dialog").getByRole("heading", { name: RECITER })).toBeVisible();
  });
});

