import { expect, type Locator, test, type Page } from "@playwright/test";

// The pose illustrations are stills of the schematic 3D scene, which takes their place once
// it can run (docs/salah/salah-3d.md).

test.beforeEach(async ({ page }) => {
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ status: 401 }));
  await page.route(/\.(mp3|m4a)(\?|$)/, (route) => route.fulfill({ status: 404 }));
});

async function openLesson(page: Page, path: string) {
  await page.goto(path);
  await expect(page.getByTestId("salah-player")).toHaveAttribute("aria-busy", "false");
}

/** Notes whether any script the page has fetched so far carries three.js. */
function watchThree(page: Page) {
  const seen = { three: false };
  page.on("response", async (response) => {
    if (response.request().resourceType() !== "script") return;
    const body = await response.text().catch(() => "");
    if (body.includes("THREE.WebGLRenderer")) seen.three = true;
  });
  return seen;
}

const currentStep = (page: Page) => page.locator(".salah-step:not([hidden])");
// The first scene of a run waits for the three.js chunk (compiled on demand by `next dev`).
const SCENE_TIMEOUT = { timeout: 30_000 };
// Any first action on the page starts the scene.
const act = (page: Page) => page.mouse.move(5, 5);
// A pose plays once: the takbir in about 2.5 s, the tashahhud in about 12 s.
const POSE_TIMEOUT = { timeout: 20_000 };
const replayButton = (step: Locator) => step.getByRole("button", { name: "Повторить", exact: true });

/** Whether the scene draws anything new between two looks a moment apart. */
async function moving(canvas: Locator) {
  const before = await canvas.screenshot();
  await canvas.page().waitForTimeout(400);
  return !before.equals(await canvas.screenshot());
}

function setTabHidden(page: Page, hidden: boolean) {
  return page.evaluate((value) => {
    Object.defineProperty(document, "hidden", { configurable: true, get: () => value });
    document.dispatchEvent(new Event("visibilitychange"));
  }, hidden);
}

test("the scene replaces the still once the visitor acts and follows the steps", async ({ page }) => {
  const loaded = watchThree(page);
  await openLesson(page, "/ru/salah/fajr");
  const step = currentStep(page);
  await expect(step.locator("figcaption")).toHaveText("Схематичная 3D-иллюстрация");
  await expect(step.locator("img")).toHaveAttribute("alt", "Стоящий мужчина поднимает руки до плеч");
  await expect(page.getByRole("group", { name: "Иллюстрация шага" })).toHaveCount(0);
  await page.waitForLoadState("networkidle");
  // The page loads with the still only.
  expect(loaded.three).toBe(false);
  await expect(page.locator("canvas")).toHaveCount(0);

  await act(page);
  const canvas = step.locator("[data-testid='salah-3d'] canvas");
  await expect(canvas).toBeVisible(SCENE_TIMEOUT);
  expect(loaded.three).toBe(true);
  // The still underneath keeps describing the step.
  await expect(step.locator("img")).toHaveAttribute("alt", "Стоящий мужчина поднимает руки до плеч");
  await expect(canvas).toHaveAttribute("aria-hidden", "true");

  // One canvas moves along with the step.
  await page.getByRole("button", { name: "Далее" }).click();
  await expect(step).toHaveAttribute("data-step", "fajr.r1.fatiha");
  await expect(step.locator("[data-testid='salah-3d'] canvas")).toBeVisible();
  await expect(page.locator("canvas")).toHaveCount(1);
});

test("a pose plays once, holds its last frame and plays again on «Повторить»", async ({ page }) => {
  await openLesson(page, "/ru/salah/fajr");
  await act(page);
  const step = currentStep(page);
  const canvas = step.locator("[data-testid='salah-3d'] canvas");
  await expect(canvas).toHaveAttribute("data-running", "true", SCENE_TIMEOUT);
  await expect(replayButton(step)).toHaveCount(0);

  await expect(replayButton(step)).toBeVisible(POSE_TIMEOUT);
  await expect(replayButton(step)).toContainText("↻");
  await expect(canvas).toHaveAttribute("data-running", "false");
  await expect(step.getByRole("button", { name: "Воспроизвести движение" })).toBeVisible();
  // No loop: the figure holds still.
  await expect.poll(() => moving(canvas), POSE_TIMEOUT).toBe(false);

  await replayButton(step).click();
  await expect(replayButton(step)).toHaveCount(0);
  await expect(canvas).toHaveAttribute("data-running", "true");
  expect(await moving(canvas)).toBe(true);
  await expect(replayButton(step)).toBeVisible(POSE_TIMEOUT);
  await expect.poll(() => moving(canvas), POSE_TIMEOUT).toBe(false);

  // Play after the end plays the pose again too.
  await step.getByRole("button", { name: "Воспроизвести движение" }).click();
  await expect(canvas).toHaveAttribute("data-running", "true");
  await expect(replayButton(step)).toBeVisible(POSE_TIMEOUT);

  // The next step plays its own pose once.
  await page.getByRole("button", { name: "Далее" }).click();
  await expect(step).toHaveAttribute("data-step", "fajr.r1.fatiha");
  await expect(page.locator("canvas")).toHaveAttribute("data-running", "true");
  await expect(replayButton(step)).toHaveCount(0);
  await expect(replayButton(step)).toBeVisible(POSE_TIMEOUT);
  await expect(page.locator("canvas")).toHaveAttribute("data-running", "false");
});

