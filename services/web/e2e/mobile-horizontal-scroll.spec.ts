import { expect, test, type Page } from "@playwright/test";

// Runs in WebKit, the engine of every iPhone browser (see playwright.config.ts): there
// the text of a <select> narrower than its longest option used to stick out of the box
// and make the whole page wider than the screen. Chromium clips it by itself.

test.beforeEach(async ({ page }) => {
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ status: 401 }));
});

/** The page must not scroll sideways; a failure names the element that widens it. */
async function expectNoHorizontalScroll(page: Page, label: string) {
  await expect.poll(() => page.evaluate(() => {
    const root = document.documentElement;
    const width = root.scrollWidth;
    if (width <= root.clientWidth) return "fits";
    let node: Element = document.body;
    for (;;) {
      const wider = [...node.children].find((child) => {
        const element = child as HTMLElement;
        const display = element.style.display;
        element.style.display = "none";
        const narrower = root.scrollWidth < width;
        element.style.display = display;
        return narrower;
      });
      if (!wider) break;
      node = wider;
    }
    return `${width}px page in a ${root.clientWidth}px window: <${node.tagName.toLowerCase()} id="${node.id}" class="${node.getAttribute("class") ?? ""}">`;
  }), { message: label }).toBe("fits");
  // The same on any platform's WebKit build, whatever its list rendering.
  expect(await page.locator("select").evaluateAll((lists) => lists
    .filter((list) => getComputedStyle(list).overflowX === "visible")
    .map((list) => list.id)), `${label}: lists that do not clip their text`).toEqual([]);
}

const pages = [
  "", "/surahs", "/planner", "/audio", "/more", "/memorization", "/prayer", "/calendar", "/dua",
  "/names", "/salah", "/tajweed", "/courses", "/settings", "/profile", "/login",
  "/quran/madani-hafs/surah/1/ayah/1",
];

for (const { width, locale } of [
  { width: 320, locale: "ru" },
  { width: 360, locale: "en" },
  { width: 390, locale: "ru" },
  { width: 430, locale: "ar" },
]) {
  test(`the Quran page does not scroll sideways at ${width}px in ${locale}`, async ({ page }) => {
    test.setTimeout(120_000);
    await page.setViewportSize({ width, height: 780 });
    // A short and a long surah name; the Mushaf and the text view.
    for (const surah of [1, 3]) {
      await page.goto(`/${locale}/quran?surah=${surah}&ayah=1`);
      const reader = page.locator(".quran-page-layout").filter({ visible: true });
      await expect(reader).toHaveClass(/is-reader-immersive/);
      await expectNoHorizontalScroll(page, `surah ${surah}, reader`);
      // The screen before the reader is opened: the cards, the settings and the audio panel.
      await reader.locator(".mushaf-page-container").focus();
      await page.keyboard.press("Escape");
      await expect(reader).not.toHaveClass(/is-reader-immersive/);
      await expect(reader.locator("#mushaf-recitation option").first()).toBeAttached();
      await expectNoHorizontalScroll(page, `surah ${surah}, Mushaf, settings closed`);
      const settings = reader.locator(".quran-reader-settings");
      await settings.locator("summary").click();
      await expect(settings.locator("#mushaf-variant")).toBeVisible();
      await expectNoHorizontalScroll(page, `surah ${surah}, Mushaf, settings open`);

      await page.goto(`/${locale}/quran?surah=${surah}&ayah=1&view=text`);
      await expect(reader).not.toHaveClass(/is-mushaf-mode/);
      await expectNoHorizontalScroll(page, `surah ${surah}, text, settings closed`);
      await settings.locator("summary").click();
      await expect(settings.locator("#quran-edition")).toBeVisible();
      await expectNoHorizontalScroll(page, `surah ${surah}, text, settings open`);
    }
  });

  test(`the main pages do not scroll sideways at ${width}px in ${locale}`, async ({ page }) => {
    test.setTimeout(180_000);
    await page.setViewportSize({ width, height: 780 });
    for (const route of pages) {
      await page.goto(`/${locale}${route}`);
      await expect(page.locator("main")).toBeVisible();
      await expectNoHorizontalScroll(page, route || "/");
    }
  });
}
