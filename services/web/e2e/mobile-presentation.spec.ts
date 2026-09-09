import { expect, test } from "@playwright/test";

test.beforeEach(async ({ page }) => {
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ status: 401 }));
});

for (const viewport of [
  { width: 320, locale: "ru", direction: "ltr" },
  { width: 390, locale: "ar", direction: "rtl" },
  { width: 430, locale: "tr", direction: "ltr" },
  { width: 768, locale: "en", direction: "ltr" },
]) {
  test(`mobile screens fit ${viewport.width}px in ${viewport.locale}`, async ({ page }) => {
    test.setTimeout(90_000);
    await page.setViewportSize({ width: viewport.width, height: 844 });
    for (const route of ["", "/quran", "/audio", "/planner", "/memorization", "/prayer", "/calendar", "/dua", "/profile", "/login"]) {
      await page.goto(`/${viewport.locale}${route}`);
      await expect(page.locator("html")).toHaveAttribute("dir", viewport.direction);
      await expect(page.locator("main")).toBeVisible();
      const navigation = page.locator(".mobile-navigation");
      await expect(page.locator(".app-menu")).toBeHidden();
      await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth))
        .toBeLessThanOrEqual(viewport.width);
      if (route === "/quran") {
        await expect(page.locator(".quran-page-layout").filter({ visible: true })).toHaveClass(/is-mushaf-mode/);
        await expect(page.locator(".mushaf-reader-surface").filter({ visible: true })).toBeVisible();
        await expect(navigation).toBeHidden();
        continue;
      }
      await expect(navigation).toBeVisible();
      const bounds = await navigation.boundingBox();
      expect(bounds!.y + bounds!.height).toBeCloseTo(844, 0);
      for (const tab of await navigation.locator(".mobile-tab").all()) {
        const box = await tab.boundingBox();
        expect(box!.width).toBeGreaterThanOrEqual(44);
        expect(box!.height).toBeGreaterThanOrEqual(44);
        expect(box!.x).toBeGreaterThanOrEqual(0);
        expect(box!.x + box!.width).toBeLessThanOrEqual(viewport.width);
      }
    }
  });
}

test("five mobile tabs and More preserve localized destinations and keyboard access", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/ru");
  const navigation = page.locator(".mobile-navigation");
  await expect(navigation.locator(":scope > a")).toHaveText(["Главная", "Коран", "План", "Аудио"]);
  await expect(navigation.locator('[aria-current="page"]')).toHaveAttribute("href", "/ru");

  await navigation.getByRole("link", { name: "Коран", exact: true }).click();
  await expect(page).toHaveURL("/ru/quran");
  await expect(page.locator(".quran-page-layout").filter({ visible: true })).toHaveClass(/is-mushaf-mode/);
  await expect(navigation).toBeHidden();
  await page.getByRole("button", { name: "📜 Текст", exact: true }).click();
  await expect(navigation).toBeVisible();
  await expect(navigation.locator('[aria-current="page"]')).toHaveAttribute("href", "/ru/quran");

  await navigation.getByRole("link", { name: "Главная", exact: true }).click();
  await page.getByTestId("home-hero").getByRole("link", { name: "📖 Читать Коран" }).click();
  await expect(page).toHaveURL("/ru/quran");
  await expect(page.locator(".quran-page-layout").filter({ visible: true })).toHaveClass(/is-mushaf-mode/);
  await page.getByRole("button", { name: "📜 Текст", exact: true }).click();

  const more = navigation.locator("summary");
  await more.focus();
  await page.keyboard.press("Enter");
  await expect(navigation.locator(".mobile-more-panel")).toBeVisible();
  await expect(navigation.locator(".mobile-more-links a")).toHaveCount(5);
  await page.keyboard.press("Escape");
  await expect(navigation.locator(".mobile-more-panel")).toBeHidden();
  await expect(more).toBeFocused();

  await more.click();
  await navigation.getByRole("link", { name: "Ду’а", exact: true }).click();
  await expect(page).toHaveURL("/ru/dua");
  await expect(navigation.locator(".mobile-more-panel")).toBeHidden();
  await expect(more).toHaveClass(/is-active/);

  await page.getByTestId("language-switcher").selectOption("ar");
  await expect(page).toHaveURL("/ar/dua");
  await navigation.locator("summary").click();
  await expect(navigation.locator('.mobile-more-links [aria-current="page"]')).toHaveAttribute("href", "/ar/dua");
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(390);
});

test("reader disclosure keeps controls mounted and restores the desktop presentation", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/ru/quran");
  const settings = page.locator(".quran-reader-settings");
  const translation = page.locator("#translation-enabled");
  await expect(translation).toBeHidden();
  await settings.locator("summary").click();
  await expect(translation).toBeVisible();
  await translation.evaluate((input) => input.setAttribute("data-mounted-check", "same-control"));
  await settings.locator("summary").click();
  await expect(translation).toBeHidden();
  await settings.locator("summary").click();
  await expect(translation).toHaveAttribute("data-mounted-check", "same-control");
  await page.setViewportSize({ width: 1280, height: 900 });
  await expect(translation).toBeVisible();
  await expect(settings.locator("summary")).toBeHidden();
  await expect(page.locator(".mobile-navigation")).toBeHidden();
  await expect(page.locator(".app-menu")).toBeVisible();
});

test("mobile More fits landscape and the compact breakpoint does not alter desktop tokens", async ({ page }) => {
  await page.setViewportSize({ width: 667, height: 375 });
  await page.goto("/ru");
  await page.locator(".mobile-more > summary").click();
  const panel = page.locator(".mobile-more-panel");
  const box = await panel.boundingBox();
  expect(box!.y).toBeGreaterThanOrEqual(15);
  expect(box!.y + box!.height).toBeLessThanOrEqual((await page.locator(".mobile-navigation").boundingBox())!.y + 1);
  await panel.getByRole("link", { name: "Кабинет", exact: true }).click();
  await expect(page).toHaveURL("/ru/profile");
  for (const width of [769, 1024, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    await expect(page.locator(".mobile-navigation")).toBeHidden();
    await expect(page.locator(".app-menu")).toBeVisible();
    expect(await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue("--bg").trim())).toBe("#f8fafc");
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
  }
});
