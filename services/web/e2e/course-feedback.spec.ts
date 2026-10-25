import { expect, test, type Page, type Request } from "@playwright/test";

// Share, votes, the course rating, lesson reports and anonymous counters
// (docs/courses/README.md, «Поделиться, оценка, замечания и статистика»).

const MOCK_API = `http://127.0.0.1:${process.env.MOCK_PUBLIC_API_PORT || 3199}`;

type CourseEvent = { course: string; lesson: string; event: string };

test.beforeEach(async ({ page }) => {
  // Each test walks several pages and a guest sign-in.
  test.slow();
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ status: 401 }));
});

async function mockState(page: Page) {
  const response = await page.request.get(`${MOCK_API}/__test__/course-events`);
  return (await response.json()) as {
    events: CourseEvent[];
    ratings: Record<string, unknown>[];
    reports: Record<string, unknown>[];
  };
}

/** The next batch of counters, sent when the page is left. */
async function nextBatch(page: Page): Promise<{ request: Request; events: CourseEvent[] }> {
  const request = page.waitForRequest((item) => item.url().endsWith("/api/v1/courses/events") && item.method() === "POST");
  await page.evaluate(() => window.dispatchEvent(new PageTransitionEvent("pagehide")));
  const sent = await request;
  return { request: sent, events: (sent.postDataJSON() as { events: CourseEvent[] }).events };
}

test("a computer copies the link; the pages carry the cover for messengers", async ({ page, context, baseURL }) => {
  await context.grantPermissions(["clipboard-read", "clipboard-write"]);
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto("/ru/courses/ramadan/namerenie");

  const share = page.getByTestId("course-share");
  await expect(share).toHaveText("Скопировать ссылку");
  await share.click();
  await expect(page.locator(".course-lesson-header [role=status]")).toHaveText("Ссылка скопирована");
  expect(await page.evaluate(() => navigator.clipboard.readText())).toBe(`${baseURL}/ru/courses/ramadan/namerenie`);

  // The lesson shows its video cover, the course its own cover.
  await expect(page.locator('meta[property="og:image"]')).toHaveAttribute("content", /courses\/posters\/[0-9a-f-]+-1280\.webp$/);
  await expect(page.locator('meta[name="twitter:card"]')).toHaveAttribute("content", "summary_large_image");
  await expect(page.locator('meta[property="og:url"]')).toHaveAttribute("content", `${baseURL}/ru/courses/ramadan/namerenie`);
  await page.goto("/ru/courses/ramadan");
  await expect(page.locator('meta[property="og:image"]')).toHaveAttribute("content", /courses\/covers\/[0-9a-f]+\.webp$/);
  await expect(page.locator('meta[property="og:image:width"]')).toHaveAttribute("content", "1280");
  await expect(page.getByTestId("course-share")).toHaveText("Скопировать ссылку");
});

test.describe("on a phone", () => {
  test.use({ viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true });

  test("the system share menu gets the title and the link", async ({ page, baseURL }) => {
    await page.addInitScript(() => {
      Object.defineProperty(navigator, "share", {
        configurable: true,
        value: async (data: ShareData) => {
          (window as unknown as { shared: ShareData }).shared = data;
        },
      });
    });
    await page.goto("/ru/courses/ramadan");

    const share = page.getByTestId("course-share");
    await expect(share).toHaveText("Поделиться");
    await share.click();
    await expect.poll(() => page.evaluate(() => (window as unknown as { shared?: ShareData }).shared)).toEqual({
      title: "Рамадан",
      text: expect.any(String),
      url: `${baseURL}/ru/courses/ramadan`,
    });
  });
});

test("«Полезно» counts once, and counters leave without cookies or an account", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto("/ru/courses/ramadan/smysl-posta");
  const feedback = page.getByTestId("lesson-feedback");
  await expect(feedback).toContainText("Тема была полезной?");

  await feedback.getByRole("button", { name: "Полезно" }).click();
  await expect(feedback).toContainText("Спасибо за отзыв");
  await expect(feedback.getByRole("button", { name: "Не очень" })).toHaveCount(0);
  expect(await page.evaluate(() => JSON.parse(localStorage.getItem("courses.vote.ramadan") || "null")))
    .toEqual({ "smysl-posta": "helpful" });

  await page.getByTestId("course-lesson-bar").getByRole("button", { name: "Тема изучена" }).click();
  const { request, events } = await nextBatch(page);
  expect(events).toEqual([
    { course: "ramadan", lesson: "smysl-posta", event: "lesson_opened" },
    { course: "ramadan", lesson: "smysl-posta", event: "lesson_helpful" },
    { course: "ramadan", lesson: "smysl-posta", event: "lesson_completed" },
  ]);
  const headers = await request.allHeaders();
  expect(headers.cookie).toBeUndefined();
  expect(headers.authorization).toBeUndefined();
  expect(JSON.parse(request.postData() || "{}").platform).toBe("web");

  await page.reload();
  await expect(feedback).toContainText("Спасибо за отзыв");
});

test("the video counts its start and its end", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto("/ru/courses/ramadan/namerenie");
  await page.getByTestId("lesson-video").getByRole("button").click();
  const player = page.locator("video");
  await expect.poll(() => player.evaluate((element: HTMLVideoElement) => element.currentTime)).toBeGreaterThan(0);
  await player.evaluate((element: HTMLVideoElement) => {
    element.currentTime = element.duration * 0.95;
  });

  await expect.poll(async () => (await nextBatch(page)).events.map((event) => event.event), { timeout: 10_000 })
    .toContain("video_finished");
  const events = (await mockState(page)).events.filter((event) => event.lesson === "namerenie").map((event) => event.event);
  expect(events).toEqual(expect.arrayContaining(["lesson_opened", "video_started", "video_finished"]));
});

