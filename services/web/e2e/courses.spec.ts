import { expect, test, type Page } from "@playwright/test";

const progressKey = "courses.progress.ramadan";
const positionKey = "courses.position.ramadan";
const videoFile = /\/media\/courses\/videos\/[^/]+\.mp4$/;
const slideFile = /\/media\/courses\/slides\/([0-9a-f]{20})(?:-800)?\.webp$/;

test.beforeEach(async ({ page }) => {
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ status: 401 }));
});

async function storedProgress(page: Page) {
  return page.evaluate((key) => JSON.parse(window.localStorage.getItem(key) || "null"), progressKey);
}

async function storedPosition(page: Page): Promise<number | null> {
  return page.evaluate((key) => JSON.parse(window.localStorage.getItem(key) || "{}").namerenie?.ms ?? null, positionKey);
}

/** The slide pictures the page asked for, by their hash. */
function watchSlideRequests(page: Page): Set<string> {
  const hashes = new Set<string>();
  page.on("request", (request) => {
    const match = slideFile.exec(new URL(request.url()).pathname);
    if (match) hashes.add(match[1]!.slice(0, 4));
  });
  return hashes;
}

/** How far the current slide is from the frame's edge; 0 once the track has moved. */
async function slideOffset(page: Page): Promise<number> {
  return page.getByTestId("lesson-slides").evaluate((carousel) => {
    const frame = carousel.querySelector(".lesson-slides-frame")!.getBoundingClientRect();
    const index = Number((carousel as HTMLElement).dataset.index);
    const slide = carousel.querySelectorAll(".lesson-slides-slide")[index]!.getBoundingClientRect();
    return Math.round(Math.abs(slide.left - frame.left - 1));
  });
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

test("the prayer card shows its cover like a thematic course; tajweed without one keeps its icon", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/en/courses");
  const cards = page.locator(".courses-grid > li > a");
  // The covers do not depend on the language: English has no thematic course, the cards stay.
  await expect(cards).toHaveCount(2);
  const salah = page.locator('a[href="/en/salah"]');
  const cover = salah.locator(".courses-card-art img");
  await expect(cover).toHaveAttribute("src", "/media/courses/covers/fedcba9876543210fedc-640.webp");
  await expect(cover).toHaveAttribute("srcset", /fedcba9876543210fedc\.webp 1280w/);
  await expect(cover).toHaveAttribute("alt", "");
  await expect.poll(() => cover.evaluate((image: HTMLImageElement) => image.complete && image.naturalWidth > 0)).toBe(true);
  const box = (await salah.locator(".courses-card-art").boundingBox())!;
  expect(Math.abs(box.width / box.height - 16 / 9)).toBeLessThan(0.02);
  await expect(salah.locator(".courses-card-icon")).toHaveCount(0);
  await expect(salah).toContainText("A step-by-step prayer course");

  const tajweed = page.locator('a[href="/en/tajweed"]');
  await expect(tajweed.locator(".courses-card-art-builtin .courses-card-icon")).toBeVisible();
  await expect(tajweed.locator("img")).toHaveCount(0);
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

test("lesson media: the video, then slides that turn with arrows, dots, ←/→ and a drag", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  const slideRequests = watchSlideRequests(page);
  await page.goto("/ru/courses/ramadan/namerenie");
  const media = page.locator(".lesson-media > *");
  await expect(media).toHaveCount(2);
  await expect(media.nth(0)).toHaveClass("course-lesson-video");
  const carousel = page.getByRole("region", { name: "Слайды" });
  await expect(carousel).toHaveAttribute("aria-roledescription", "карусель");
  await expect(media.nth(1)).toHaveAttribute("data-testid", "lesson-slides");

  const counter = carousel.locator(".lesson-slides-counter");
  const caption = carousel.locator(".lesson-slides-captions p[data-current]");
  const live = carousel.locator("[aria-live=polite]");
  const previous = carousel.getByRole("button", { name: "Предыдущий слайд" });
  const next = carousel.getByRole("button", { name: "Следующий слайд" });
  await expect(counter).toHaveText("1 / 5");
  await expect(caption).toHaveText("[Когда делать намерение — схема после проверки]");
  await expect(caption).toHaveAttribute("dir", "ltr");
  await expect(live).toHaveText("");
  await expect(previous).toHaveAttribute("aria-disabled", "true");
  await expect(carousel.getByRole("button", { name: /^Слайд \d из 5$/ })).toHaveCount(5);

  // The tallest slide is 3:4: the frame stops at 4:5 and, on a desktop, at 80% of the screen's height.
  const frame = (await carousel.locator(".lesson-slides-frame").boundingBox())!;
  expect(frame.height).toBeCloseTo(Math.min(frame.width * 1.25, 900 * 0.8), 0);
  const first = carousel.locator(".lesson-slides-slide").first().locator("img");
  await expect(first).toHaveAttribute("srcset", /-800\.webp 800w, .+\.webp 1600w$/);
  await expect(first).toHaveAttribute("alt", "Схема: ночь, рассвет и время намерения");
  // On a phone the first slide is larger than the video's cover: it loads first too.
  await expect(first).toHaveAttribute("fetchpriority", "high");
  await expect(carousel.locator(".lesson-slides-slide").nth(1).locator("img")).not.toHaveAttribute("fetchpriority", /.*/);
  expect(await first.evaluate((image) => getComputedStyle(image).objectFit)).toBe("contain");
  // Only the current slide and its neighbour load at first.
  await expect(carousel.locator(".lesson-slides-slide img")).toHaveCount(2);
  await page.waitForLoadState("networkidle");
  expect([...slideRequests].sort()).toEqual(["1111", "3333"]);
  await expect(carousel.locator(".lesson-slides-slide").nth(1)).toHaveAttribute("aria-hidden", "true");

  await next.click();
  await expect(counter).toHaveText("2 / 5");
  await expect(live).toHaveText("Слайд 2 из 5");
  await expect(caption).toHaveText("نويت صوم غد");
  await expect(caption).toHaveAttribute("dir", "rtl");
  await expect.poll(() => slideOffset(page)).toBe(0);
  await expect(carousel.locator(".lesson-slides-slide img")).toHaveCount(3);
  await expect.poll(() => [...slideRequests].sort()).toEqual(["1111", "3333", "4444"]);

  const fourth = carousel.getByRole("button", { name: "Слайд 4 из 5" });
  await fourth.click();
  await expect(counter).toHaveText("4 / 5");
  await expect(fourth).toHaveAttribute("aria-current", "true");
  // An empty caption keeps its line, so the notes below do not move.
  await expect(caption).toHaveText("");

  // ←/→ while the focus is in the carousel; the focus follows the dots.
  await page.keyboard.press("ArrowLeft");
  await expect(counter).toHaveText("3 / 5");
  await expect(carousel.getByRole("button", { name: "Слайд 3 из 5" })).toBeFocused();
  await page.keyboard.press("ArrowRight");
  await page.keyboard.press("ArrowRight");
  await expect(counter).toHaveText("5 / 5");
  await expect(next).toHaveAttribute("aria-disabled", "true");
  await page.keyboard.press("ArrowRight");
  await expect(counter).toHaveText("5 / 5");
  await expect.poll(() => slideOffset(page)).toBe(0);

  // A drag to the right brings the slide before; a short one snaps back.
  await carousel.locator(".lesson-slides-frame").scrollIntoViewIfNeeded();
  const box = (await carousel.locator(".lesson-slides-frame").boundingBox())!;
  const y = box.y + box.height / 2;
  await page.mouse.move(box.x + box.width / 2, y);
  await page.mouse.down();
  await page.mouse.move(box.x + box.width / 2 + 40, y, { steps: 4 });
  await page.mouse.up();
  await expect(counter).toHaveText("5 / 5");
  await page.mouse.move(box.x + box.width / 2, y);
  await page.mouse.down();
  await page.mouse.move(box.x + box.width / 2 + 300, y, { steps: 6 });
  await page.mouse.up();
  await expect(counter).toHaveText("4 / 5");
  await expect.poll(() => slideOffset(page)).toBe(0);

  // Keys outside the carousel do not turn slides.
  await page.locator("h1").click();
  await page.keyboard.press("ArrowLeft");
  await expect(counter).toHaveText("4 / 5");
});

test("a banner is a 16:9 picture above the notes; the lesson has no video", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto("/ru/courses/ramadan/smysl-posta");
  await expect(page.locator(".course-lesson-header")).not.toContainText("видео");
  await expect(page.getByTestId("lesson-video")).toHaveCount(0);
  const banner = page.getByTestId("lesson-banner");
  const image = banner.getByRole("img", { name: "Полумесяц над минаретом на закате" });
  await expect(image).toHaveAttribute("srcset", /-800\.webp 800w, .+bbbb\.webp 1600w$/);
  await expect(image).toHaveAttribute("fetchpriority", "high");
  // 880 px wide on a 1× screen: the 1600 px file.
  await expect.poll(() => image.evaluate((element: HTMLImageElement) => element.complete && element.currentSrc))
    .toMatch(/bbbb\.webp$/);
  const box = (await image.boundingBox())!;
  expect(Math.abs(box.width / box.height - 16 / 9)).toBeLessThan(0.01);
  // An empty caption draws nothing.
  await expect(banner.locator("figcaption")).toHaveCount(0);
  const notes = (await page.locator(".course-lesson-notes").boundingBox())!;
  expect(box.y + box.height).toBeLessThan(notes.y);
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

test("«!» and «?» after a word open their note; Escape and a tap outside close it; links lead into the site", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto("/ru/courses/ramadan/namerenie");
  const notes = page.locator(".course-notes");
  const help = notes.getByRole("button", { name: "Пояснение" });
  const warning = notes.getByRole("button", { name: "Внимание" });
  await expect(help).toHaveText("?");
  await expect(warning).toHaveText("!");
  // The icon stands right after its word, in the line of text.
  expect(await help.evaluate((element) => [
    element.previousSibling?.textContent?.endsWith("ради Аллаха"),
    element.nextElementSibling?.getAttribute("popover"),
    element.nextElementSibling?.nextSibling?.textContent,
  ])).toEqual([true, "auto", "."]);
  const icon = (await help.boundingBox())!;
  const line = (await notes.locator("p").first().boundingBox())!;
  expect(icon.y).toBeLessThan(line.y + 40);
  // A 20 px circle with a 44 px tap target.
  const target = await help.evaluate((element) => {
    const after = getComputedStyle(element, "::after");
    return element.getBoundingClientRect().width - 2 * parseFloat(after.left);
  });
  expect(target).toBeGreaterThanOrEqual(44);

  const popover = page.getByRole("dialog", { name: "Пояснение" });
  await expect(popover).toBeHidden();
  await help.click();
  await expect(popover).toBeVisible();
  await expect(popover).toContainText("Пояснение о намерении — после проверки.");
  await page.keyboard.press("Escape");
  await expect(popover).toBeHidden();

  await warning.click();
  const warningNote = page.getByRole("dialog", { name: "Внимание" });
  await expect(warningNote).toContainText("Предупреждение — после проверки.");
  await page.mouse.click(10, 10);
  await expect(warningNote).toBeHidden();
  await warning.click();
  await warningNote.getByRole("button", { name: "Закрыть" }).click();
  await expect(warningNote).toBeHidden();

  const ayah = notes.getByRole("link", { name: "Коран, 2:183" });
  await expect(ayah).toHaveAttribute("href", "/ru/quran?surah=2&ayah=183");
  await expect(ayah).not.toHaveAttribute("target", /.+/);
});

test("Arabic notes mirror the «?» icon and its note", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/ar/courses/ramadan/namerenie");
  const notes = page.locator(".course-notes");
  const help = notes.getByRole("button", { name: "توضيح" });
  const word = notes.locator("strong", { hasText: "عزم القلب" });
  // In a right-to-left line the icon after a word stands to its left.
  expect((await help.boundingBox())!.x).toBeLessThan((await word.boundingBox())!.x);
  await help.click();
  const popover = page.getByRole("dialog", { name: "توضيح" });
  await expect(popover).toBeVisible();
  expect(await popover.evaluate((element) => getComputedStyle(element).direction)).toBe("rtl");
  await expect(popover.getByRole("button", { name: "إغلاق" })).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(popover).toBeHidden();
  await expect(notes.getByRole("link", { name: "آية الصيام" })).toHaveAttribute("href", "/ar/quran?surah=2&ayah=183");
});

