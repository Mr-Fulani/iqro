import { expect, test, type Page } from "@playwright/test";

const progressKey = "tajweed.progress.tajweed";
const practiceKey = "tajweed.practice.tajweed";

type Task = {
  key: string;
  type: "find" | "identify" | "listen";
  target: string;
  review: boolean;
  example: { verse_key: string; words: { position: number }[]; occurrences: { parts: { position: number }[] }[] };
  focus: number;
  options?: string[];
};

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

async function passLessons(page: Page, lessons: string[]) {
  await page.addInitScript(([key, slugs]) => {
    if (window.localStorage.getItem(key as string)) return;
    const entry = { status: "completed", step_slug: "find", content_version: "2026-10-22", updated_at: "2026-10-22T10:00:00.000Z" };
    window.localStorage.setItem(key as string, JSON.stringify({
      lessons: Object.fromEntries((slugs as string[]).map((slug) => [slug, entry])),
    }));
  }, [progressKey, lessons] as const);
}

async function withAudio(page: Page, timed = true) {
  await page.route(/\/api\/v1\/recitations\/[^/]+\/ayahs\/\d+\/\d+$/, (route) => (timed
    ? route.fulfill({
      json: {
        track: { asset: { url: "https://audio.example.test/tajweed-practice.mp3" } },
        segment: {
          start_ms: 1_000,
          end_ms: 9_000,
          words: Array.from({ length: 12 }, (_, index) => [index + 1, 1_000 + index * 1_000, 2_000 + index * 1_000]),
        },
      },
    })
    : route.fulfill({ status: 404, json: { detail: "Not found." } })));
  const wav = silentWav(14);
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
}

/** Starts a session and returns the tasks the API built for it. */
async function startSession(page: Page): Promise<Task[]> {
  const practice = page.getByTestId("tajweed-practice");
  await expect(practice).toHaveAttribute("aria-busy", "false");
  const response = page.waitForResponse((item) => new URL(item.url()).pathname === "/api/v1/tajweed/courses/tajweed/practice");
  await practice.getByRole("button", { name: /Начать практику|Ещё раз/ }).click();
  const { tasks } = await (await response).json() as { tasks: Task[] };
  await expect(page.getByTestId("tajweed-practice-counter")).toContainText(`Задание 1 из ${tasks.length}`);
  return tasks;
}

const NAMES: Record<string, string> = { izhar: "Изхар", ikhafa: "Ихфа", qalaqah: "Калькаля" };

function placePositions(task: Task): number[] {
  return task.example.occurrences.flatMap((occurrence) => occurrence.parts.map((part) => part.position));
}

test.beforeEach(async ({ page }) => {
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ status: 401 }));
});

test("without a passed lesson the practice sends the learner to the course", async ({ page }) => {
  await page.goto("/ru/tajweed/practice");
  const practice = page.getByTestId("tajweed-practice");
  await expect(practice.getByText("Пройдите хотя бы один урок курса")).toBeVisible();
  await expect(practice.getByRole("link", { name: "К курсу" })).toHaveAttribute("href", "/ru/tajweed");
  await expect(practice.getByRole("button", { name: "Начать практику" })).toHaveCount(0);

  await page.goto("/ru/tajweed");
  await expect(page.getByRole("link", { name: "Открыть практику" })).toHaveAttribute("href", "/ru/tajweed/practice");
});

