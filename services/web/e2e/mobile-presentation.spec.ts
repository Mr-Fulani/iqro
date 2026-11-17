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
    for (const route of ["", "/quran", "/audio", "/planner", "/memorization", "/prayer", "/calendar", "/dua", "/profile", "/login", "/more", "/settings", "/surahs"]) {
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
  await expect(navigation.locator(":scope > a")).toHaveText(["Главная", "Коран", "План", "Аудио", "Ещё"]);
  await expect(navigation.locator('[aria-current="page"]')).toHaveAttribute("href", "/ru");

  // The Quran tab is the list of surahs, as in the app; a surah opens the reader.
  await navigation.getByRole("link", { name: "Коран", exact: true }).click();
  await expect(page).toHaveURL("/ru/surahs");
  await expect(navigation.locator('[aria-current="page"]')).toHaveAttribute("href", "/ru/surahs");
  await expect(page.getByTestId("surahs-continue")).toHaveAttribute("href", "/ru/quran?surah=1&ayah=1");
  await page.getByTestId("surahs-list").getByRole("link", { name: /Аль-Фатиха/ }).click();
  await expect(page).toHaveURL("/ru/quran?surah=1&ayah=1");
  await expect(page.locator(".quran-page-layout").filter({ visible: true })).toHaveClass(/is-mushaf-mode/);
  await expect(navigation).toBeHidden();
  await page.getByRole("toolbar").getByRole("button", { name: "Настройки чтения", exact: true }).click();
  await page.getByRole("button", { name: "📜 Текст", exact: true }).click();
  await expect(navigation).toBeVisible();
  // The reader keeps the Quran tab lit and has a way back to the list.
  await expect(navigation.locator('[aria-current="page"]')).toHaveAttribute("href", "/ru/surahs");
  await expect(page.getByTestId("header-back")).toBeVisible();

  // «Text» chosen on the tab opens the reader in the text mode, and is remembered.
  await page.goto("/ru/surahs");
  await page.getByTestId("surahs-view-text").click();
  await page.reload();
  await expect(page.getByTestId("surahs-view-text")).toHaveAttribute("aria-pressed", "true");
  await page.getByTestId("surahs-list").getByRole("link", { name: /Аль-Фатиха/ }).click();
  await expect(page).toHaveURL("/ru/quran?surah=1&ayah=1&view=text");
  await expect(page.locator(".quran-page-layout").filter({ visible: true })).not.toHaveClass(/is-mushaf-mode/);
  await expect(navigation).toBeVisible();
  await page.goto("/ru/surahs");
  await page.getByTestId("surahs-view-mushaf").click();

  await navigation.getByRole("link", { name: "Главная", exact: true }).click();
  await page.getByTestId("home-reading-read").click();
  await expect(page).toHaveURL("/ru/quran");
  await expect(page.locator(".quran-page-layout").filter({ visible: true })).toHaveClass(/is-mushaf-mode/);
  await page.getByRole("toolbar").getByRole("button", { name: "Настройки чтения", exact: true }).click();
  await page.getByRole("button", { name: "📜 Текст", exact: true }).click();

  // More is a screen of its own, opened from the fifth tab with the keyboard too.
  const more = navigation.getByTestId("mobile-more-tab");
  await more.focus();
  await page.keyboard.press("Enter");
  await expect(page).toHaveURL("/ru/more");
  await expect(more).toHaveAttribute("aria-current", "page");
  const screen = page.locator(".more-page");
  // What's new, eight tools, then profile, sharing and settings.
  await expect(screen.getByRole("link")).toHaveCount(12);
  await expect(screen.getByRole("link", { name: /^Что нового/ })).toHaveAttribute("href", "/ru/news");
  await expect(screen.getByRole("link", { name: "Заметки", exact: true })).toHaveAttribute("href", "/ru/notes");
  await expect(screen.getByRole("link", { name: "Имена Аллаха", exact: true })).toHaveAttribute("href", "/ru/names");
  await expect(page.getByTestId("header-back")).toBeHidden();

  await screen.getByRole("link", { name: "Ду’а", exact: true }).click();
  await expect(page).toHaveURL("/ru/dua");
  await expect(more).toHaveAttribute("aria-current", "page");
  // Every screen behind a tab has a way back.
  await page.getByTestId("header-back").click();
  await expect(page).toHaveURL("/ru/more");

  await screen.getByTestId("more-settings").click();
  await expect(page).toHaveURL("/ru/settings");
  const language = page.getByTestId("mobile-language-switcher");
  await expect(language).toBeVisible();
  await expect(language).toHaveValue("ru");
  await language.selectOption("ar");
  await expect(page).toHaveURL("/ar/settings");
  await expect(page.locator("html")).toHaveAttribute("dir", "rtl");
  await page.reload();
  await expect(language).toHaveValue("ar");
  await expect(more).toHaveAttribute("aria-current", "page");
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
  await navigation.getByTestId("mobile-more-tab").click();
  await expect(page).toHaveURL("/ru/more");
  await expect(navigation).toBeVisible();
  await navigation.getByRole("link", { name: "Главная", exact: true }).click();
  await expect(page).toHaveURL("/ru");
  await expect(navigation).toBeVisible();
});

