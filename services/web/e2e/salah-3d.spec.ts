import { expect, test, type Page } from "@playwright/test";

// The schematic 3D scene is an addition to the course pictures (docs/salah/salah-3d.md).

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

test("3D loads on demand, follows the steps and pauses with the tab", async ({ page }) => {
  const loaded = watchThree(page);
  await openLesson(page, "/ru/salah/fajr");
  const step = currentStep(page);
  const visual = step.getByRole("group", { name: "Иллюстрация шага" });
  await expect(visual.getByRole("button", { name: "Картинка" })).toHaveAttribute("aria-pressed", "true");
  await page.waitForLoadState("networkidle");
  expect(loaded.three).toBe(false);

  await visual.getByRole("button", { name: "3D" }).click();
  await expect(visual.getByRole("button", { name: "3D" })).toHaveAttribute("aria-pressed", "true");
  const canvas = step.locator("[data-testid='salah-3d'] canvas");
  await expect(canvas).toBeVisible();
  await expect(step.locator("figcaption")).toContainText("Схематичная 3D-иллюстрация");
  const pause = step.getByRole("button", { name: "Остановить движение" });
  await expect(pause).toBeVisible();
  await expect(canvas).toHaveAttribute("data-running", "true");
  expect(loaded.three).toBe(true);
  // The course picture stays underneath and keeps describing the step.
  await expect(step.locator("img")).toHaveAttribute("alt", "Стоящий мужчина поднимает руки до плеч");
  await expect(canvas).toHaveAttribute("aria-hidden", "true");

  await pause.click();
  await expect(canvas).toHaveAttribute("data-running", "false");
  await step.getByRole("button", { name: "Воспроизвести движение" }).click();
  await expect(canvas).toHaveAttribute("data-running", "true");
  await step.getByRole("button", { name: "Скорость движения: 1×" }).click();
  await expect(step.getByRole("button", { name: "Скорость движения: 0,75×" })).toHaveText("0,75×");

  // The choice lasts for the lesson; one canvas moves along with the step.
  await page.getByRole("button", { name: "Далее" }).click();
  await expect(step).toHaveAttribute("data-step", "fajr.r1.fatiha");
  await expect(step.locator("[data-testid='salah-3d'] canvas")).toBeVisible();
  await expect(page.locator("canvas")).toHaveCount(1);

  await page.evaluate(() => {
    Object.defineProperty(document, "hidden", { configurable: true, get: () => true });
    document.dispatchEvent(new Event("visibilitychange"));
  });
  await expect(page.locator("canvas")).toHaveAttribute("data-running", "false");
  await page.evaluate(() => {
    Object.defineProperty(document, "hidden", { configurable: true, get: () => false });
    document.dispatchEvent(new Event("visibilitychange"));
  });
  await expect(page.locator("canvas")).toHaveAttribute("data-running", "true");

  await step.getByRole("button", { name: "Картинка" }).click();
  await expect(page.locator("canvas")).toHaveCount(0);
  await expect(step.locator("img")).toBeVisible();
});

test("without WebGL the picture stays and 3D is no longer offered", async ({ page }) => {
  await page.addInitScript(() => {
    const getContext = HTMLCanvasElement.prototype.getContext;
    HTMLCanvasElement.prototype.getContext = function (this: HTMLCanvasElement, type: string, ...rest: unknown[]) {
      if (type.startsWith("webgl")) return null;
      return getContext.call(this, type as "2d", ...(rest as []));
    } as typeof getContext;
  });
  const loaded = watchThree(page);
  await openLesson(page, "/ru/salah/fajr");
  const step = currentStep(page);
  await step.getByRole("button", { name: "3D" }).click();
  await expect(step.getByRole("status")).toHaveText("3D-иллюстрация недоступна на этом устройстве — показана картинка.");
  await expect(step.getByRole("group", { name: "Иллюстрация шага" })).toHaveCount(0);
  await expect(step.locator("img")).toBeVisible();
  await expect(page.locator("canvas")).toHaveCount(0);
  await page.getByRole("button", { name: "Далее" }).click();
  await expect(currentStep(page).getByRole("group", { name: "Иллюстрация шага" })).toHaveCount(0);
  await expect(currentStep(page).getByRole("status")).toHaveCount(0);
  expect(loaded.three).toBe(false);
});

test("a failed 3D download brings the picture back", async ({ page }) => {
  await openLesson(page, "/ru/salah/fajr");
  await page.waitForLoadState("networkidle");
  await page.route(/\.js(\?|$)/, (route) => route.abort());
  const step = currentStep(page);
  await step.getByRole("button", { name: "3D" }).click();
  await expect(step.getByRole("status")).toHaveText("3D-иллюстрация недоступна на этом устройстве — показана картинка.");
  await expect(step.locator("img")).toBeVisible();
  await expect(page.locator("canvas")).toHaveCount(0);
});

test("reduced motion and steps without a matching pose keep only the picture", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await openLesson(page, "/ru/salah/fajr");
  await expect(currentStep(page).locator("img")).toBeVisible();
  await expect(page.getByRole("group", { name: "Иллюстрация шага" })).toHaveCount(0);

  await page.emulateMedia({ reducedMotion: "no-preference" });
  await openLesson(page, "/ru/salah/wudu#wudu.face");
  await expect(currentStep(page)).toHaveAttribute("data-step", "wudu.face");
  await expect(currentStep(page).locator("img")).toBeVisible();
  await expect(page.getByRole("group", { name: "Иллюстрация шага" })).toHaveCount(0);
});

test("the Arabic page labels 3D in Arabic and reads the switch right to left", async ({ page }) => {
  await openLesson(page, "/ar/salah/fajr");
  const step = currentStep(page);
  const visual = step.getByRole("group", { name: "رسم الخطوة" });
  const picture = (await visual.getByRole("button", { name: "صورة" }).boundingBox())!;
  const threeD = visual.getByRole("button", { name: "ثلاثي الأبعاد" });
  expect((await threeD.boundingBox())!.x).toBeLessThan(picture.x);
  // The scene is not mirrored, so the switch stays in its empty top-right corner.
  const frame = (await step.locator(".salah-step-frame").boundingBox())!;
  const switcher = (await visual.boundingBox())!;
  expect(frame.x + frame.width - (switcher.x + switcher.width)).toBeLessThan(switcher.x - frame.x);
  await threeD.click();
  await expect(step.locator("figcaption")).toContainText("رسم توضيحي تخطيطي ثلاثي الأبعاد");
  await expect(step.getByRole("button", { name: "إيقاف الحركة مؤقتًا" })).toBeVisible();
});