test("pause, speed and a hidden tab hold the movement", async ({ page }) => {
  await openLesson(page, "/ru/salah/fajr#fajr.r2.tashahhud");
  await act(page);
  const step = currentStep(page);
  const canvas = step.locator("[data-testid='salah-3d'] canvas");
  await expect(canvas).toHaveAttribute("data-running", "true", SCENE_TIMEOUT);

  await step.getByRole("button", { name: "Остановить движение" }).click();
  await expect(canvas).toHaveAttribute("data-running", "false");
  await expect.poll(() => moving(canvas)).toBe(false);
  // Paused is not ended.
  await expect(replayButton(step)).toHaveCount(0);
  await step.getByRole("button", { name: "Воспроизвести движение" }).click();
  await expect(canvas).toHaveAttribute("data-running", "true");
  await step.getByRole("button", { name: "Скорость движения: 1×" }).click();
  await expect(step.getByRole("button", { name: "Скорость движения: 0,75×" })).toHaveText("0,75×");

  await setTabHidden(page, true);
  await expect(canvas).toHaveAttribute("data-running", "false");
  await setTabHidden(page, false);
  await expect(canvas).toHaveAttribute("data-running", "true");
});

test("without WebGL the still stays and three.js is never fetched", async ({ page }) => {
  await page.addInitScript(() => {
    const getContext = HTMLCanvasElement.prototype.getContext;
    HTMLCanvasElement.prototype.getContext = function (this: HTMLCanvasElement, type: string, ...rest: unknown[]) {
      if (type.startsWith("webgl")) return null;
      return getContext.call(this, type as "2d", ...(rest as []));
    } as typeof getContext;
  });
  const loaded = watchThree(page);
  await openLesson(page, "/ru/salah/fajr");
  await act(page);
  await page.getByRole("button", { name: "Далее" }).click();
  const step = currentStep(page);
  await expect(step).toHaveAttribute("data-step", "fajr.r1.fatiha");
  await expect(step.locator("img")).toBeVisible();
  await expect(step.locator("figcaption")).toHaveText("Схематичная 3D-иллюстрация");
  await expect(page.locator("canvas")).toHaveCount(0);
  await page.waitForLoadState("networkidle");
  expect(loaded.three).toBe(false);
});

test("a failed scene download leaves the still", async ({ page }) => {
  await openLesson(page, "/ru/salah/fajr");
  await page.waitForLoadState("networkidle");
  await page.route(/\.js(\?|$)/, (route) => route.abort());
  await act(page);
  const step = currentStep(page);
  await expect(step.locator("img")).toBeVisible();
  await expect(step.getByRole("button", { name: "Остановить движение" })).toHaveCount(0);
  await expect(replayButton(step)).toHaveCount(0);
  await expect(page.locator("canvas")).toHaveCount(0);
});

test("reduced motion keeps the still, and a picture without a scene stays a picture", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  const loaded = watchThree(page);
  await openLesson(page, "/ru/salah/fajr");
  await act(page);
  await expect(currentStep(page).locator("figcaption")).toHaveText("Схематичная 3D-иллюстрация");
  await expect(page.locator("canvas")).toHaveCount(0);
  await expect(replayButton(currentStep(page))).toHaveCount(0);
  await page.waitForLoadState("networkidle");
  expect(loaded.three).toBe(false);

  await page.emulateMedia({ reducedMotion: "no-preference" });
  await openLesson(page, "/ru/salah/wudu#wudu.face");
  await act(page);
  await expect(currentStep(page)).toHaveAttribute("data-step", "wudu.face");
  await expect(currentStep(page).locator("img")).toBeVisible();
  await expect(currentStep(page).locator("figcaption")).toHaveCount(0);
  await expect(page.locator("canvas")).toHaveCount(0);
});

test("the Arabic page labels the scene and its tools in Arabic", async ({ page }) => {
  await openLesson(page, "/ar/salah/fajr");
  const step = currentStep(page);
  await expect(step.locator("figcaption")).toContainText("رسم توضيحي تخطيطي ثلاثي الأبعاد");
  await act(page);
  await expect(step.getByRole("button", { name: "إيقاف الحركة مؤقتًا" })).toBeVisible(SCENE_TIMEOUT);
  await expect(step.getByRole("button", { name: "إعادة زاوية العرض" })).toBeVisible();
  const replay = step.getByRole("button", { name: "إعادة الحركة" });
  await expect(replay).toBeVisible(POSE_TIMEOUT);
  // At the scene's inline end: on the left in Arabic.
  const frame = (await step.locator(".salah-step-frame").boundingBox())!;
  const button = (await replay.boundingBox())!;
  expect(button.x + button.width / 2).toBeLessThan(frame.x + frame.width / 2);
});