test("mobile More fits landscape and the compact breakpoint does not alter desktop tokens", async ({ page }) => {
  await page.setViewportSize({ width: 667, height: 375 });
  await page.goto("/ru");
  await page.goto("/ru/more");
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(667);
  await page.locator(".more-page").getByRole("link", { name: /^Личный кабинет/ }).click();
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

test("the phone home follows the app; the desktop home keeps its own blocks", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/ru");

  // The top bar: the name with today's date and the way to the settings.
  await expect(page.getByTestId("home-date")).toContainText(" · ");
  await expect(page.getByTestId("home-settings")).toHaveAttribute("href", "/ru/settings");
  await expect(page.locator(".header-actions")).toBeHidden();

  // The sky of prayers, the reading to continue with the day's goal, the sections.
  await expect(page.getByTestId("home-sky")).toBeVisible();
  const reading = page.getByTestId("home-reading");
  await expect(reading.getByText("Продолжить чтение")).toBeVisible();
  await expect(reading.getByText("Аль-Фатиха")).toBeVisible();
  await expect(reading.getByText("Аят 1 · Страница 1")).toBeVisible();
  await expect(reading.getByRole("link", { name: "Читать" })).toHaveAttribute("href", "/ru/quran");
  await expect(page.getByTestId("home-plan")).toHaveAttribute("href", "/ru/planner");
  const tiles = page.locator(".home-section-tile");
  await expect(tiles).toHaveCount(9);
  expect(
    await page.locator(".home-sections-grid").evaluate((grid) =>
      getComputedStyle(grid).gridTemplateColumns.split(" ").length,
    ),
  ).toBe(3);

  // The desktop's other blocks are not on the phone.
  for (const testId of ["home-hero", "today-reading", "featured-reciters"]) {
    await expect(page.getByTestId(testId)).toBeHidden();
  }
  await expect(page.locator(".home-surah-catalog, .home-planner-cta, .home-page .kpi-grid")).toHaveCount(3);
  for (const block of await page.locator(".home-surah-catalog, .home-planner-cta, .home-page .kpi-grid").all()) {
    await expect(block).toBeHidden();
  }

  // The ninth tile opens the More screen.
  await expect(page.getByTestId("home-section-all")).toHaveAttribute("href", "/ru/more");

  await page.setViewportSize({ width: 1280, height: 900 });
  for (const testId of ["home-hero", "today-reading", "featured-reciters"]) {
    await expect(page.getByTestId(testId)).toBeVisible();
  }
  for (const testId of ["home-date", "home-settings", "home-reading", "home-section-all"]) {
    await expect(page.getByTestId(testId)).toBeHidden();
  }
  await expect(page.locator(".header-actions")).toBeVisible();
});
