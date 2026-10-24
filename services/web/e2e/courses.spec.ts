import { expect, test, type Page } from "@playwright/test";

const progressKey = "courses.progress.ramadan";
const positionKey = "courses.position.ramadan";
const videoFile = /\/media\/courses\/videos\/[^/]+\.mp4$/;

test.beforeEach(async ({ page }) => {
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ status: 401 }));
});

async function storedProgress(page: Page) {
  return page.evaluate((key) => JSON.parse(window.localStorage.getItem(key) || "null"), progressKey);
}

async function storedPosition(page: Page): Promise<number | null> {
  return page.evaluate((key) => JSON.parse(window.localStorage.getItem(key) || "{}").namerenie?.ms ?? null, positionKey);
}

/** Requests for the video file itself; the cover alone must never start one. */
function watchVideoRequests(page: Page): string[] {
  const requests: string[] = [];
  page.on("request", (request) => {
    if (videoFile.test(new URL(request.url()).pathname)) requests.push(request.url());
  });
  return requests;
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
  await expect(cards.filter({ hasText: "Рамадан" })).toContainText("Тем: 3 · 30 мин. · 10 мин видео");
  await expect(page.locator(".app-menu").getByRole("link", { name: "Курсы" })).toHaveClass(/menu-link-active/);

  await cards.filter({ hasText: "Рамадан" }).click();
  await expect(page).toHaveURL("/ru/courses/ramadan");
  const summary = page.getByTestId("course-progress");
  await expect(summary).toContainText("0 из 3 тем");
  await expect(summary.getByRole("link", { name: "Начать курс" })).toHaveAttribute("href", "/ru/courses/ramadan/smysl-posta");
  await expect(page.locator(".course-hero")).toContainText("30 мин. · 10 мин видео");
  const lessonCards = page.locator(".course-lesson-card");
  await expect(lessonCards.nth(1)).toContainText("12 мин. · видео 9:48");
  await expect(lessonCards.nth(0)).not.toContainText("видео");

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

test("the video waits behind its cover until ▶, plays in place and remembers where it stopped", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  const requests = watchVideoRequests(page);
  await page.goto("/ru/courses/ramadan/namerenie");
  await expect(page.locator(".course-lesson-header")).toContainText("12 мин. · видео 9:48");
  const video = page.getByTestId("lesson-video");
  const cover = video.getByRole("button", { name: "Смотреть видео «Намерение (ният)», 9:48, 108 МБ" });
  await expect(cover).toBeVisible();
  await expect(video).toContainText("9:48 · 108 МБ");
  const image = cover.locator("img");
  await expect(image).toHaveAttribute("fetchpriority", "high");
  await expect(image).toHaveAttribute("srcset", /-640\.webp 640w, .+-1280\.webp 1280w$/);
  // The cover keeps the 16:9 box, so nothing moves when the player takes its place.
  const box = (await video.boundingBox())!;
  expect(Math.abs(box.width / box.height - 16 / 9)).toBeLessThan(0.01);
  // The video speaks the page's language: no note about it.
  await expect(page.getByTestId("lesson-video-language")).toHaveCount(0);
  await page.waitForLoadState("networkidle");
  expect(requests).toEqual([]);
  await expect(page.locator("video")).toHaveCount(0);

  await cover.click();
  const player = video.locator("video");
  await expect(player).toHaveAttribute("controls", "");
  await expect(player).toHaveAttribute("playsinline", "");
  await expect(player).toHaveAttribute("preload", "metadata");
  await expect(player).toBeFocused();
  await expect.poll(() => player.evaluate((element: HTMLVideoElement) => element.currentTime)).toBeGreaterThan(0);
  expect(requests.length).toBeGreaterThan(0);
  const after = (await video.boundingBox())!;
  expect(after.height).toBeCloseTo(box.height, 0);

  // A pause saves the position; the cover then offers to continue from it.
  await player.evaluate((element: HTMLVideoElement) => {
    element.currentTime = 3.4;
    element.pause();
  });
  await expect.poll(() => storedPosition(page)).toBe(3_400);
  await page.reload();
  await expect(video.getByRole("button", { name: "Смотреть видео «Намерение (ният)», 9:48, 108 МБ, продолжить с 0:03" }))
    .toBeVisible();
  await expect(video).toContainText("Продолжить с 0:03");
  await video.getByRole("button").click();
  await expect.poll(() => player.evaluate((element: HTMLVideoElement) => element.currentTime)).toBeGreaterThanOrEqual(3.4);

  // A video watched to the end forgets its position.
  await player.evaluate((element: HTMLVideoElement) => {
    element.currentTime = element.duration - 0.3;
    void element.play();
  });
  await expect.poll(() => storedPosition(page)).toBeNull();
  await page.reload();
  await expect(video).not.toContainText("Продолжить с");
});

