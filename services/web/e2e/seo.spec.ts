import { expect, test } from "@playwright/test";

test.beforeEach(async ({ page }) => {
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ status: 401 }));
  await page.route("**/api/v1/**", (route) =>
    route.fulfill({ status: 404, json: { detail: "Not available in the SEO contract test." } }),
  );
});

test("public Quran page exposes page-specific canonical and social metadata", async ({ page }) => {
  await page.goto("/ru/quran");

  await expect(page).toHaveTitle("Читать Коран — Мадинский Мусхаф Хафс | Quran Platform");
  await expect(page.locator('meta[name="description"]')).toHaveAttribute(
    "content",
    /Читайте 114 сур Священного Корана/,
  );
  await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
    "href",
    "http://127.0.0.1:3100/ru/quran",
  );
  await expect(page.locator('link[rel="alternate"][hreflang="en"]')).toHaveAttribute(
    "href",
    "http://127.0.0.1:3100/en/quran",
  );
  await expect(page.locator('link[rel="alternate"][hreflang="ar"]')).toHaveAttribute(
    "href",
    "http://127.0.0.1:3100/ar/quran",
  );
  await expect(page.locator('link[rel="alternate"][hreflang="x-default"]')).toHaveAttribute(
    "href",
    "http://127.0.0.1:3100/ru/quran",
  );
  await expect(page.locator('meta[name="robots"]')).toHaveAttribute("content", /index, follow/);
  await expect(page.locator('meta[property="og:title"]')).toHaveAttribute(
    "content",
    "Читать Коран — Мадинский Мусхаф Хафс",
  );
  await expect(page.locator('meta[name="twitter:card"]')).toHaveAttribute(
    "content",
    "summary_large_image",
  );
});

test("account routes are explicitly excluded from indexing", async ({ page }) => {
  await page.goto("/ru/login");

  await expect(page).toHaveTitle("Вход в аккаунт | Quran Platform");
  await expect(page.locator('meta[name="robots"]')).toHaveAttribute("content", /noindex/);
  await expect(page.locator('meta[name="robots"]')).toHaveAttribute("content", /nofollow/);
  await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
    "href",
    "http://127.0.0.1:3100/ru/login",
  );
});

test("locale-prefixed routes drive language, direction, and localized navigation", async ({ page }) => {
  await page.goto("/ar/quran");

  await expect(page.locator("html")).toHaveAttribute("lang", "ar");
  await expect(page.locator("html")).toHaveAttribute("dir", "rtl");
  await expect(page).toHaveTitle("قراءة القرآن — مصحف المدينة برواية حفص | Quran Platform");
  await expect(page.locator('.app-menu a[href="/ar/audio"]')).toBeVisible();

  const unsupported = await page.request.get("/de/quran");
  expect(unsupported.status()).toBe(404);
});

test("robots and sitemap publish only the current public route set", async ({ request }) => {
  const robotsResponse = await request.get("/robots.txt");
  expect(robotsResponse.ok()).toBe(true);
  const robots = await robotsResponse.text();
  expect(robots).toContain("Disallow: /api/");
  expect(robots).toContain("Disallow: /profile");
  expect(robots).toContain("Disallow: /ru/profile");
  expect(robots).toContain("Sitemap: http://127.0.0.1:3100/sitemap.xml");

  const sitemapResponse = await request.get("/sitemap.xml");
  expect(sitemapResponse.ok()).toBe(true);
  const sitemap = await sitemapResponse.text();
  for (const locale of ["ru", "en", "ar", "tr"]) {
    for (const path of ["", "/quran", "/audio", "/prayer"]) {
      expect(sitemap).toContain(`<loc>http://127.0.0.1:3100/${locale}${path}</loc>`);
    }
  }
  expect(sitemap).not.toContain("/login");
  expect(sitemap).not.toContain("/register");
  expect(sitemap).not.toContain("/profile");
});

test("web manifest and generated share assets are available", async ({ request }) => {
  const manifestResponse = await request.get("/manifest.webmanifest");
  expect(manifestResponse.ok()).toBe(true);
  expect(await manifestResponse.json()).toMatchObject({
    name: "Quran Platform",
    short_name: "Quran",
    display: "standalone",
    theme_color: "#065f46",
  });

  const iconResponse = await request.get("/icon");
  expect(iconResponse.ok()).toBe(true);
  expect(iconResponse.headers()["content-type"]).toContain("image/png");

  const shareResponse = await request.get("/opengraph-image");
  expect(shareResponse.ok()).toBe(true);
  expect(shareResponse.headers()["content-type"]).toContain("image/png");
});
