import { readFile } from "node:fs/promises";
import { devices, expect, type Page, test } from "@playwright/test";

// Al-Fatiha of the test API in a Mushaf of its own: ayahs 1–4 on its first
// page, 5–7 on the second, which never loads. Ayah 3 has a word too many.
const WORDS = [4, 4, 3, 3];
const checksum = "c".repeat(64);
const mushaf = {
  source_id: 5,
  name: "KFGQPC HAFS",
  description: "fixture",
  qirat_name: "Hafs",
  pages_count: 604,
  lines_per_page: 15,
  default_font_name: "qpc-hafs",
  mapping_mode: "reference",
  schema_version: "1",
  sync_sequence: 1,
  source_checksum_sha256: checksum,
  last_synced_at: "2026-08-25T00:00:00Z",
  rendering: {
    available: true,
    version: 2,
    mode: "unicode-font",
    font_format: "woff2",
    font_url: "https://verses.quran.foundation/fonts/quran/hafs/uthmanic_hafs/UthmanicHafs1Ver18.woff2",
  },
  source: { name: "Quran.Foundation Content API", url: "https://api-docs.quran.foundation/", attribution: "Quran Foundation" },
};

function firstPage() {
  let id = 0;
  const words = WORDS.flatMap((count, index) => [
    ...Array.from({ length: count }, (_, position) => ({ type: "word", text: `س${index + 1}`, position: position + 1 })),
    { type: "end", text: `۝${index + 1}`, position: count + 1 },
  ].map((word) => {
    id += 1;
    return {
      id, word_id: id, verse_id: index + 1, verse_key: `1:${index + 1}`, page_number: 1, line_number: index + 1,
      position_in_line: word.position, position_in_page: id, position_in_verse: word.position,
      char_type_id: null, char_type_name: word.type, text: word.text, css_class: "", css_style: "",
    };
  }));
  return {
    mushaf_id: 5, qirat_name: "Hafs", font_name: "qpc-hafs", rendering: mushaf.rendering, page_number: 1,
    pages_count: 604, lines_per_page: 15, source_checksum_sha256: checksum, verse_mapping: { "1": "1-4" },
    first_verse_id: 1, last_verse_id: 4, first_word_id: 1, last_word_id: id, verses_count: 4, words,
  };
}

async function mockMushaf(page: Page) {
  const font = await readFile(
    new URL("../node_modules/next/dist/next-devtools/server/font/geist-latin.woff2", import.meta.url),
  );
  await page.route("https://verses.quran.foundation/fonts/**", (route) =>
    route.fulfill({ status: 200, contentType: "font/woff2", body: font }));
  await page.route("**/api/v1/quran/foundation/mushafs", (route) => route.fulfill({ json: [mushaf] }));
  await page.route("**/api/v1/quran/foundation/mushafs/5/page-index", (route) => route.fulfill({ json: {
    mushaf_id: 5, pages_count: 604, source_checksum_sha256: checksum,
    verse_pages: { "1:1": [1], "1:2": [1], "1:3": [1], "1:4": [1], "1:5": [2], "1:6": [2], "1:7": [2] },
  } }));
  await page.route("**/api/v1/quran/foundation/mushafs/5/pages/*", (route) =>
    route.request().url().endsWith("/pages/1") ? route.fulfill({ json: firstPage() }) : route.fulfill({ status: 503 }));
}

/** The Quran text, the cards with translation and buttons. */
async function openText(page: Page) {
  await page.goto("/ru/quran");
  const toolbar = page.getByRole("toolbar").getByRole("button", { name: "Настройки чтения", exact: true });
  // A phone opens the full-screen Mushaf: the switch is in its settings.
  if (await toolbar.waitFor({ timeout: 4000 }).then(() => true, () => false)) await toolbar.click();
  await page.getByRole("button", { name: "📜 Текст", exact: true }).click();
  await expect(page.locator("#quran-ayah-1-5")).toBeVisible();
}

test("the text cards are written as the selected Mushaf writes them, with a line at its page end", async ({ page }) => {
  await mockMushaf(page);
  await openText(page);

  const word = page.locator('#quran-ayah-1-2 [data-word-key="1:2:1"]');
  await expect(word).toHaveText("س2");
  await expect(word).toHaveCSS("font-family", /qf-mushaf-5/);
  await expect(page.locator("#quran-ayah-1-2 .ayah-end-marker")).toHaveText("۝2");
  // Not the reader's words: the plain text stays, and its own end sign.
  await expect(page.locator("#quran-ayah-1-3 .ayah-end-marker")).toHaveText("﴿٣﴾");
  await expect(page.locator('#quran-ayah-1-3 [data-word-key="1:3:1"]')).not.toHaveCSS("font-family", /qf-mushaf-5/);
  // A page that did not load leaves the plain text too.
  await expect(page.locator("#quran-ayah-1-5 .ayah-end-marker")).toHaveText("﴿٥﴾");

  const end = page.getByTestId("reader-page-end");
  await expect(end).toHaveCount(1);
  await expect(end).toHaveText("Страница 1");
  expect(await end.evaluate((element) => element.nextElementSibling?.id)).toBe("quran-ayah-1-5");
});

test.describe("on a phone", () => {
  test.use({ viewport: devices["Pixel 7"].viewport, userAgent: devices["Pixel 7"].userAgent,
    deviceScaleFactor: devices["Pixel 7"].deviceScaleFactor, isMobile: true, hasTouch: true });

  test("the plain text takes the Mushaf's script, page ends and page numbers, in the reader's digits", async ({ page }) => {
    await mockMushaf(page);
    await openText(page);
    const words = page.locator("#quran-ayah-1-5 .quran-arabic-text");
    await words.scrollIntoViewIfNeeded();
    const box = (await words.boundingBox())!;
    const width = page.viewportSize()!.width;
    const y = box.y + box.height / 2;
    const session = await page.context().newCDPSession(page);
    await session.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: width * 0.25, y }] });
    for (let step = 1; step <= 12; step += 1) {
      await session.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [{ x: width * (0.25 + step / 24), y }] });
      await page.waitForTimeout(16);
    }
    await session.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });

    const reader = page.getByTestId("plain-text-reader");
    // The second page of this Mushaf, in digits a reader of Russian knows.
    await expect(page.getByTestId("plain-text-place")).toHaveText("Аят 5 · стр. 2");
    await expect(reader.getByTestId("plain-text-page-end")).toHaveText("Страница 1");
    await expect(reader.locator('[data-word-key="1:2:1"]')).toHaveText("س2");
    await expect(reader.locator('[data-word-key="1:2:1"]')).toHaveCSS("font-family", /qf-mushaf-5/);
    await expect(reader.locator('[data-ayah="5"] .ayah-end-marker')).toHaveText("﴿٥﴾");
  });
});