test("«Continue» in the catalog says where the video stopped", async ({ page }) => {
  await page.goto("/ru/courses");
  await page.evaluate(([progress, position]) => {
    window.localStorage.setItem(progress, JSON.stringify({
      lessons: {
        "smysl-posta": { status: "completed", step_slug: "", content_version: "1", updated_at: "2026-10-24T10:00:00Z" },
        namerenie: { status: "in_progress", step_slug: "", content_version: "1", updated_at: "2026-10-24T10:05:00Z" },
      },
    }));
    window.localStorage.setItem(position, JSON.stringify({ namerenie: { ms: 252_000, updated_at: "2026-10-24T10:09:00Z" } }));
  }, [progressKey, positionKey]);
  await page.reload();
  const strip = page.getByTestId("courses-continue");
  await expect(strip).toContainText("Рамадан · Тема 2 «Намерение (ният)» · с 4:12");
  await strip.getByRole("link", { name: "Продолжить" }).click();
  await expect(page).toHaveURL("/ru/courses/ramadan/namerenie");
  await expect(page.getByTestId("lesson-video")).toContainText("Продолжить с 4:12");
});

test("a video that does not load says so and tries again; the notes stay", async ({ page }) => {
  let broken = true;
  await page.route(videoFile, (route) => (broken ? route.fulfill({ status: 503, body: "" }) : route.fallback()));
  await page.goto("/ru/courses/ramadan/namerenie");
  const video = page.getByTestId("lesson-video");
  await video.getByRole("button").click();
  await expect(video.getByRole("alert")).toHaveText("Видео не загрузилось");
  await expect(video).toHaveAttribute("data-state", "error");
  await expect(page.locator(".course-notes h3")).toHaveText("Что такое намерение");

  broken = false;
  await video.getByRole("button", { name: "Повторить" }).click();
  await expect(video).toHaveAttribute("data-state", "playing");
  await expect.poll(() => video.locator("video").evaluate((element: HTMLVideoElement) => element.currentTime))
    .toBeGreaterThan(0);
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

  // No Arabic dub yet: the Arabic lesson gets the Russian voice and says so in Arabic.
  await expect(page.getByTestId("lesson-video-language")).toHaveText("الفيديو باللغة الروسية");
  const video = page.getByTestId("lesson-video");
  await expect(video.getByRole("button", { name: /^شاهد فيديو «النية»/ })).toBeVisible();
  // The size chip sits at the inline end, the left in RTL.
  const videoBox = (await video.boundingBox())!;
  const meta = (await video.locator(".lesson-video-meta").boundingBox())!;
  expect(meta.x - videoBox.x).toBeLessThan(videoBox.width / 2);

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

  test("the video cover fills the width and a tap starts the player", async ({ page }) => {
    const requests = watchVideoRequests(page);
    await page.goto("/ru/courses/ramadan/namerenie");
    const video = page.getByTestId("lesson-video");
    const box = (await video.boundingBox())!;
    expect(box.width).toBeGreaterThan(330);
    expect(Math.abs(box.width / box.height - 16 / 9)).toBeLessThan(0.01);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
    await page.waitForLoadState("networkidle");
    expect(requests).toEqual([]);

    await video.getByRole("button").tap();
    await expect(video.locator("video")).toHaveAttribute("playsinline", "");
    await expect.poll(() => requests.length).toBeGreaterThan(0);
  });

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
