import { expect, test, type ConsoleMessage } from "@playwright/test";

// Key pages must load and hydrate without a single error in the console.
const PAGES = [
  "/ru",
  "/en",
  "/ar",
  "/tr",
  "/ru/quran",
  "/ru/quran/madani-hafs/surah/1",
  "/ru/prayer",
  "/ru/salah/fajr",
  "/ru/tajweed",
  "/ru/tajweed/izhar",
  "/ru/dua",
  "/ru/news",
];

// Network failures the browser logs on its own; nothing else may reach the console.
const failedRequest = (message: ConsoleMessage, part: string) =>
  message.text().startsWith("Failed to load resource") && message.location().url.includes(part);

// Requests the mock API in e2e/mock-public-api.mjs does not serve; production answers them.
const MOCK_GAPS = [
  "/api/v1/prayer/methods",
  "/api/v1/quran/editions/madani-hafs/hizb",
  "/api/v1/quran/editions/madani-hafs/juz",
  "/api/v1/quran/editions/madani-hafs/rub-el-hizb",
  "/api/v1/quran/foundation/mushafs",
  "/api/v1/quran/tafsirs",
  "/api/v1/quran/translations",
  "/api/v1/recitations/00000000-0000-7000-8000-000000000701/ayahs/",
  "https://audio.example.test/",
];

const ALLOWED: { reason: string; matches: (message: ConsoleMessage) => boolean }[] = [
  { reason: "a guest has no session to refresh", matches: (message) => failedRequest(message, "/api/web-auth/refresh") },
  { reason: "a guest has no prayer profile", matches: (message) => failedRequest(message, "/api/v1/me/prayer-profile") },
  { reason: "the mock API does not serve it", matches: (message) => MOCK_GAPS.some((part) => failedRequest(message, part)) },
];

// The server renders in UTC; a visitor in Tokyo is already in the next day at night.
test.use({ timezoneId: "Asia/Tokyo" });

for (const path of PAGES) {
  for (const viewport of [
    { name: "desktop", width: 1280, height: 900 },
    { name: "phone", width: 390, height: 844 },
  ]) {
    test(`${path} on a ${viewport.name} hydrates without console errors`, async ({ page }) => {
      const errors: string[] = [];
      page.on("pageerror", (error) => errors.push(`pageerror: ${error.message}`));
      page.on("console", (message) => {
        if (message.type() !== "error" || ALLOWED.some((allowed) => allowed.matches(message))) return;
        errors.push(`console.error: ${message.text()} (${message.location().url})`);
      });
      await page.setViewportSize({ width: viewport.width, height: viewport.height });
      await page.goto(path, { waitUntil: "load" });
      // Hydration, the announcement fetch and the receipts sync settle by then.
      await page.waitForLoadState("networkidle").catch(() => undefined);
      expect(errors).toEqual([]);
    });
  }
}
