import { expect, test, type Page } from "@playwright/test";

const progressKey = "courses.progress.ramadan";

test.beforeEach(async ({ page }) => {
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ status: 401 }));
});

async function storedProgress(page: Page) {
  return page.evaluate((key) => JSON.parse(window.localStorage.getItem(key) || "null"), progressKey);
}

test("catalog → course → lesson → «lesson learned» keeps progress on the device", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto("/ru/courses");
  await expect(page.getByRole("heading", { level: 1, name: "Курсы" })).toBeVisible();
  // The prayer and tajweed courses come first and keep their own pages.
  const cards = page.locator(".courses-grid > li > a");
  await expect(cards).toHaveCount(3);
  expect(await cards.evaluateAll((links) => links.map((link) => link.getAttribute("href"))))
    .toEqual(["/ru/salah", "/ru/tajweed", "/ru/courses/ramadan"]);
  await expect(page.getByTestId("courses-continue")).toHaveCount(0);
  await expect(page.locator(".app-menu").getByRole("link", { name: "Курсы" })).toHaveClass(/menu-link-active/);

  await cards.filter({ hasText: "Рамадан" }).click();
  await expect(page).toHaveURL("/ru/courses/ramadan");
  const summary = page.getByTestId("course-progress");
  await expect(summary).toContainText("0 из 3 тем");
  await expect(summary.getByRole("link", { name: "Начать курс" })).toHaveAttribute("href", "/ru/courses/ramadan/smysl-posta");

  await page.getByRole("link", { name: /Намерение \(ният\)/ }).click();
  await expect(page).toHaveURL("/ru/courses/ramadan/namerenie");
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Намерение (ният)");
  await expect(page.getByText("Тема 2 из 3")).toBeVisible();
  const notes = page.locator(".course-notes");
  await expect(notes.locator("h3")).toHaveText("Что такое намерение");
  await expect(notes.locator("strong", { hasText: "решение сердца" })).toBeVisible();
  await expect(notes.locator(".course-notes-note")).toContainText("Важно.");
  await expect(page.locator(".course-lesson-sources li")).toHaveCount(2);
  // Opening a lesson starts it.
  await expect.poll(() => storedProgress(page)).toMatchObject({
    lessons: { namerenie: { status: "in_progress", step_slug: "", content_version: "1" } },
  });

  const bar = page.getByTestId("course-lesson-bar");
  await bar.getByRole("button", { name: "Тема изучена" }).click();
  await expect(bar).toHaveAttribute("data-completed", "true");
  await expect(bar).toContainText("Тема пройдена");
  await expect(bar.getByRole("link", { name: "Дальше: Таравих" })).toHaveAttribute("href", "/ru/courses/ramadan/taraviikh");
  await expect(page.locator(".course-outline a[aria-current=page]")).toContainText("Пройдена");
  expect(await storedProgress(page)).toMatchObject({
    lessons: { namerenie: { status: "completed", step_slug: "", content_version: "1" } },
  });

  await page.reload();
  await expect(bar).toHaveAttribute("data-completed", "true");

  await page.goto("/ru/courses/ramadan");
  await expect(summary).toContainText("1 из 3 тем");
  // «Continue» opens the first lesson not learned yet.
  await expect(summary.getByRole("link", { name: "Продолжить" })).toHaveAttribute("href", "/ru/courses/ramadan/smysl-posta");

  await page.goto("/ru/courses");
  const strip = page.getByTestId("courses-continue");
  await expect(strip).toContainText("Рамадан · Тема 1 «Смысл поста»");
  await expect(strip.getByRole("link", { name: "Продолжить" })).toHaveAttribute("href", "/ru/courses/ramadan/smysl-posta");
  await expect(cards.filter({ hasText: "Рамадан" })).toContainText("Начат · 1 из 3");
});