test("a session asks to find, to name and to recognise by ear, then counts the score", async ({ page }) => {
  await passLessons(page, ["izhar", "ikhfa", "qalqalah"]);
  await withAudio(page);
  await page.goto("/ru/tajweed/practice");
  await expect(page.getByTestId("tajweed-practice").getByRole("listitem")).toHaveText(["Изхар", "Ихфа", "Калькаля"]);
  const tasks = await startSession(page);
  expect(tasks.map((task) => task.type).slice(0, 3)).toEqual(["find", "identify", "listen"]);
  const step = page.getByTestId("tajweed-practice-task");
  const feedback = page.getByTestId("tajweed-practice-feedback");

  // Find: the ayah is plain until the answer; a word of the place is right.
  await expect(step.getByRole("heading")).toHaveText("Найдите в аяте: «Изхар»");
  await expect(step.locator(".tajweed-course-word.is-lit")).toHaveCount(0);
  await step.locator(`button[data-word-position="${placePositions(tasks[0]!)[0]}"]`).click();
  await expect(feedback).toHaveText("Верно!");
  await expect(step.locator(".tajweed-course-word.is-lit").first()).toBeVisible();
  // The first answer counts: a second tap changes nothing.
  await step.locator("button.tajweed-course-word").last().click();
  await expect(feedback).toHaveText("Верно!");

  // Which rule: a wrong option is marked and the right one shown.
  await page.keyboard.press("ArrowRight");
  await expect(page.getByTestId("tajweed-practice-counter")).toContainText("Задание 2 из");
  await expect(step.getByRole("heading")).toHaveText("Какое правило в выделенном месте?");
  await expect(step.locator(".tajweed-course-word.is-lit").first()).toBeVisible();
  await step.getByRole("button", { name: "Изхар" }).click();
  await expect(feedback).toHaveText("Неверно. Здесь «Ихфа».");
  await expect(step.getByRole("button", { name: "Изхар" })).toHaveAttribute("aria-pressed", "true");
  await expect(step.getByRole("button", { name: "Ихфа" })).toHaveClass(/is-correct/);

  // Listen: the sound comes first, the ayah after the answer; a step change stops it.
  await page.keyboard.press("ArrowRight");
  await expect(step.getByRole("heading")).toHaveText("Послушайте и определите правило");
  await expect(step.getByTestId("tajweed-practice-ayah")).toHaveCount(0);
  await step.getByRole("button", { name: "Послушать фрагмент" }).click();
  await expect(step.getByRole("button", { name: "Остановить" })).toBeVisible();
  await step.getByRole("button", { name: NAMES[tasks[2]!.target], exact: true }).click();
  await expect(feedback).toHaveText("Верно!");
  await expect(step.getByTestId("tajweed-practice-ayah")).toBeVisible();
  await page.keyboard.press("ArrowLeft");
  expect(await page.evaluate(() => [...document.querySelectorAll("audio")].every((audio) => audio.paused))).toBe(true);

  // Finishing counts the answered tasks and keeps the session until it is sent (we are on task 2).
  for (let index = 2; index < tasks.length; index += 1) {
    await page.getByRole("button", { name: /^Далее/ }).click();
  }
  await page.getByRole("button", { name: "Завершить" }).click();
  await expect(page.getByRole("status").filter({ hasText: "Верно 2 из 3" })).toBeVisible();
  const stats = page.getByTestId("tajweed-practice-stats");
  await expect(stats).toContainText("Счёт2");
  await expect(stats).toContainText("1 дн. подряд");
  await expect(stats).toContainText("Повторение1");
  const stored = await page.evaluate((key) => JSON.parse(window.localStorage.getItem(key) || "null"), practiceKey);
  expect(stored.pending).toHaveLength(1);
  expect(stored.pending[0].answers.map((answer: { key: string; correct: boolean }) => [answer.key, answer.correct]))
    .toEqual([[tasks[0]!.key, true], [tasks[1]!.key, false], [tasks[2]!.key, true]]);
  expect(stored.state.review.map((item: { key: string }) => item.key)).toEqual([tasks[1]!.key]);

  // The mistake comes back first in the next session.
  const again = await startSession(page);
  expect(again[0]).toMatchObject({ key: tasks[1]!.key, review: true });
  await expect(page.getByTestId("tajweed-practice-counter")).toContainText("Повторение");
});

