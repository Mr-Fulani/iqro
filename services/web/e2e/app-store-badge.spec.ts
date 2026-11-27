import { expect, test, type Locator } from "@playwright/test";

// playwright.config.ts sets NEXT_PUBLIC_IOS_APP_STORE_URL; the switched-off
// state is covered by lib/store-badge.test.ts.
const STORE_URL = "https://apps.apple.com/app/iqro/id6740000000";
const LABELS = {
  ru: "Загрузите в App Store",
  en: "Download on the App Store",
  ar: "تنزيل من App Store",
  tr: "App Store'dan İndirin",
};

async function expectBadge(badge: Locator, locale: string, label: string) {
  await expect(badge).toHaveAttribute("href", STORE_URL);
  await expect(badge).toHaveAttribute("target", "_blank");
  await expect(badge).toHaveAttribute("rel", /noopener/);
  await expect(badge.getByRole("img", { name: label })).toHaveAttribute("src", `/images/store/app-store-${locale}.svg`);
}

for (const [locale, label] of Object.entries(LABELS)) {
  test(`App Store badge once per page and first among the stores: ${locale}`, async ({ page }) => {
    test.slow(); // two pages
    // Home: the app card has the stores' badges, so the footer does not repeat them.
    await page.goto(`/${locale}`);
    await expect(page.getByTestId("app-store-badge")).toHaveCount(1);
    await expect(page.locator(".footer-app-stores")).toHaveCount(0);
    const card = page.getByTestId("home-app-card");
    await expectBadge(card.getByTestId("app-store-badge"), locale, label);
    // Apple asks for its badge first in a row of stores' badges.
    await expect(card.locator(".app-store-badge, .google-play-badge").first()).toHaveClass("app-store-badge");
    const image = card.getByTestId("app-store-badge").getByRole("img");
    await image.scrollIntoViewIfNeeded();
    await expect(image).toHaveJSProperty("complete", true);
    expect(await image.evaluate((img: HTMLImageElement) => img.naturalWidth)).toBeGreaterThan(0);
    await expect(page.locator(".footer-bottom")).toContainText("Apple Inc.");

    // Any other page: the badge stands in the footer instead of the "coming soon" plate.
    await page.goto(`/${locale}/dua`);
    await expect(page.getByTestId("app-store-badge")).toHaveCount(1);
    const row = page.locator(".footer-app-stores");
    await expectBadge(row.getByTestId("app-store-badge"), locale, label);
    await expect(row.locator(".app-store-badge, .google-play-badge").first()).toHaveClass("app-store-badge");
    await expect(row.locator(".footer-store-badge")).toHaveCount(0);
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
