// The catalog's teaching reciter plays in the Mushaf reader until the visitor
// picks one; the audio player keeps its own default. The tajweed course always
// plays al-Husary's Muallim.
import { readFile } from "node:fs/promises";

import { expect, test, type Page } from "@playwright/test";

import {
  alternateRecitation,
  alternateTracks,
  paginated,
  recitation,
  recitationsMatching,
  reciter,
  tracks,
} from "./fixtures/audio.ts";

const MUSHAF_PREFERENCE_KEY = "quran_reciter_preference_v2:mushaf";

/** The shared catalog with al-Husary's recitation marked as the teaching one. */
async function routeTeachingCatalog(page: Page) {
  const testFont = await readFile(
    new URL("../node_modules/next/dist/next-devtools/server/font/geist-latin.woff2", import.meta.url),
  );
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ status: 401 }));
  await page.route("https://audio.example.test/**", (route) =>
    route.fulfill({ status: 200, contentType: "audio/mpeg", body: "" }),
  );
  await page.route("https://verses.quran.foundation/fonts/**", (route) =>
    route.fulfill({ status: 200, contentType: "font/woff2", body: testFont }),
  );
  await page.route((url) => url.pathname === "/api/v1/recitations", (route) => {
    const query = new URL(route.request().url()).searchParams;
    const catalog = recitationsMatching(query).map((item) =>
      item.id === alternateRecitation.id ? { ...item, teaching_default: true } : item,
    );
    return route.fulfill({ json: paginated(catalog) });
  });
}

test("the Mushaf plays the teaching reciter until the visitor picks one, and remembers only the pick", async ({ page }) => {
  await routeTeachingCatalog(page);
  await page.goto("/ru/quran?surah=6");
  const layout = page.locator(".quran-page-layout").filter({ visible: true });

  await expect(layout.locator("#mushaf-recitation")).toHaveValue(alternateRecitation.id);
  await expect(layout.locator("audio")).toHaveAttribute("src", alternateTracks[5].asset.url);
  expect(await page.evaluate((key) => window.localStorage.getItem(key), MUSHAF_PREFERENCE_KEY)).toBeNull();

  await layout.locator("#mushaf-recitation").selectOption(recitation.id, { force: true });
  await expect(layout.locator("audio")).toHaveAttribute("src", tracks[5].asset.url);
  await page.reload();
  const reloaded = page.locator(".quran-page-layout").filter({ visible: true });
  await expect(reloaded.locator("#mushaf-recitation")).toHaveValue(recitation.id);
  await expect(reloaded.locator("audio")).toHaveAttribute("src", tracks[5].asset.url);
});

test("the audio player keeps its own default reciter", async ({ page }) => {
  await routeTeachingCatalog(page);
  await page.goto("/ru/audio");

  await expect(page.locator("#audio-reciter-select")).toHaveValue(reciter.id);
  await expect(page.locator("#audio-reciter-select")).not.toHaveValue(alternateRecitation.reciter.id);
});

test("the tajweed course plays its examples with al-Husary's Muallim, whatever the Mushaf plays", async ({ page }) => {
  await routeTeachingCatalog(page);
  const muallim = { ...alternateRecitation, id: "00000000-0000-7000-8000-000000001012", code: "qf-12-muallim-01a15bc65dc9", style: "muallim" };
  await page.route((url) => url.pathname === "/api/v1/recitations", (route) => {
    const query = new URL(route.request().url()).searchParams;
    const catalog = recitationsMatching(query).map((item) =>
      item.id === alternateRecitation.id ? { ...item, teaching_default: true } : item,
    );
    return route.fulfill({ json: paginated([...catalog, muallim]) });
  });
  // The Mushaf plays another reciter: the course does not follow it.
  const picked = JSON.stringify({ personKey: reciter.slug, reciterId: reciter.id, recitationId: recitation.id, style: recitation.style });
  await page.addInitScript(([key, value]) => window.localStorage.setItem(key, value), [MUSHAF_PREFERENCE_KEY, picked]);
  const timingRequests: string[] = [];
  await page.route(/\/api\/v1\/recitations\/[^/]+\/ayahs\/\d+\/\d+$/, (route) => {
    timingRequests.push(new URL(route.request().url()).pathname);
    return route.fulfill({
      json: {
        track: { asset: { url: "https://audio.example.test/tajweed-course.mp3" } },
        segment: {
          start_ms: 1_000,
          end_ms: 9_000,
          words: Array.from({ length: 8 }, (_, index) => [index + 1, 1_000 + index * 1_000, 2_000 + index * 1_000]),
        },
      },
    });
  });

  await page.goto("/ru/tajweed/ikhfa");
  const lesson = page.getByTestId("tajweed-lesson");
  await expect(lesson).toHaveAttribute("aria-busy", "false");
  await expect(lesson.locator(".tajweed-course-ayah").first()).toBeAttached();
  await page.keyboard.press("ArrowRight");
  await page.keyboard.press("ArrowRight");
  await expect(page.getByTestId("tajweed-lesson-counter")).toHaveText("Шаг 3 из 6: Пример 1 из 3");
  const step = lesson.locator(".tajweed-lesson-step:not([hidden])");
  await step.getByRole("button", { name: "Послушать фрагмент" }).click();

  await expect.poll(() => timingRequests.length).toBeGreaterThan(0);
  expect(timingRequests[0]).toContain(`/api/v1/recitations/${muallim.id}/ayahs/`);
});