test("without the reciter's timings a listening task is asked as «which rule»", async ({ page }) => {
  await passLessons(page, ["izhar", "ikhfa", "qalqalah"]);
  await withAudio(page, false);
  await page.goto("/ru/tajweed/practice");
  const tasks = await startSession(page);
  const step = page.getByTestId("tajweed-practice-task");
  await page.keyboard.press("ArrowRight");
  await page.keyboard.press("ArrowRight");
  await expect(step).toHaveAttribute("data-task", "identify");
  await expect(step.getByRole("heading")).toHaveText("Какое правило в выделенном месте?");
  await step.getByRole("button", { name: "Изхар", exact: true }).click();
  for (let index = 3; index < tasks.length; index += 1) await page.getByRole("button", { name: /^Далее/ }).click();
  await page.getByRole("button", { name: "Завершить" }).click();
  const stored = await page.evaluate((key) => JSON.parse(window.localStorage.getItem(key) || "null"), practiceKey);
  expect(stored.pending[0].answers[0].key).toBe(tasks[2]!.key.replace(/^listen~/, "identify~"));
});

test("a signed-in visitor's sessions are sent and the account's state is kept", async ({ page }) => {
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
      device: { id: "00000000-0000-7000-8000-000000000201", platform: "web", locale: "ru", app_version: "1.0.0", bootstrap_generation: 1 },
    },
  }));
  const account = {
    course: "tajweed",
    sessions: 5,
    answers: 40,
    correct: 31,
    score: 31,
    streak: { current: 3, best: 4, last_date: new Date().toISOString().slice(0, 10) },
    review: [],
  };
  const sent: unknown[] = [];
  await page.route("**/api/v1/me/tajweed/practice/tajweed", (route) => route.fulfill({ json: account }));
  await page.route("**/api/v1/me/tajweed/practice-sessions", async (route) => {
    sent.push(route.request().postDataJSON());
    expect(route.request().headers().authorization).toBe("Bearer guest-access-token");
    await route.fulfill({ status: 201, json: { ...account, sessions: 6, answers: 41, correct: 32, score: 32 } });
  });
  await passLessons(page, ["izhar"]);
  await withAudio(page);
  await page.goto("/ru/tajweed/practice");
  await expect(page.getByTestId("tajweed-practice-stats")).toContainText("Счёт31");
  await expect(page.getByTestId("tajweed-practice-stats")).toContainText("3 дн. подряд");

  const tasks = await startSession(page);
  expect(tasks.every((task) => task.type === "find")).toBe(true);
  await page.getByTestId("tajweed-practice-task")
    .locator(`button[data-word-position="${placePositions(tasks[0]!)[0]}"]`).click();
  for (let index = 1; index < tasks.length; index += 1) await page.getByRole("button", { name: /^Далее/ }).click();
  await page.getByRole("button", { name: "Завершить" }).click();
  await expect.poll(() => sent.length).toBe(1);
  expect(sent[0]).toMatchObject({ course: "tajweed", answers: [{ key: tasks[0]!.key, correct: true }] });
  await expect(page.getByTestId("tajweed-practice-stats")).toContainText("Счёт32");
  await expect.poll(() => page.evaluate((key) => JSON.parse(window.localStorage.getItem(key)!).pending.length, practiceKey)).toBe(0);
});

for (const viewport of [{ width: 360, height: 740 }, { width: 740, height: 360 }]) {
  test(`a practice task fits a ${viewport.width}×${viewport.height} phone in Arabic`, async ({ page }) => {
    await page.setViewportSize(viewport);
    await passLessons(page, ["izhar", "ikhfa", "qalqalah"]);
    await withAudio(page);
    await page.goto("/ar/tajweed/practice");
    const practice = page.getByTestId("tajweed-practice");
    await expect(practice).toHaveAttribute("aria-busy", "false");
    await practice.getByRole("button", { name: "ابدأ التدريب" }).click();
    for (const type of ["find", "identify"]) {
      await expect(page.getByTestId("tajweed-practice-task")).toHaveAttribute("data-task", type);
      expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(viewport.width);
      const box = await page.getByTestId("tajweed-practice-ayah").boundingBox();
      expect(box!.x).toBeGreaterThanOrEqual(0);
      expect(box!.x + box!.width).toBeLessThanOrEqual(viewport.width);
      await page.keyboard.press("ArrowLeft");
    }
    const next = page.getByRole("button", { name: /التالي/ });
    await next.scrollIntoViewIfNeeded();
    await expect(next).toBeInViewport();
  });
}
