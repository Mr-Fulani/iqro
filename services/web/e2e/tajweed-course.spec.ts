import { readFileSync } from "node:fs";

import { expect, test, type Page } from "@playwright/test";

const progressKey = "tajweed.progress.tajweed";
const examples = JSON.parse(
  readFileSync(new URL("./fixtures/tajweed-course-examples.json", import.meta.url), "utf8"),
) as Record<string, {
  examples: {
    verse_key: string;
    words: { position: number; text: string }[];
    occurrences: { parts: { position: number; start: number; end: number }[] }[];
  }[];
}>;

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

test.beforeEach(async ({ page }) => {
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ status: 401 }));
  // Every word of an ayah sounds one second, from the first second of the track.
  await page.route(/\/api\/v1\/recitations\/[^/]+\/ayahs\/\d+\/\d+$/, (route) => route.fulfill({
    json: {
      track: { asset: { url: "https://audio.example.test/tajweed-course.mp3" } },
      segment: {
        start_ms: 1_000,
        end_ms: 9_000,
        words: Array.from({ length: 8 }, (_, index) => [index + 1, 1_000 + index * 1_000, 2_000 + index * 1_000]),
      },
    },
  }));
  // Seeking to a word needs range requests, as a real audio host answers them.
  const wav = silentWav(10);
  await page.route(/\.mp3(\?|$)/, (route) => {
    const range = /bytes=(\d+)-(\d*)/.exec(route.request().headers().range ?? "");
    const start = range ? Number(range[1]) : 0;
    const end = range?.[2] ? Math.min(Number(range[2]), wav.length - 1) : wav.length - 1;
    return route.fulfill({
      status: range ? 206 : 200,
      contentType: "audio/wav",
      headers: { "Accept-Ranges": "bytes", ...(range ? { "Content-Range": `bytes ${start}-${end}/${wav.length}` } : {}) },
      body: wav.subarray(start, end + 1),
    });
  });
});

// The lesson restores its step after hydration and the examples; act only then.
async function openLesson(page: Page, path: string) {
  await page.goto(path);
  const lesson = page.getByTestId("tajweed-lesson");
  await expect(lesson).toHaveAttribute("aria-busy", "false");
  await expect(lesson.locator(".tajweed-course-ayah").first()).toBeAttached();
  return lesson;
}

function counter(page: Page) {
  return page.getByTestId("tajweed-lesson-counter");
}

async function storedProgress(page: Page) {
  return page.evaluate((key) => JSON.parse(window.localStorage.getItem(key) || "null"), progressKey);
}

test("course and lesson pages render on the server and unknown lessons are 404", async ({ request }) => {
  const course = await request.get("/ru/tajweed");
  expect(course.ok()).toBe(true);
  const courseHtml = await course.text();
  expect(courseHtml).toContain("<h1>Таджвид</h1>");
  for (const text of ["Нун с сукуном и танвин", "Мадды", "Лунные и солнечные буквы", "Калькаля"]) {
    expect(courseHtml).toContain(text);
  }
  expect(courseHtml).toContain('href="/ru/tajweed/izhar"');
  expect(courseHtml).toMatch(/<link rel="canonical" href="[^"]+\/ru\/tajweed"/);

  const lesson = await request.get("/ru/tajweed/idgham-without-ghunnah");
  expect(lesson.ok()).toBe(true);
  const html = await lesson.text();
  expect(html).toContain("· Таджвид | Quran Platform</title>");
  expect(html).toContain("Как читать");
  expect(html).toContain("الإدغام بغير غنة");
  expect(html).not.toContain("noindex");

  expect((await request.get("/ru/tajweed/missing-lesson")).status()).toBe(404);
  expect((await request.get("/ru/tajweed/Bad_Slug")).status()).toBe(404);
});

test("header, mobile navigation and footer lead to the course next to the prayer course", async ({ page }) => {
  await page.setViewportSize({ width: 1400, height: 900 });
  await page.goto("/ru/tajweed");
  // The header has one entry for all courses; the course opens from its catalog.
  const header = page.locator(".app-menu");
  await expect(header.getByRole("link", { name: "Курсы" })).toHaveClass(/menu-link-active/);
  await expect(header.getByRole("link", { name: "Таджвид" })).toHaveCount(0);
  await expect(page.locator("footer").getByRole("link", { name: "Таджвид" })).toHaveAttribute("href", "/ru/tajweed");

  await page.setViewportSize({ width: 390, height: 844 });
  const navigation = page.locator(".mobile-navigation");
  await navigation.locator(".mobile-more > summary").click();
  // «More» leads to the course through the catalog, as in the app.
  const more = navigation.locator(".mobile-more-links");
  await expect(more.getByRole("link", { name: "Курсы" })).toHaveAttribute("aria-current", "page");
  await expect(more.getByRole("link", { name: "Таджвид" })).toHaveCount(0);
  for (const [locale, label] of [["en", "Courses"], ["ar", "الدورات"], ["tr", "Kurslar"]]) {
    await page.goto(`/${locale}/tajweed`);
    await navigation.locator(".mobile-more > summary").click();
    await expect(more.getByRole("link", { name: label })).toHaveAttribute("href", `/${locale}/courses`);
  }
});

