import { expect, test } from "@playwright/test";

// The next page takes a while to arrive, as on a slow connection.
test.beforeEach(async ({ page }) => {
  await page.route(
    (url) => url.searchParams.has("_rsc"),
    async (route) => {
      await new Promise((resolve) => setTimeout(resolve, 1500));
      await route.continue();
    },
  );
});

// The delay above, plus the first compilation of the section on a development server.
const ARRIVAL_TIMEOUT = 20_000;

for (const view of [
  { name: "a desktop", locale: "ru", width: 1280, height: 900, menu: "nav.app-menu" },
  { name: "a phone in Arabic", locale: "ar", width: 390, height: 844, menu: "nav.mobile-navigation" },
]) {
  test(`a pressed menu link shows the progress bar until the section opens on ${view.name}`, async ({ page }) => {
    await page.setViewportSize({ width: view.width, height: view.height });
    await page.goto(`/${view.locale}`, { waitUntil: "load" });
    await page.waitForLoadState("networkidle").catch(() => undefined);
    const bar = page.getByTestId("navigation-progress");
    await expect(bar).toHaveCount(0);
    const pageHeight = await page.evaluate(() => document.documentElement.scrollHeight);

    await page.locator(`${view.menu} a[href="/${view.locale}/audio"]`).click();
    await expect(bar).toBeVisible();
    const box = (await bar.boundingBox())!;
    expect(box.y).toBe(0);
    expect(box.height).toBe(3);
    // It grows from the edge where reading starts: the right one in Arabic.
    if (view.locale === "ar") expect(box.x + box.width).toBeCloseTo(view.width, 0);
    else expect(box.x).toBe(0);
    // Drawn over the page: nothing under it moves.
    expect(await page.evaluate(() => document.documentElement.scrollHeight)).toBe(pageHeight);
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(view.width);

    await expect(page).toHaveURL(new RegExp(`/${view.locale}/audio$`), { timeout: ARRIVAL_TIMEOUT });
    await expect(bar).toHaveCount(0);
  });
}

test("with reduced motion the bar appears whole instead of growing", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto("/ru", { waitUntil: "load" });
  await page.waitForLoadState("networkidle").catch(() => undefined);
  await page.locator('nav.app-menu a[href="/ru/audio"]').click();
  const bar = page.getByTestId("navigation-progress");
  await expect(bar).toBeVisible();
  expect((await bar.boundingBox())!.width).toBe(1280);
  await expect(page).toHaveURL(/\/ru\/audio$/, { timeout: ARRIVAL_TIMEOUT });
  await expect(bar).toHaveCount(0);
});

test("a link to the open page leaves no bar behind", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto("/ru/audio", { waitUntil: "load" });
  await page.waitForLoadState("networkidle").catch(() => undefined);
  await page.locator('nav.app-menu a[href="/ru/audio"]').click();
  await page.waitForTimeout(500);
  await expect(page.getByTestId("navigation-progress")).toHaveCount(0);
});
