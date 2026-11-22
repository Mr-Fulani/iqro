import { expect, test } from "@playwright/test";

// playwright.config.ts sets NEXT_PUBLIC_ANDROID_PLAY_STORE_URL; the switched-off
// state is covered by lib/store-badge.test.ts.
const STORE_URL = "https://play.google.com/store/apps/details?id=forum.iqro.app";
const LABELS = {
  ru: "Доступно в Google Play",
  en: "Get it on Google Play",
  ar: "احصل عليه من Google Play",
  tr: "Google Play'den alın",
};

for (const [locale, label] of Object.entries(LABELS)) {
  test(`Google Play badge on the home page and in the footer: ${locale}`, async ({ page }) => {
    await page.goto(`/${locale}`);
    const badges = page.getByTestId("google-play-badge");
    await expect(badges).toHaveCount(2);
    for (const badge of await badges.all()) {
      await expect(badge).toHaveAttribute("href", STORE_URL);
      await expect(badge).toHaveAttribute("target", "_blank");
      await expect(badge).toHaveAttribute("rel", /noopener/);
      const image = badge.getByRole("img", { name: label });
      await expect(image).toHaveAttribute("src", `/images/store/google-play-${locale}.webp`);
    }
    const homeBadge = page.getByTestId("home-app-card").getByTestId("google-play-badge");
    await homeBadge.scrollIntoViewIfNeeded();
    await expect(homeBadge.getByRole("img")).toHaveJSProperty("complete", true);
    expect(await homeBadge.getByRole("img").evaluate((img: HTMLImageElement) => img.naturalWidth)).toBeGreaterThan(0);
  });
}

test("Google Play badge stays in the page flow on a phone", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/ru");
  const card = page.getByTestId("home-app-card");
  await card.scrollIntoViewIfNeeded();
  await expect(card).toBeVisible();
  expect(await card.evaluate((element) => getComputedStyle(element).position)).toBe("static");
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
});