type Example = (typeof examples)[string]["examples"][number];

function placePositions(example: Example): Set<number> {
  return new Set(example.occurrences.flatMap((occurrence) => occurrence.parts.map((part) => part.position)));
}

function wordPositions(example: Example, inPlace: boolean): number[] {
  const place = placePositions(example);
  return example.words.map((word) => word.position).filter((position) => place.has(position) === inPlace);
}

test("a lesson explains the rule, plays its examples and asks to find it", async ({ page }) => {
  const lesson = await openLesson(page, "/ru/tajweed/ikhfa");
  await expect(counter(page)).toHaveText("Шаг 1 из 6: Правило");
  await expect(counter(page)).toHaveAttribute("aria-live", "polite");
  const step = lesson.locator(".tajweed-lesson-step:not([hidden])");
  await expect(step.getByRole("heading", { name: /Ихфа/ })).toBeVisible();
  await expect(step.locator(".tajweed-lesson-letters li")).toHaveCount(15);
  await expect(lesson.getByRole("button", { name: "Назад" })).toBeDisabled();

  await page.keyboard.press("ArrowRight");
  await expect(counter(page)).toHaveText("Шаг 2 из 6: Как читать");
  await page.keyboard.press("ArrowRight");
  await expect(counter(page)).toHaveText("Шаг 3 из 6: Пример 1 из 3");
  await expect(page).toHaveURL(/#example-1$/);

  // The example's place is lit in its words and played from its first word to its last.
  const first = examples.ikhfa!.examples[0]!;
  const lit = step.locator(".tajweed-course-word.is-lit");
  await expect(lit).toHaveCount(placePositions({ ...first, occurrences: first.occurrences.slice(0, 1) }).size);
  await expect(step.locator(".tajweed-course-ayah")).toHaveAttribute("dir", "rtl");
  expect((await step.locator(".tajweed-course-ayah").textContent())?.replaceAll("\u200d", ""))
    .toBe(first.words.map((word) => word.text).join(" "));
  const firstWord = Math.min(...first.occurrences[0]!.parts.map((part) => part.position));
  await step.getByRole("button", { name: "Медленнее, 0,75×" }).click();
  await step.getByRole("button", { name: "Послушать фрагмент" }).click();
  await expect(step.getByRole("button", { name: "Остановить" })).toBeVisible();
  const fragment = step.locator(".tajweed-audio audio");
  // Word N of the mocked timings sounds from N to N + 1 seconds.
  const playing = await fragment.evaluate((audio: HTMLAudioElement) => ({
    rate: audio.playbackRate,
    time: audio.currentTime,
    paused: audio.paused,
  }));
  expect(playing).toMatchObject({ rate: 0.75, paused: false });
  expect(playing.time).toBeGreaterThanOrEqual(firstWord);
  expect(playing.time).toBeLessThan(firstWord + 1);

  // A step change stops the sound.
  await page.keyboard.press("ArrowRight");
  await expect(counter(page)).toHaveText("Шаг 4 из 6: Пример 2 из 3");
  expect(await page.evaluate(() => [...document.querySelectorAll("audio")].every((audio) => audio.paused))).toBe(true);

  // «More examples» on the last example adds three before «find» and opens the first of them.
  await page.keyboard.press("ArrowRight");
  await lesson.getByRole("button", { name: "Ещё примеры" }).click();
  await expect(counter(page)).toHaveText("Шаг 6 из 9: Пример 4 из 6");
  await expect(page).toHaveURL(/#example-4$/);
  await expect(lesson.getByRole("button", { name: "Ещё примеры" })).toHaveCount(0);

  // «Find the rule»: the ayah is plain, a word with the rule lights the place.
  for (let turn = 0; turn < 3; turn += 1) await lesson.getByRole("button", { name: "Далее" }).click();
  await expect(counter(page)).toHaveText("Шаг 9 из 9: Найдите правило в аяте");
  const find = lesson.locator('[data-step="find"]');
  await expect(find.getByText("Нажмите на слово, в котором есть «Ихфа».")).toBeVisible();
  await expect(find.locator(".tajweed-course-word.is-lit")).toHaveCount(0);
  const findExample = examples.ikhfa!.examples[3]!;
  await find.locator(`button[data-word-position="${wordPositions(findExample, true)[0]}"]`).click();
  await expect(find.getByTestId("tajweed-find-feedback")).toHaveText("Верно! Здесь «Ихфа».");
  await expect(find.locator(".tajweed-course-word.is-lit").first()).toBeVisible();

  // Finishing marks the lesson passed and offers the next one.
  await lesson.getByRole("button", { name: "Завершить урок" }).click();
  await expect(lesson.getByRole("status").filter({ hasText: "Урок пройден" })).toBeVisible();
  await expect(lesson.getByRole("link", { name: /^Следующий урок:/ })).toHaveAttribute("href", "/ru/tajweed/ikhfa-shafawi");
  expect((await storedProgress(page)).lessons.ikhfa.status).toBe("completed");

  await page.goto("/ru/tajweed");
  await expect(page.getByTestId("tajweed-course-progress")).toContainText("1 из 21 уроков");
  await expect(page.locator('a[href="/ru/tajweed/ikhfa"] .tajweed-course-status')).toHaveText("Пройден");
});

test("the find exercise marks misses, shows the answer and takes another ayah", async ({ page }) => {
  const lesson = await openLesson(page, "/ru/tajweed/iqlab#find");
  await expect(counter(page)).toHaveText("Шаг 6 из 6: Найдите правило в аяте");
  const find = lesson.locator('[data-step="find"]');
  const feedback = find.getByTestId("tajweed-find-feedback");
  const [missA, missB] = wordPositions(examples.iqlab!.examples[3]!, false);
  await find.locator(`button[data-word-position="${missA}"]`).click();
  await expect(feedback).toHaveText("Здесь этого правила нет — попробуйте другое слово.");
  await expect(find.locator(`button[data-word-position="${missA}"]`)).toHaveAttribute("aria-pressed", "true");
  await expect(find.getByRole("button", { name: "Показать ответ" })).toHaveCount(0);
  await find.locator(`button[data-word-position="${missB}"]`).click();
  await find.getByRole("button", { name: "Показать ответ" }).click();
  await expect(feedback).toHaveText("Вот где здесь «Икляб».");
  await expect(find.locator(".tajweed-course-word.is-lit").first()).toBeVisible();

  const next = examples.iqlab!.examples[4]!;
  await find.getByRole("button", { name: "Другой аят" }).click();
  await expect.poll(async () => (await find.locator(".tajweed-course-ayah").textContent())?.replaceAll("\u200d", ""))
    .toBe(next.words.map((word) => word.text).join(" "));
  await expect(feedback).toHaveText("");
  await find.locator(`button[data-word-position="${wordPositions(next, true)[0]}"]`).click();
  await expect(feedback).toHaveText("Верно! Здесь «Икляб».");
  await expect(find.getByRole("button", { name: "Послушать фрагмент" })).toBeVisible();
});

test("a signed-in visitor's progress is merged with the account", async ({ page }) => {
  await page.unroute("**/api/web-auth/refresh");
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({
    json: {
      token_type: "Bearer",
      access_token: "guest-access-token",
      expires_in: 900,
      access_expires_at: "2027-08-23T18:15:00Z",
      user: {
        id: "00000000-0000-7000-8000-000000000101",
        status: "guest",
        preferred_locale: "ru",
        email: null,
        deletion_requested_at: null,
        deletion_scheduled_for: null,
      },
      device: {
        id: "00000000-0000-7000-8000-000000000201",
        platform: "web",
        locale: "ru",
        app_version: "1.0.0",
        bootstrap_generation: 1,
      },
    },
  }));
  const remote = {
    status: "completed",
    step_slug: "find",
    content_version: "2026-10-22",
    updated_at: "2026-10-21T10:00:00.000Z",
  };
  const sent: unknown[] = [];
  await page.route("**/api/v1/me/tajweed/progress/tajweed", async (route) => {
    const body = route.request().postDataJSON() as { lessons: Record<string, unknown> };
    sent.push(body);
    expect(route.request().headers().authorization).toBe("Bearer guest-access-token");
    await route.fulfill({ json: { course: "tajweed", lessons: { ...body.lessons, iqlab: remote } } });
  });
  await page.goto("/ru/tajweed");
  await expect(page.getByTestId("tajweed-course-progress")).toContainText("1 из 21 уроков");
  expect(sent).toEqual([{ lessons: {} }]);
  expect((await storedProgress(page)).lessons.iqlab).toEqual(remote);

  await openLesson(page, "/ru/tajweed/izhar");
  await expect.poll(() => sent.length).toBeGreaterThan(1);
});

for (const viewport of [
  { width: 360, height: 740 },
  { width: 390, height: 844 },
  { width: 740, height: 360 },
]) {
  test(`a lesson fits a ${viewport.width}×${viewport.height} phone in Arabic`, async ({ page }) => {
    await page.setViewportSize(viewport);
    const lesson = await openLesson(page, "/ar/tajweed/madd-separated#example-1");
    await expect(counter(page)).toHaveText(/^الخطوة 3 من 6/);
    for (const step of ["example-1", "find"]) {
      if (step === "find") await page.goto("/ar/tajweed/madd-separated#find");
      const shown = lesson.locator(`[data-step="${step}"]`);
      await expect(shown).toBeVisible();
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(viewport.width);
      const box = await shown.locator(".tajweed-course-ayah").boundingBox();
      expect(box!.x).toBeGreaterThanOrEqual(0);
      expect(box!.x + box!.width).toBeLessThanOrEqual(viewport.width);
    }
    const next = lesson.getByRole("button", { name: /إنهاء الدرس|التالي/ });
    await next.scrollIntoViewIfNeeded();
    await expect(next).toBeInViewport();
  });
}
