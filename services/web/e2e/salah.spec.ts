import { expect, test, type Page } from "@playwright/test";

const progressKey = "salah.progress.hanbali-umdah";

test.beforeEach(async ({ page }) => {
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ status: 401 }));
  // Formula recordings live on external hosts; keep the suite offline.
  await page.route(/\.(mp3|m4a)(\?|$)/, (route) => route.fulfill({ status: 404 }));
});

function counter(page: Page) {
  return page.getByTestId("salah-step-counter");
}

async function storedProgress(page: Page) {
  return page.evaluate((key) => JSON.parse(window.localStorage.getItem(key) || "null"), progressKey);
}

test("course and lesson pages render indexable steps and Arabic on the server", async ({ request }) => {
  const course = await request.get("/ru/salah");
  expect(course.ok()).toBe(true);
  const courseHtml = await course.text();
  expect(courseHtml).toContain("<h1>Обучение намазу</h1>");
  for (const text of ["Основы", "Очищение", "Пять молитв", "Что такое намаз", "Вуду", "Фаджр"]) {
    expect(courseHtml).toContain(text);
  }
  expect(courseHtml).toContain('href="/ru/salah/fajr"');
  expect(courseHtml).toMatch(/<link rel="canonical" href="[^"]+\/ru\/salah"/);

  const lesson = await request.get("/ru/salah/fajr");
  expect(lesson.ok()).toBe(true);
  const html = await lesson.text();
  expect(html).toContain("<title>Фаджр · Обучение намазу | Quran Platform</title>");
  for (const title of ["Начальный такбир", "Аль-Фатиха", "Руку&#x27;", "Последний ташаххуд", "Таслим"]) {
    expect(html).toContain(title);
  }
  expect(html).toContain('<p class="salah-arabic" lang="ar" dir="rtl">السَّلَامُ عَلَيْكُمْ وَرَحْمَةُ اللَّهِ</p>');
  expect(html).toContain('width="720" height="720"');
  expect(html).not.toContain("noindex");

  expect((await request.get("/ru/salah/missing-lesson")).status()).toBe(404);
  expect((await request.get("/ru/salah/Bad_Slug")).status()).toBe(404);
});

test("mobile navigation marks the prayer course without the prayer times", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/ru/salah");
  const navigation = page.locator(".mobile-navigation");
  await navigation.locator(".mobile-more > summary").click();
  const more = navigation.locator(".mobile-more-links");
  await expect(more.getByRole("link", { name: "Обучение намазу" })).toHaveAttribute("aria-current", "page");
  await expect(more.getByRole("link", { name: "Намаз", exact: true })).not.toHaveAttribute("aria-current", "page");
  for (const [locale, label] of [["en", "Learn to pray"], ["ar", "تعلّم الصلاة"], ["tr", "Namaz öğrenimi"]]) {
    await page.goto(`/${locale}/salah`);
    await navigation.locator(".mobile-more > summary").click();
    await expect(more.getByRole("link", { name: label })).toHaveAttribute("href", `/${locale}/salah`);
  }
});

