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
      await expect(page.getByTestId("language-switcher")).toBeHidden();
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
  await page.getByRole("toolbar").getByRole("button", { name: "Настройки чтения", exact: true }).click();
  await page.getByRole("button", { name: "📜 Текст", exact: true }).click();
  await expect(navigation).toBeVisible();
  await expect(navigation.locator('[aria-current="page"]')).toHaveAttribute("href", "/ru/quran");

  await navigation.getByRole("link", { name: "Главная", exact: true }).click();
  await page.getByTestId("home-hero").getByRole("link", { name: "📖 Читать Коран" }).click();
  await expect(page).toHaveURL("/ru/quran");
  await expect(page.locator(".quran-page-layout").filter({ visible: true })).toHaveClass(/is-mushaf-mode/);
  await page.getByRole("toolbar").getByRole("button", { name: "Настройки чтения", exact: true }).click();
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

  await more.click();
  const language = page.getByTestId("mobile-language-switcher");
  await expect(language).toBeVisible();
  await expect(language).toHaveValue("ru");
  await language.selectOption("ar");
  await expect(page).toHaveURL("/ar/dua");
  await expect(page.locator("html")).toHaveAttribute("dir", "rtl");
  await page.reload();
  await navigation.locator("summary").click();
  await expect(language).toHaveValue("ar");
  await expect(navigation.locator('.mobile-more-links [aria-current="page"]')).toHaveAttribute("href", "/ar/dua");
  const languageBox = await language.boundingBox();
  expect(languageBox!.height).toBeGreaterThanOrEqual(44);
  expect(languageBox!.width).toBeLessThanOrEqual(105);
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(390);
});

test("reader settings stay outside immersive mode and preserve mounted controls", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/ru/quran");
  const reader = page.locator(".quran-page-layout").filter({ visible: true });
  const settings = reader.locator(".quran-reader-settings");
  const fields = ["#quran-edition", "#mushaf-variant", "#surah-navigation", "#ayah-navigation", "#mushaf-page-jump", "#translation-enabled"];
  for (const field of fields) await expect(settings.locator(field)).toBeHidden();
  await page.getByRole("toolbar").getByRole("button", { name: "Настройки чтения", exact: true }).click();
  await expect(reader).not.toHaveClass(/is-reader-immersive/);
  await expect(page.locator(".mobile-navigation")).toBeVisible();
  await expect(page.getByRole("dialog")).toHaveCount(0);
  for (const field of fields) await expect(settings.locator(field)).toBeVisible();
  await settings.locator("#mushaf-variant").evaluate((element) => element.setAttribute("data-mounted-check", "same"));
  await reader.locator(".reader-settings-navigation").getByRole("button", { name: "Аудио", exact: true }).click();
  await expect(reader.locator(".reader-panel-audio")).toBeFocused();
  await expect(reader.locator(".reader-panel-audio")).toBeInViewport();
  await page.getByRole("button", { name: "Открыть читалку", exact: true }).click();
  await expect(reader).toHaveClass(/is-reader-immersive/);
  await expect(page.locator(".mobile-navigation")).toBeHidden();
  await expect(settings.locator("#mushaf-variant")).toHaveAttribute("data-mounted-check", "same");
  await page.getByRole("toolbar").getByRole("button", { name: "Настройки чтения", exact: true }).click();
  for (const size of [{ width: 844, height: 390 }, { width: 390, height: 844 }, { width: 1280, height: 900 }]) {
    await page.setViewportSize(size);
    for (const field of fields) await expect(settings.locator(field)).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBe(size.width);
  }
  await page.setViewportSize({ width: 844, height: 390 });
  await expect(settings).toHaveJSProperty("open", false);
  await settings.locator("summary").click();
  await expect(settings).toHaveJSProperty("open", true);
  await settings.locator("summary").click();
  await expect(settings).toHaveJSProperty("open", false);
  await page.setViewportSize({ width: 1280, height: 900 });
  await expect(settings).toHaveJSProperty("open", true);
  for (const field of fields) await expect(settings.locator(field)).toBeVisible();
  await expect(reader.locator(".mushaf-page-navigation")).toBeVisible();
  await expect(settings.locator("summary")).toBeHidden();
  await expect(page.locator(".mobile-navigation")).toBeHidden();
  await expect(page.locator(".app-menu")).toBeVisible();
});

test("leaving the reader restores usable bottom navigation without changing Mushaf mode", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/ru/quran");
  const reader = page.locator(".quran-page-layout").filter({ visible: true });
  const navigation = page.locator(".mobile-navigation");
  for (const exit of ["button", "escape", "settings"]) {
    await expect(navigation).toBeHidden();
    if (exit === "escape") {
      await reader.locator(".mushaf-page-container").focus();
      await page.keyboard.press("Escape");
    } else {
      await page.getByRole("toolbar").getByRole("button", {
        name: exit === "button" ? "Выйти из читалки" : "Настройки чтения", exact: true,
      }).click();
    }
    await expect(reader).toHaveClass(/is-mushaf-mode/);
    await expect(reader).not.toHaveClass(/is-reader-immersive/);
    await expect(navigation).toBeVisible();
    const box = (await navigation.boundingBox())!;
    expect(box.y + box.height).toBe(844);
    expect(box.height).toBeGreaterThanOrEqual(72);
    expect(await page.locator(".app-container").evaluate((element) => parseFloat(getComputedStyle(element).paddingBottom))).toBeGreaterThanOrEqual(88);
    await page.getByRole("button", { name: "Открыть читалку", exact: true }).click();
  }
  await page.setViewportSize({ width: 667, height: 375 });
  await page.getByRole("toolbar").getByRole("button", { name: "Выйти из читалки", exact: true }).click();
  await expect(navigation).toBeVisible();
  await navigation.locator(".mobile-more > summary").click();
  await expect(page.getByTestId("mobile-language-switcher")).toBeVisible();
  await navigation.getByRole("link", { name: "Главная", exact: true }).click();
  await expect(page).toHaveURL("/ru");
  await expect(navigation).toBeVisible();
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
    await expect(page.getByTestId("language-switcher")).toBeVisible();
    await expect(page.getByTestId("mobile-language-switcher")).toBeHidden();
    expect(await page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue("--bg").trim())).toBe("#f8fafc");
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(width);
  }
});