test("«Сообщить об ошибке» sends a ticket that knows the lesson", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto("/ru/courses/ramadan/namerenie");
  await page.getByRole("button", { name: "Сообщить об ошибке" }).click();

  const dialog = page.getByTestId("lesson-report-dialog");
  await expect(dialog.getByRole("heading", { name: "Сообщить об ошибке" })).toBeVisible();
  await expect(dialog.getByLabel("Тип замечания")).toHaveValue("religious_content");
  await expect(dialog.getByRole("option")).toHaveText([
    "Ошибка в религиозном содержании",
    "Опечатка или перевод",
    "Не работает видео или страница",
    "Другое",
  ]);
  await expect(dialog.getByRole("button", { name: "Отправить" })).toBeDisabled();
  await dialog.getByLabel("Что не так?").fill("В цитате, кажется, неверный аят.");
  await dialog.getByLabel("Email для ответа (необязательно)").fill("student@example.test");
  await dialog.getByRole("button", { name: "Отправить" }).click();

  // The first guest session compiles its route in development mode.
  await expect(dialog).toContainText(/Спасибо! Номер обращения FB-e2e\d+\./, { timeout: 30_000 });
  await expect(dialog).toContainText("Ответ появится в профиле");
  const report = (await mockState(page)).reports.at(-1)!;
  expect(report).toMatchObject({
    category: "religious_content",
    subject: "Рамадан · 2. Намерение (ният)",
    message: "В цитате, кажется, неверный аят.",
    locale: "ru",
    contact_email: "student@example.test",
    context: {
      course_slug: "ramadan",
      lesson_slug: "namerenie",
      content_version: "1",
      route: "/courses/ramadan/namerenie",
      client_platform: "web",
    },
  });
  await dialog.getByRole("button", { name: "Закрыть" }).first().click();
  await expect(dialog).toHaveCount(0);
});

test("a report names the slide on screen", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto("/ru/courses/ramadan/namerenie");
  const slides = page.getByTestId("lesson-slides");
  await slides.getByRole("button", { name: "Следующий слайд" }).click();
  await slides.getByRole("button", { name: "Следующий слайд" }).click();
  await expect(slides).toHaveAttribute("data-index", "2");
  await page.getByRole("button", { name: "Сообщить об ошибке" }).click();
  const dialog = page.getByTestId("lesson-report-dialog");
  await expect(dialog.getByTestId("report-slide")).toHaveText("Приложим и номер слайда: 3.");
  await dialog.getByLabel("Что не так?").fill("На слайде опечатка.");
  await dialog.getByRole("button", { name: "Отправить" }).click();
  await expect(dialog).toContainText(/Номер обращения FB-e2e\d+\./, { timeout: 30_000 });
  const report = (await mockState(page)).reports.at(-1)!;
  expect(report).toMatchObject({ message: "На слайде опечатка.", context: { lesson_slug: "namerenie", slide_number: 3 } });
});

test("the rating appears after the last lesson and on the course page, never as an average", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto("/ru/courses/ramadan");
  await expect(page.getByTestId("course-progress")).toBeVisible();
  await expect(page.getByTestId("course-rating")).toHaveCount(0);

  await page.goto("/ru/courses/ramadan/taraviikh");
  await expect(page.getByTestId("course-rating")).toHaveCount(0);
  await page.getByTestId("course-lesson-bar").getByRole("button", { name: "Тема изучена" }).click();
  const rating = page.getByTestId("course-rating");
  await expect(rating.getByRole("group", { name: "Насколько курс был полезен?" })).toBeVisible();
  await expect(rating.getByRole("radio")).toHaveCount(5);
  await expect(rating.getByRole("button", { name: "Отправить" })).toBeDisabled();
  await rating.getByRole("radio", { name: "4 из 5" }).check({ force: true });
  await rating.getByLabel("Комментарий (необязательно)").fill("Спасибо, всё понятно");
  await expect(rating).toContainText("20 / 1000");
  await rating.getByRole("button", { name: "Отправить" }).click();

  await expect(rating).toContainText("Спасибо! Ваша оценка: 4 из 5");
  expect((await mockState(page)).ratings.at(-1)).toEqual({
    course: "ramadan",
    stars: 4,
    comment: "Спасибо, всё понятно",
    language: "ru",
    platform: "web",
  });
  expect(await page.evaluate(() => JSON.parse(localStorage.getItem("courses.rating.ramadan") || "null")))
    .toMatchObject({ stars: 4, comment: "Спасибо, всё понятно" });

  await page.goto("/ru/courses/ramadan");
  await expect(rating).toContainText("Спасибо! Ваша оценка: 4 из 5");
  await rating.getByRole("button", { name: "Изменить" }).click();
  await expect(rating.getByRole("radio", { name: "4 из 5" })).toBeChecked();
  await rating.getByRole("radio", { name: "5 из 5" }).check({ force: true });
  await rating.getByRole("button", { name: "Отправить" }).click();
  await expect(rating).toContainText("Спасибо! Ваша оценка: 5 из 5");
});