test("the step player moves with buttons and arrow keys and keeps the step in the URL", async ({ page }) => {
  await page.goto("/ru/salah/fajr");
  const player = page.getByTestId("salah-player");
  await expect(counter(page)).toHaveText("Шаг 1 из 5 · Ракаат 1");
  await expect(player.getByRole("button", { name: "Назад" })).toBeDisabled();
  await expect(page.locator(".salah-rakats li")).toHaveCount(2);
  await expect(page.locator('.salah-rakats li[aria-current="step"]')).toHaveCount(1);
  await expect(page.locator(".salah-rakats li").first()).toHaveAttribute("aria-current", "step");

  const image = player.locator(".salah-step:not([hidden]) img");
  await expect(image).toHaveAttribute("width", "720");
  await expect(image).toHaveAttribute("height", "720");
  await expect(image).toHaveAttribute("alt", "Стоящий мужчина поднимает руки до плеч");
  await expect(page.locator('link[rel="preload"][as="image"][href*="position-qiyam"]')).toHaveCount(1);

  await player.getByRole("button", { name: "Далее" }).click();
  await expect(counter(page)).toHaveText("Шаг 2 из 5 · Ракаат 1");
  await expect(page).toHaveURL(/\/ru\/salah\/fajr#fajr\.r1\.fatiha$/);
  await expect(page.locator('link[rel="preload"][as="image"][href*="position-ruku"]')).toHaveCount(1);

  await page.keyboard.press("ArrowRight");
  await expect(counter(page)).toHaveText("Шаг 3 из 5 · Ракаат 1");
  await page.keyboard.press("ArrowRight");
  await expect(counter(page)).toHaveText("Шаг 4 из 5 · Ракаат 2");
  await expect(page.locator(".salah-rakats li").first()).toHaveClass(/is-done/);
  await expect(page.locator(".salah-rakats li").nth(1)).toHaveAttribute("aria-current", "step");
  await page.keyboard.press("ArrowLeft");
  await expect(counter(page)).toHaveText("Шаг 3 из 5 · Ракаат 1");
  await expect(player.getByRole("heading", { name: "Руку'" })).toBeVisible();
  await expect(player.getByRole("heading", { name: "Таслим" })).toBeHidden();

  await page.goto("/ru/salah/fajr#fajr.r2.tashahhud");
  await expect(counter(page)).toHaveText("Шаг 4 из 5 · Ракаат 2");
  await page.goto("/ru/salah/fajr?step=fajr.r1.ruku");
  await expect(counter(page)).toHaveText("Шаг 3 из 5 · Ракаат 1");
});

test("arrow keys are mirrored on the Arabic RTL page", async ({ page }) => {
  await page.goto("/ar/salah/fajr");
  await expect(page.locator("html")).toHaveAttribute("dir", "rtl");
  await expect(counter(page)).toContainText("1");
  const step = page.locator(".salah-step:not([hidden])");
  await expect(step).toHaveAttribute("data-step", "fajr.r1.takbir");
  await page.keyboard.press("ArrowLeft");
  await expect(step).toHaveAttribute("data-step", "fajr.r1.fatiha");
  await page.keyboard.press("ArrowLeft");
  await expect(step).toHaveAttribute("data-step", "fajr.r1.ruku");
  await page.keyboard.press("ArrowRight");
  await expect(step).toHaveAttribute("data-step", "fajr.r1.fatiha");
  await expect(page.getByRole("button", { name: /التالي/ })).toContainText("←");
  await expect(step.locator(".salah-arabic")).toHaveAttribute("lang", "ar");
});

test("formula cards play audio, count repetitions and switch text and modes", async ({ page }) => {
  await page.goto("/ru/salah/fajr");
  const step = page.locator(".salah-step:not([hidden])");
  await step.getByRole("button", { name: "Слушать" }).click();
  const audio = step.locator("audio");
  await expect(audio).toHaveCount(1);
  await expect(audio).toHaveAttribute("src", /takbir-3f2a9c1d\.m4a$/);
  await page.getByRole("button", { name: "Далее" }).click();
  await expect(page.locator("audio")).toHaveCount(0);

  await page.goto("/ru/salah/fajr#fajr.r1.ruku");
  await expect(step).toHaveAttribute("data-step", "fajr.r1.ruku");
  await expect(step.locator(".salah-transliteration")).toBeVisible();
  await expect(step.locator(".salah-translation")).toHaveText("Слава моему Великому Господу! -3 раза");
  const counterGroup = step.getByRole("group", { name: "Повторить 3 раза" });
  await expect(counterGroup).toHaveCount(1);
  for (let repetition = 0; repetition < 3; repetition += 1) {
    await counterGroup.getByRole("button", { name: "Отметить повтор" }).click();
  }
  await expect(counterGroup.locator("output")).toHaveText("Готово · 3");
  await counterGroup.getByRole("button", { name: "Сбросить счётчик" }).click();
  await expect(counterGroup.locator("output")).toHaveText("0 из 3");

  await page.getByLabel("Транслитерация").uncheck();
  await expect(step.locator(".salah-transliteration")).toHaveCount(0);
  await page.getByLabel("Перевод").uncheck();
  await expect(step.locator(".salah-translation")).toHaveCount(0);

  await page.getByRole("button", { name: "Практика" }).click();
  await expect(page.getByRole("button", { name: "Практика" })).toHaveAttribute("aria-pressed", "true");
  await expect(step.locator(".salah-instruction")).toHaveCount(0);
  await expect(step.locator(".salah-arabic")).toBeVisible();
  await expect(step.locator("img")).toBeVisible();
  await page.reload();
  await expect(page.getByRole("button", { name: "Практика" })).toHaveAttribute("aria-pressed", "true");
});

test("progress resumes the lesson, restarts a missing step and keeps completion", async ({ page }) => {
  await page.goto("/ru/salah/fajr");
  await page.getByRole("button", { name: "Далее" }).click();
  await page.getByRole("button", { name: "Далее" }).click();
  await expect(counter(page)).toHaveText("Шаг 3 из 5 · Ракаат 1");
  const saved = await storedProgress(page);
  expect(saved.lessons.fajr).toMatchObject({
    status: "in_progress",
    step_slug: "fajr.r1.ruku",
    content_version: "2026-10-18",
  });

  await page.goto("/ru/salah");
  const summary = page.getByTestId("salah-course-progress");
  await expect(summary).toContainText("0 из 3 уроков");
  await expect(summary.getByRole("link", { name: "Продолжить" })).toHaveAttribute("href", "/ru/salah/fajr#fajr.r1.ruku");
  await expect(page.getByRole("link", { name: /Фаджр/ }).locator(".salah-lesson-status")).toHaveText("Начат");

  await page.goto("/ru/salah/fajr");
  await expect(counter(page)).toHaveText("Шаг 3 из 5 · Ракаат 1");

  await page.evaluate((key) => {
    const progress = JSON.parse(window.localStorage.getItem(key)!);
    progress.lessons.fajr.step_slug = "fajr.r3.ruku";
    window.localStorage.setItem(key, JSON.stringify(progress));
  }, progressKey);
  await page.goto("/ru/salah/fajr");
  await expect(counter(page)).toHaveText("Шаг 1 из 5 · Ракаат 1");

  // A cross-document load, so the step comes from the address at hydration
  // rather than from a hash change racing it in development mode.
  await page.goto("/ru/salah");
  await page.goto("/ru/salah/fajr#fajr.r2.taslim");
  await page.getByRole("button", { name: "Завершить урок" }).click();
  await expect(page.getByRole("status").filter({ hasText: "Урок пройден" })).toBeVisible();
  expect((await storedProgress(page)).lessons.fajr.status).toBe("completed");

  await page.goto("/ru/salah/fajr");
  await expect(counter(page)).toHaveText("Шаг 1 из 5 · Ракаат 1");
  await page.getByRole("button", { name: "Далее" }).click();
  expect((await storedProgress(page)).lessons.fajr).toMatchObject({
    status: "completed",
    step_slug: "fajr.r1.fatiha",
  });

  await page.goto("/ru/salah");
  await expect(summary).toContainText("1 из 3 уроков");
  await expect(summary.getByRole("link", { name: "Продолжить" })).toHaveAttribute("href", "/ru/salah/what-is-salah");
  await expect(page.getByRole("link", { name: /Фаджр/ }).locator(".salah-lesson-status")).toHaveText("Пройден");
});

test("the prayer-times page links to the course", async ({ page }) => {
  await page.goto("/ru/prayer");
  await page.getByTestId("prayer-salah-link").click();
  await expect(page).toHaveURL("/ru/salah");
  await expect(page.getByRole("heading", { level: 1, name: "Обучение намазу" })).toBeVisible();
});
