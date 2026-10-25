import { type ElementHandle, expect, test, type Page } from "@playwright/test";

const progressKey = "salah.progress.hanbali-umdah";

test.beforeEach(async ({ page }) => {
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ status: 401 }));
  // Formula recordings live on external hosts; keep the suite offline.
  await page.route(/\.(mp3|m4a)(\?|$)/, (route) => route.fulfill({ status: 404 }));
});

function counter(page: Page) {
  return page.getByTestId("salah-step-counter");
}

// The player restores the step and progress after hydration; act only then.
async function openLesson(page: Page, path: string) {
  await page.goto(path);
  await expect(page.getByTestId("salah-player")).toHaveAttribute("aria-busy", "false");
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

test("header and mobile navigation mark the prayer course without the prayer times", async ({ page }) => {
  await page.setViewportSize({ width: 1400, height: 900 });
  await page.goto("/ru/salah");
  // The header has one entry for all courses; the course opens from its catalog.
  const header = page.locator(".app-menu");
  await expect(header.getByRole("link", { name: "Курсы" })).toHaveClass(/menu-link-active/);
  await expect(header.getByRole("link", { name: "Обучение намазу" })).toHaveCount(0);
  await expect(header.getByRole("link", { name: "Намаз", exact: true })).not.toHaveClass(/menu-link-active/);

  await page.setViewportSize({ width: 390, height: 844 });
  const navigation = page.locator(".mobile-navigation");
  await navigation.locator(".mobile-more > summary").click();
  // «More» leads to the course through the catalog, as in the app.
  const more = navigation.locator(".mobile-more-links");
  await expect(more.getByRole("link", { name: "Курсы" })).toHaveAttribute("aria-current", "page");
  await expect(more.getByRole("link", { name: "Обучение намазу" })).toHaveCount(0);
  await expect(more.getByRole("link", { name: "Намаз", exact: true })).not.toHaveAttribute("aria-current", "page");
  for (const [locale, label] of [["en", "Courses"], ["ar", "الدورات"], ["tr", "Kurslar"]]) {
    await page.goto(`/${locale}/salah`);
    await navigation.locator(".mobile-more > summary").click();
    await expect(more.getByRole("link", { name: label })).toHaveAttribute("href", `/${locale}/courses`);
  }
  // The footer leads to the catalog only; the prayer course is a card there.
  await expect(page.locator('footer a[href="/tr/salah"]')).toHaveCount(0);
  await expect(page.locator('footer a[href="/tr/courses"]')).toHaveCount(1);
});

test("the step player moves with buttons and arrow keys and keeps the step in the URL", async ({ page }) => {
  await openLesson(page, "/ru/salah/fajr");
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

  await openLesson(page, "/ru/salah/fajr#fajr.r2.tashahhud");
  await expect(counter(page)).toHaveText("Шаг 4 из 5 · Ракаат 2");
  await openLesson(page, "/ru/salah/fajr?step=fajr.r1.ruku");
  await expect(counter(page)).toHaveText("Шаг 3 из 5 · Ракаат 1");
});

test("arrow keys are mirrored on the Arabic RTL page", async ({ page }) => {
  await openLesson(page, "/ar/salah/fajr");
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

/** Seconds of silence as a WAV file: a recording the browser can play offline. */
function silentWav(seconds: number) {
  const rate = 8000;
  const bytes = rate * seconds * 2;
  const wav = Buffer.alloc(44 + bytes);
  wav.write("RIFF", 0);
  wav.writeUInt32LE(36 + bytes, 4);
  wav.write("WAVEfmt ", 8);
  wav.writeUInt32LE(16, 16);
  wav.writeUInt16LE(1, 20); // PCM
  wav.writeUInt16LE(1, 22); // mono
  wav.writeUInt32LE(rate, 24);
  wav.writeUInt32LE(rate * 2, 28);
  wav.writeUInt16LE(2, 32);
  wav.writeUInt16LE(16, 34);
  wav.write("data", 36);
  wav.writeUInt32LE(bytes, 40);
  return wav;
}

test("a step's recording stops when the visitor leaves the step and starts over on return", async ({ page }) => {
  await page.route(/\.(mp3|m4a)(\?|$)/, (route) => route.fulfill({ contentType: "audio/wav", body: silentWav(8) }));
  await openLesson(page, "/ru/salah/fajr");
  const step = page.locator(".salah-step:not([hidden])");
  const listen = async () => {
    await step.getByRole("button", { name: "Слушать" }).click();
    return (await step.locator("audio").elementHandle())!;
  };
  // Where the clip is, or -1 while it is silent.
  const position = (audio: ElementHandle) =>
    audio.evaluate((element) => ((element as HTMLAudioElement).paused ? -1 : (element as HTMLAudioElement).currentTime));
  // The first click also starts the 3D scene, which can hold the page for a few seconds.
  const STARTED = { timeout: 15_000 };
  const sounding = () =>
    page.evaluate(() => [...document.querySelectorAll("audio")].filter((element) => !element.paused).length);

  let audio = await listen();
  await expect.poll(() => position(audio), STARTED).toBeGreaterThan(3);
  await page.getByRole("button", { name: "Далее" }).click();
  await expect.poll(() => position(audio)).toBe(-1);
  await expect(page.locator("audio")).toHaveCount(0);

  // Back on the step, the clip plays from its start.
  await page.getByRole("button", { name: "Назад" }).click();
  await expect(step).toHaveAttribute("data-step", "fajr.r1.takbir");
  audio = await listen();
  await expect.poll(() => position(audio), STARTED).toBeGreaterThan(0);
  expect(await position(audio)).toBeLessThan(2.5);

  // Another step's clip never sounds alongside.
  await page.getByRole("button", { name: "Далее" }).click();
  const fatiha = await listen();
  await expect.poll(() => position(fatiha), STARTED).toBeGreaterThan(0);
  expect(await position(audio)).toBe(-1);
  expect(await sounding()).toBe(1);

  // Hiding the page stops it, like the app going to the background.
  await page.evaluate(() => {
    Object.defineProperty(document, "hidden", { configurable: true, get: () => true });
    document.dispatchEvent(new Event("visibilitychange"));
  });
  await expect.poll(() => position(fatiha)).toBe(-1);
  await expect(page.locator("audio")).toHaveCount(0);
  await page.evaluate(() => {
    Object.defineProperty(document, "hidden", { configurable: true, get: () => false });
    document.dispatchEvent(new Event("visibilitychange"));
  });

  // So does leaving the lesson by a link.
  audio = await listen();
  await expect.poll(() => position(audio), STARTED).toBeGreaterThan(0);
  await page.locator('main a[href="/ru/salah"]').first().click();
  await expect(page).toHaveURL(/\/ru\/salah$/);
  await expect.poll(() => position(audio)).toBe(-1);
  expect(await sounding()).toBe(0);
});

test("formula cards play audio, count repetitions and switch text and modes", async ({ page }) => {
  await openLesson(page, "/ru/salah/fajr");
  const step = page.locator(".salah-step:not([hidden])");
  await step.getByRole("button", { name: "Слушать" }).click();
  const audio = step.locator("audio");
  await expect(audio).toHaveCount(1);
  await expect(audio).toHaveAttribute("src", /takbir-3f2a9c1d\.m4a$/);
  await page.getByRole("button", { name: "Далее" }).click();
  await expect(page.locator("audio")).toHaveCount(0);

  await openLesson(page, "/ru/salah/fajr#fajr.r1.ruku");
  await expect(step).toHaveAttribute("data-step", "fajr.r1.ruku");
  await expect(step.locator(".salah-transliteration")).toBeVisible();
  await expect(step.locator(".salah-translation")).toHaveText("Слава моему Великому Господу! -3 раза");
  await expect(step.locator(".salah-formula-caption")).toHaveText("«Хисн аль-Муслим», № 33");
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
  await expect(step.locator(".salah-formula-caption")).toHaveCount(0);
  await expect(step.locator(".salah-arabic")).toBeVisible();
  await expect(step.locator("img")).toBeVisible();
  await page.reload();
  await expect(page.getByRole("button", { name: "Практика" })).toHaveAttribute("aria-pressed", "true");
});

test("step notes open from «?» and «!» and close with Escape, a click outside or another step", async ({ page }) => {
  await openLesson(page, "/ru/salah/fajr#fajr.r1.ruku");
  const step = page.locator(".salah-step:not([hidden])");
  await expect(step.getByTestId("salah-note-icon")).toHaveCount(2);
  const help = step.getByRole("button", { name: "Справка", exact: true });
  const warning = step.getByRole("button", { name: "Важно", exact: true });
  await expect(help).toHaveText("?");
  await expect(warning).toHaveText("!");
  await expect(help).toHaveAttribute("aria-expanded", "false");
  await expect(step.getByRole("dialog")).toHaveCount(0);

  await help.click();
  const helpNote = step.getByRole("dialog", { name: "Справка" });
  await expect(helpNote).toBeVisible();
  await expect(helpNote).toContainText("Спина и голова на одной линии");
  await expect(help).toHaveAttribute("aria-expanded", "true");
  await expect(helpNote).toBeFocused();
  // The popover stays inside the step, whatever the width.
  const [noteBox, stepBox] = [await helpNote.boundingBox(), await step.boundingBox()];
  expect(noteBox!.x).toBeGreaterThanOrEqual(stepBox!.x);
  expect(noteBox!.x + noteBox!.width).toBeLessThanOrEqual(stepBox!.x + stepBox!.width + 1);
  await page.keyboard.press("Escape");
  await expect(helpNote).toBeHidden();
  await expect(help).toBeFocused();

  // Keyboard only: Enter opens, Tab reaches «close», Enter closes and returns focus.
  await page.keyboard.press("Enter");
  await expect(helpNote).toBeVisible();
  await page.keyboard.press("Tab");
  await expect(helpNote.getByRole("button", { name: "Закрыть заметку" })).toBeFocused();
  await page.keyboard.press("Enter");
  await expect(helpNote).toBeHidden();
  await expect(help).toBeFocused();

  // One note at a time; a click outside closes it.
  await warning.click();
  await help.click();
  await expect(step.getByRole("dialog")).toHaveCount(1);
  await warning.click();
  const warningNote = step.getByRole("dialog", { name: "Важно" });
  await expect(warningNote).toContainText("без него ракаат не засчитывается");
  await counter(page).click();
  await expect(warningNote).toBeHidden();

  // Turning the step closes it; the next visit starts closed.
  await warning.click();
  await page.keyboard.press("ArrowRight");
  await expect(counter(page)).toHaveText("Шаг 4 из 5 · Ракаат 2");
  await page.keyboard.press("ArrowLeft");
  await expect(counter(page)).toHaveText("Шаг 3 из 5 · Ракаат 1");
  await expect(step.getByRole("dialog")).toHaveCount(0);

  // Practice shows only the picture, the Arabic and the audio.
  await page.getByRole("button", { name: "Практика" }).click();
  await expect(step.getByTestId("salah-note-icon")).toHaveCount(0);
});

test("notes are in the server HTML and mirrored on the Arabic page", async ({ page, request }) => {
  const html = await (await request.get("/ru/salah/fajr")).text();
  expect(html).toContain("Спина и голова на одной линии: не опускайте голову и не задирайте её.");

  await openLesson(page, "/ar/salah/fajr#fajr.r1.ruku");
  const step = page.locator(".salah-step:not([hidden])");
  const icons = step.getByTestId("salah-note-icon");
  await expect(icons.first()).toHaveAttribute("aria-label", "توضيح");
  // Right to left: the first note's icon is the rightmost.
  const [first, second] = [await icons.nth(0).boundingBox(), await icons.nth(1).boundingBox()];
  expect(first!.x).toBeGreaterThan(second!.x);
  await icons.nth(1).click();
  const note = step.getByRole("dialog", { name: "تنبيه مهم" });
  await expect(note).toBeVisible();
  const [noteBox, stepBox] = [await note.boundingBox(), await step.boundingBox()];
  expect(noteBox!.x).toBeGreaterThanOrEqual(stepBox!.x);
  expect(noteBox!.x + noteBox!.width).toBeLessThanOrEqual(stepBox!.x + stepBox!.width + 1);
  await page.keyboard.press("Escape");
  await expect(note).toBeHidden();
});

test("a step's own voice-over plays in the step and stops with the step", async ({ page }) => {
  await openLesson(page, "/ru/salah/fajr#fajr.r1.ruku");
  const step = page.locator(".salah-step:not([hidden])");
  const voice = step.getByTestId("salah-step-audio");
  await expect(voice).toHaveAccessibleName("Озвучка шага: Слушать");
  await voice.click();
  await expect(step.locator("audio")).toHaveAttribute("src", /audio-ruku-ru-[0-9a-f]+\.m4a$/);
  await expect(page.locator("audio")).toHaveCount(1);
  await page.getByRole("button", { name: "Далее" }).click();
  await expect(page.locator("audio")).toHaveCount(0);
});

test("on a phone the formulas' Arabic font waits for the page to load", async ({ page, request }) => {
  // The server sends the player without the switch: the font is not fetched for the first paint.
  const html = await (await request.get("/ru/salah/fajr")).text();
  expect(html).toContain('class="surface salah-player"');

  await page.setViewportSize({ width: 390, height: 844 });
  await openLesson(page, "/ru/salah/fajr");
  await expect(page.getByTestId("salah-player")).toHaveClass(/\bhas-formula-font\b/);
  const arabic = page.locator(".salah-step:not([hidden]) .salah-arabic").first();
  await expect.poll(() => arabic.evaluate((element) => getComputedStyle(element).fontFamily)).toMatch(/Amiri/);
});

test("progress resumes the lesson, restarts a missing step and keeps completion", async ({ page }) => {
  await openLesson(page, "/ru/salah/fajr");
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

  await openLesson(page, "/ru/salah/fajr");
  await expect(counter(page)).toHaveText("Шаг 3 из 5 · Ракаат 1");

  await page.evaluate((key) => {
    const progress = JSON.parse(window.localStorage.getItem(key)!);
    progress.lessons.fajr.step_slug = "fajr.r3.ruku";
    window.localStorage.setItem(key, JSON.stringify(progress));
  }, progressKey);
  await openLesson(page, "/ru/salah/fajr");
  await expect(counter(page)).toHaveText("Шаг 1 из 5 · Ракаат 1");

  await openLesson(page, "/ru/salah/fajr#fajr.r2.taslim");
  await page.getByRole("button", { name: "Завершить урок" }).click();
  await expect(page.getByRole("status").filter({ hasText: "Урок пройден" })).toBeVisible();
  expect((await storedProgress(page)).lessons.fajr.status).toBe("completed");

  await openLesson(page, "/ru/salah/fajr");
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

// Lesson media (docs/salah/lesson-media.md): the blocks of thematic courses on the first step.
const lessonMediaFile = /\/media\/courses\/(?:slides|banners|posters|videos)\//;

test("wudu's first step opens with its video, slide and banner; practice and other steps go without", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await openLesson(page, "/ru/salah/wudu");
  const first = page.locator('[data-step="wudu.intention"]');
  const media = first.locator(".salah-lesson-media .lesson-media > *");
  await expect(media).toHaveCount(3);
  await expect(media.nth(0)).toHaveClass("course-lesson-video");
  await expect(media.nth(1)).toHaveAttribute("data-testid", "lesson-slides");
  await expect(media.nth(2)).toHaveAttribute("data-testid", "lesson-banner");
  // Above the step's own text, centred and as wide as a lesson of the other courses.
  expect(await first.evaluate((step) => step.firstElementChild?.className)).toBe("salah-lesson-media");
  const block = (await first.locator(".salah-lesson-media").boundingBox())!;
  const body = (await first.locator(".salah-step-body").boundingBox())!;
  expect(block.y + block.height).toBeLessThanOrEqual(body.y + 1);
  expect(block.width).toBeCloseTo(760, 0);
  expect(Math.abs(block.x + block.width / 2 - (body.x + body.width / 2))).toBeLessThan(2);

  const video = page.getByTestId("lesson-video");
  const cover = video.getByRole("button", { name: /^Смотреть видео «Вуду», 3:04/ });
  await expect(cover).toBeVisible();
  await expect(page.getByRole("region", { name: "Слайды" }).locator(".lesson-slides-captions p[data-current]"))
    .toHaveText("Порядок омовения: лицо, руки, голова, ноги");
  await expect(media.nth(2).locator("img")).toHaveAttribute("alt", "Купол и минарет мечети на рассвете");

  // A video playing on the first step stops when the step changes.
  await cover.click();
  const player = video.locator("video");
  await expect.poll(() => player.evaluate((element: HTMLVideoElement) => element.currentTime)).toBeGreaterThan(0);
  await page.getByTestId("salah-player").getByRole("button", { name: /^Далее/ }).click();
  await expect(counter(page)).toHaveText(/^Шаг 2 из 2/);
  expect(await player.evaluate((element: HTMLVideoElement) => element.paused)).toBe(true);
  await expect(page.locator(".salah-lesson-media")).toBeHidden();

  // Practice is the prayer alone: no media, as no instruction.
  await page.getByTestId("salah-player").getByRole("button", { name: /^Назад/ }).click();
  await expect(media).toHaveCount(3);
  await page.getByRole("button", { name: "Практика" }).click();
  await expect(page.locator(".salah-lesson-media")).toHaveCount(0);
});

test("a lesson without media has no media block and asks for no media files", async ({ page, request }) => {
  const html = await (await request.get("/ru/salah/fajr")).text();
  expect(html).not.toContain("lesson-media");
  const requested: string[] = [];
  page.on("request", (item) => {
    if (lessonMediaFile.test(new URL(item.url()).pathname)) requested.push(item.url());
  });
  await openLesson(page, "/ru/salah/fajr");
  await expect(page.locator(".salah-lesson-media, [data-testid=lesson-video]")).toHaveCount(0);
  await page.waitForLoadState("networkidle");
  expect(requested).toEqual([]);
});

test("the prayer-times page links to the course", async ({ page }) => {
  await page.goto("/ru/prayer");
  const link = page.getByTestId("prayer-salah-link");
  await expect(link).toHaveText("Обучение намазу");
  await expect(link).toHaveAttribute("href", "/ru/salah");
});