test("Arabic slides mirror the order, the arrows and the keys", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto("/ar/courses/ramadan/namerenie");
  const carousel = page.getByRole("region", { name: "الشرائح" });
  const counter = carousel.locator(".lesson-slides-counter");
  const number = (value: number) => page.evaluate((item) => new Intl.NumberFormat("ar").format(item), value);
  await expect(counter).toHaveText(`${await number(1)} / ${await number(5)}`);
  const caption = carousel.locator(".lesson-slides-captions p[data-current]");
  await expect(caption).toHaveText("متى تكون النية");
  await expect(caption).toHaveAttribute("dir", "rtl");

  // «Next» is on the left and points left.
  const previous = carousel.getByRole("button", { name: "الشريحة السابقة" });
  const next = carousel.getByRole("button", { name: "الشريحة التالية" });
  expect((await next.boundingBox())!.x).toBeLessThan((await previous.boundingBox())!.x);
  expect(await next.locator("svg").evaluate((icon) => getComputedStyle(icon).transform)).toBe("matrix(-1, 0, 0, 1, 0, 0)");

  // The second slide waits on the left of the first.
  const frame = (await carousel.locator(".lesson-slides-frame").boundingBox())!;
  const second = (await carousel.locator(".lesson-slides-slide").nth(1).boundingBox())!;
  expect(second.x).toBeLessThan(frame.x);

  await next.click();
  await expect(counter).toHaveText(`${await number(2)} / ${await number(5)}`);
  await expect(carousel.locator("[aria-live=polite]")).toHaveText(`الشريحة ${await number(2)} من ${await number(5)}`);
  await expect.poll(() => slideOffset(page)).toBe(0);
  // ← goes forward in Arabic, → back.
  await page.keyboard.press("ArrowLeft");
  await expect(counter).toHaveText(`${await number(3)} / ${await number(5)}`);
  await page.keyboard.press("ArrowRight");
  await page.keyboard.press("ArrowRight");
  await expect(counter).toHaveText(`${await number(1)} / ${await number(5)}`);

  // A drag to the left brings the slide before, so to the right the next one.
  await carousel.locator(".lesson-slides-frame").scrollIntoViewIfNeeded();
  const box = (await carousel.locator(".lesson-slides-frame").boundingBox())!;
  const y = box.y + box.height / 2;
  await page.mouse.move(box.x + box.width / 2, y);
  await page.mouse.down();
  await page.mouse.move(box.x + box.width / 2 + 300, y, { steps: 6 });
  await page.mouse.up();
  await expect(counter).toHaveText(`${await number(2)} / ${await number(5)}`);
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

  test("slides fill the width, load the small pictures and turn with a swipe", async ({ page }) => {
    const slideRequests = watchSlideRequests(page);
    await page.goto("/ru/courses/ramadan/namerenie");
    const carousel = page.getByTestId("lesson-slides");
    const frame = carousel.locator(".lesson-slides-frame");
    await frame.scrollIntoViewIfNeeded();
    const box = (await frame.boundingBox())!;
    expect(box.width).toBeGreaterThan(330);
    // The tallest slide is 3:4; the frame stops at 4:5.
    expect(box.height / box.width).toBeCloseTo(1.25, 2);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);
    const image = carousel.locator(".lesson-slides-slide img").first();
    await expect.poll(() => image.evaluate((element: HTMLImageElement) => element.currentSrc)).toMatch(/-800\.webp$/);
    for (const arrow of await carousel.locator(".lesson-slides-arrow").all()) {
      expect((await arrow.boundingBox())!.height).toBeGreaterThanOrEqual(44);
    }

    // A real touch swipe: Chromium turns it into pointer events, a vertical pan stays the page's.
    const cdp = await page.context().newCDPSession(page);
    const y = box.y + box.height / 2;
    const touch = async (type: "touchStart" | "touchMove" | "touchEnd", x: number) =>
      cdp.send("Input.dispatchTouchEvent", { type, touchPoints: type === "touchEnd" ? [] : [{ x, y }] });
    await touch("touchStart", box.x + box.width - 40);
    for (let step = 1; step <= 6; step += 1) await touch("touchMove", box.x + box.width - 40 - step * 40);
    await touch("touchEnd", 0);
    await expect(carousel.locator(".lesson-slides-counter")).toHaveText("2 / 5");
    await expect.poll(() => [...slideRequests].sort()).toEqual(["1111", "3333", "4444"]);
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