test("course pages render on the server with release-only hreflang; unknown ones are 404", async ({ page, request }) => {
  const html = await (await request.get("/ru/courses/ramadan/namerenie")).text();
  expect(html).toContain("<h1>Намерение (ният)</h1>");
  expect(html).toContain("<strong>решение сердца</strong>");
  expect(html).toContain('hrefLang="ar"');
  // The release has Russian and Arabic only.
  expect(html).not.toContain('hrefLang="en"');
  expect(html).not.toContain('hrefLang="tr"');

  // A language without the release has no course.
  expect((await request.get("/en/courses/ramadan")).status()).toBe(404);
  expect((await request.get("/ru/courses/missing")).status()).toBe(404);
  expect((await request.get("/ru/courses/salah")).status()).toBe(404);
  expect((await request.get("/ru/courses/Bad_Slug")).status()).toBe(404);
  expect((await request.get("/ru/courses/ramadan/missing")).status()).toBe(404);

  await page.goto("/en/courses");
  await expect(page.locator(".courses-grid > li")).toHaveCount(2);
  await expect(page.getByTestId("courses-empty")).toContainText("New courses are coming soon");

  // A document from a newer backend asks for a reload instead of guessing.
  await page.goto("/ru/courses/future-format");
  await expect(page.getByTestId("course-outdated")).toContainText("Обновите страницу");
});

test("Arabic lesson reads right to left with Arabic runs in the Arabic font", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto("/ar/courses/ramadan/namerenie");
  await expect(page.locator("html")).toHaveAttribute("dir", "rtl");
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("النية");
  const notes = page.locator(".course-notes");
  await expect(notes.locator(":scope > *")).toHaveCount(5);
  for (const block of await notes.locator(":scope > *").all()) await expect(block).toHaveAttribute("dir", "rtl");
  const arabic = notes.locator('bdi[lang="ar"]').first();
  expect(await arabic.evaluate((element) => getComputedStyle(element).fontFamily)).toMatch(/Amiri/i);
  await expect(notes.locator('figure[dir="rtl"] figcaption')).toHaveText("— صحيح البخاري، 1");

  // The main column is on the right and the lesson list on the left.
  const main = await page.locator(".course-lesson-main").boundingBox();
  const outline = await page.locator(".course-outline").boundingBox();
  expect(outline!.x).toBeLessThan(main!.x);
  const bar = page.getByTestId("course-lesson-bar");
  await bar.getByRole("button", { name: "تعلّمت الدرس" }).click();
  await expect(bar.getByRole("link", { name: "التالي: التراويح" })).toHaveAttribute("href", "/ar/courses/ramadan/taraviikh");
});

test.describe("on a phone", () => {
  test.use({ viewport: { width: 390, height: 640 }, isMobile: true, hasTouch: true });

  test("the lesson bar stays fixed above the tab bar", async ({ page }) => {
    await page.goto("/ru/courses/ramadan/namerenie");
    const bar = page.getByTestId("course-lesson-bar");
    const tabs = page.locator(".mobile-navigation");
    await expect(bar.getByRole("button", { name: "Тема изучена" })).toBeVisible();
    await expect(bar.getByRole("link", { name: "Предыдущая тема: Смысл поста" })).toBeVisible();
    await expect(bar.getByRole("link", { name: "Дальше: Таравих" })).toBeVisible();

    for (const scroll of [0, 200]) {
      await page.evaluate((y) => window.scrollTo(0, y), scroll);
      const barBox = (await bar.boundingBox())!;
      const tabsBox = (await tabs.boundingBox())!;
      expect(Math.abs(barBox.y + barBox.height - tabsBox.y)).toBeLessThanOrEqual(1);
    }

    await bar.getByRole("button", { name: "Тема изучена" }).tap();
    await expect(bar).toHaveAttribute("data-completed", "true");

    // The catalog is in «More» on a phone.
    await tabs.locator(".mobile-more > summary").click();
    await expect(tabs.locator(".mobile-more-links").getByRole("link", { name: "Курсы" }))
      .toHaveAttribute("href", "/ru/courses");
  });
});
