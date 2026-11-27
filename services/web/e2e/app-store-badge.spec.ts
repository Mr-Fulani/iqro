import { expect, test } from "@playwright/test";

// playwright.config.ts sets NEXT_PUBLIC_IOS_APP_STORE_URL; the switched-off
// state is covered by lib/store-badge.test.ts.
const STORE_URL = "https://apps.apple.com/app/iqro/id6740000000";
const LABELS = {
  ru: "Загрузите в App Store",
  en: "Download on the App Store",
  ar: "تنزيل من App Store",
  tr: "App Store'dan İndirin",
};

for (const [locale, label] of Object.entries(LABELS)) {
  test(`App Store badge first on the home page and in the footer: ${locale}`, async ({ page }) => {
    await page.goto(`/${locale}`);
    const badges = page.getByTestId("app-store-badge");
    await expect(badges).toHaveCount(2);
    for (const badge of await badges.all()) {
      await expect(badge).toHaveAttribute("href", STORE_URL);
      await expect(badge).toHaveAttribute("target", "_blank");
      await expect(badge).toHaveAttribute("rel", /noopener/);
      const image = badge.getByRole("img", { name: label });
      await expect(image).toHaveAttribute("src", `/images/store/app-store-${locale}.svg`);
    }
    // Apple asks for its badge first in a row of stores' badges.
    for (const row of [page.getByTestId("home-app-card"), page.locator(".footer-app-stores")]) {
      await expect(row.locator(".app-store-badge, .google-play-badge").first()).toHaveClass("app-store-badge");
    }
    const homeBadge = page.getByTestId("home-app-card").getByTestId("app-store-badge");
    await homeBadge.scrollIntoViewIfNeeded();
    await expect(homeBadge.getByRole("img")).toHaveJSProperty("complete", true);
    expect(await homeBadge.getByRole("img").evaluate((img: HTMLImageElement) => img.naturalWidth)).toBeGreaterThan(0);
    // The "coming soon" plate gives way to the badge, and Apple's credit line appears.
    await expect(page.locator(".footer-store-badge", { hasText: "App Store" })).toHaveCount(0);
    await expect(page.locator(".footer-bottom")).toContainText("Apple Inc.");
  });
}

test("Safari's app banner tag is in the head of every page", async ({ request }) => {
  // Safari reads the tag from the page as it arrives, so it must be in <head>, also on
  // pages rendered on request (privacy).
  for (const path of ["/ru", "/en/privacy", "/tr/dua"]) {
    const html = await (await request.get(path)).text();
    const tag = html.indexOf('<meta name="apple-itunes-app" content="app-id=6740000000"/>');
    expect(tag, path).toBeGreaterThan(0);
    expect(tag, path).toBeLessThan(html.indexOf("</head>"));
  }
});

test("both store badges fit a phone in the page flow", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/ru");
  const stores = page.getByTestId("home-app-card").locator(".home-app-stores");
  await stores.scrollIntoViewIfNeeded();
  await expect(stores.getByTestId("app-store-badge")).toBeVisible();
  await expect(stores.getByTestId("google-play-badge")).toBeVisible();
  for (const badge of await stores.locator("img").all()) {
    expect((await badge.boundingBox())?.height).toBe(48);
  }
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
});
