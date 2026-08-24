import { expect, test } from "@playwright/test";

// These tests intentionally cold-compile many dynamic App Router segments. Running them
// serially avoids Turbopack development artifacts being read while another worker rewrites them.
test.describe.configure({ mode: "serial", timeout: 60_000 });

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

test("unknown routes return the localized 404 surface and stay out of the index", async ({ page }) => {
  const response = await page.goto("/ru/this-page-does-not-exist");
  expect(response?.status()).toBe(404);
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Страница не найдена");
  await expect(page.locator('meta[name="robots"]')).toHaveAttribute("content", /noindex/);
  await expect(page.getByRole("link", { name: "Вернуться на главную" })).toHaveAttribute(
    "href",
    "/ru",
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
  expect(robots).toContain("Sitemap: http://127.0.0.1:3100/sitemaps/quran/sitemap.xml");
  expect(robots).toContain("Sitemap: http://127.0.0.1:3100/sitemaps/audio/sitemap.xml");

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

test("published surah and ayah routes render indexable Quran text on the server", async ({ page, request }) => {
  const editionResponse = await request.get("/ru/quran/madani-hafs");
  expect(editionResponse.ok()).toBe(true);
  const editionHtml = await editionResponse.text();
  expect(editionHtml).toContain("Суры Корана — Мединский мусхаф");
  expect(editionHtml).toContain("/ru/quran/madani-hafs/surah/1");

  const surahPath = "/ru/quran/madani-hafs/surah/1";
  const serverResponse = await request.get(surahPath);
  expect(serverResponse.ok()).toBe(true);
  const html = await serverResponse.text();
  expect(html).toContain("Сура 1: Аль-Фатиха");
  expect(html).toContain("بِسْمِ اللَّهِ");
  expect(html).toContain("/ru/quran/madani-hafs/surah/1/ayah/1");

  await page.goto(surahPath);
  await expect(page).toHaveTitle("Сура 1: Аль-Фатиха | Quran Platform");
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Сура 1: Аль-Фатиха");
  await expect(page.locator('link[rel="canonical"]')).toHaveAttribute(
    "href",
    `http://127.0.0.1:3100${surahPath}`,
  );
  expect(
    (await page.locator('script[type="application/ld+json"]').allTextContents()).join("\n"),
  ).toContain("BreadcrumbList");

  await page.goto(`${surahPath}/ayah/1`);
  await expect(page).toHaveTitle("Сура 1, аят 1: Аль-Фатиха | Quran Platform");
  await expect(page.locator(".seo-single-ayah")).toContainText("بِسْمِ اللَّهِ");
});

test("published reciter and recitation routes render the licensed audio catalog on the server", async ({ page, request }) => {
  const reciterId = "00000000-0000-7000-8000-000000000159";
  const recitationId = "00000000-0000-7000-8000-000000000701";
  const catalogResponse = await request.get("/ru/audio/reciters");
  expect(catalogResponse.ok()).toBe(true);
  const catalogHtml = await catalogResponse.text();
  expect(catalogHtml).toContain("Опубликованные чтецы Корана");
  expect(catalogHtml).toContain(`/ru/audio/reciters/${reciterId}`);

  await page.goto(`/ru/audio/reciters/${reciterId}`);
  await expect(page).toHaveTitle("Чтец Махер аль-Муайкли — декламации Корана | Quran Platform");
  await expect(page.getByRole("heading", { level: 1 })).toContainText("Махер аль-Муайкли");
  await expect(page.getByRole("link", { name: /MURATTAL/ })).toHaveAttribute(
    "href",
    `/ru/audio/recitations/${recitationId}`,
  );

  const recitationResponse = await request.get(`/ru/audio/recitations/${recitationId}`);
  expect(recitationResponse.ok()).toBe(true);
  const recitationHtml = await recitationResponse.text();
  expect(recitationHtml).toContain("Test streaming license");
  expect(recitationHtml).toContain("Сура 114");
  expect(recitationHtml).not.toContain("audio.example.test");
  expect(recitationHtml).toContain('"@type":"AudioObject"');
  expect(recitationHtml).toContain('"license":"https://example.test/licenses/audio"');
});

test("root layout publishes WebSite structured data", async ({ request }) => {
  const response = await request.get("/ru");
  expect(response.ok()).toBe(true);
  const html = await response.text();
  expect(html).toContain('"@type":"WebSite"');
  expect(html).toContain('"@id":"http://127.0.0.1:3100/#website"');
});

test("content revalidation accepts only authenticated allowlisted events", async ({ request }) => {
  const endpoint = "/api/internal/content-revalidation";
  const event = {
    type: "quran.edition.changed",
    action: "activated",
    edition: "madani-hafs",
    version: "1.0.0",
  };

  expect((await request.post(endpoint, { data: event })).status()).toBe(404);
  expect((await request.post(endpoint, {
    data: { ...event, arbitrary_tag: "everything" },
    headers: { Authorization: "Bearer test-only-content-revalidation-secret-0001" },
  })).status()).toBe(422);
  const accepted = await request.post(endpoint, {
    data: event,
    headers: { Authorization: "Bearer test-only-content-revalidation-secret-0001" },
  });
  expect(accepted.ok()).toBe(true);
  expect(await accepted.json()).toEqual({ accepted: true, type: event.type });
});

test("versioned Quran sitemap contains only routes from the published API catalog", async ({ request }) => {
  const indexResponse = await request.get("/sitemaps/quran/sitemap.xml");
  expect(indexResponse.ok()).toBe(true);
  const index = await indexResponse.text();
  expect(index).toContain(
    "http://127.0.0.1:3100/sitemaps/quran/madani-hafs/1.0.0/sitemap.xml",
  );
  expect(index).not.toContain("draft");

  const contentResponse = await request.get(
    "/sitemaps/quran/madani-hafs/1.0.0/sitemap.xml",
  );
  expect(contentResponse.ok()).toBe(true);
  const content = await contentResponse.text();
  expect(content).toContain(
    "<loc>http://127.0.0.1:3100/ru/quran/madani-hafs/surah/1</loc>",
  );
  expect(content).toContain(
    "<loc>http://127.0.0.1:3100/ar/quran/madani-hafs/surah/1/ayah/2</loc>",
  );
  expect(content).not.toContain("draft");

  const staleVersion = await request.get(
    "/sitemaps/quran/madani-hafs/0.9.0/sitemap.xml",
  );
  expect(staleVersion.status()).toBe(404);
  const draftPage = await request.get("/ru/quran/draft/surah/1");
  expect(draftPage.status()).toBe(404);
});

test("versioned audio sitemap contains only the current streamable recitation", async ({ request }) => {
  const recitationId = "00000000-0000-7000-8000-000000000701";
  const indexResponse = await request.get("/sitemaps/audio/sitemap.xml");
  expect(indexResponse.ok()).toBe(true);
  const index = await indexResponse.text();
  expect(index).toContain(
    `http://127.0.0.1:3100/sitemaps/audio/${recitationId}/1.0.0/sitemap.xml`,
  );

  const contentResponse = await request.get(
    `/sitemaps/audio/${recitationId}/1.0.0/sitemap.xml`,
  );
  expect(contentResponse.ok()).toBe(true);
  const content = await contentResponse.text();
  expect(content).toContain(
    `<loc>http://127.0.0.1:3100/ru/audio/recitations/${recitationId}</loc>`,
  );
  expect(content).toContain(
    "<loc>http://127.0.0.1:3100/ar/audio/reciters/00000000-0000-7000-8000-000000000159</loc>",
  );

  const staleVersion = await request.get(
    `/sitemaps/audio/${recitationId}/0.9.0/sitemap.xml`,
  );
  expect(staleVersion.status()).toBe(404);
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
