import { expect, test } from "@playwright/test";

// Opt-in verification against a prepared local backend and official CDN assets.
// Unit/e2e fixtures stay independent of provider credentials and network.
const origin = process.env.IQRO_LOCAL_API_URL;
test.skip(!origin, "Set IQRO_LOCAL_API_URL and PLAYWRIGHT_BASE_URL for real QF data");

test("all 13 real layouts render and preserve verse navigation", async ({ page }) => {
  test.setTimeout(240_000);
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(error.message));
  const catalog = await (await page.request.get(`${origin}/api/v1/quran/foundation/mushafs`)).json();
  expect(catalog).toHaveLength(13);
  await page.goto("/ru/quran?surah=2&ayah=255");
  await expect(page.locator("#mushaf-variant option")).toHaveCount(13, { timeout: 60_000 });
  for (const source of catalog) {
    console.info(`Checking QF ${source.source_id}`);
    const index = await (await page.request.get(`${origin}/api/v1/quran/foundation/mushafs/${source.source_id}/page-index`)).json();
    await page.locator("#mushaf-variant").selectOption(String(source.source_id));
    const view = page.locator(`.qf-mushaf-view[data-mushaf-id="${source.source_id}"]`);
    await expect(view).toHaveAttribute("data-page-number", String(index.verse_pages["2:255"][0]), { timeout: 60_000 });
    await expect(view).toHaveAttribute("data-font-status", "ready", { timeout: 60_000 });
    await expect(view.locator('[data-ayah-key="2:255"].is-selected')).not.toHaveCount(0, { timeout: 60_000 });
    await expect(page.locator("#mushaf-page-jump")).toHaveAttribute("max", String(source.pages_count));
    const geometry = await view.evaluate((element) => {
      const sheet = element.querySelector(".qf-mushaf-sheet")!.getBoundingClientRect();
      return [...element.querySelectorAll(".qf-mushaf-word")].every((word) => {
        const r = word.getBoundingClientRect();
        return r.left >= sheet.left - 1 && r.right <= sheet.right + 1 && r.top >= sheet.top - 1 && r.bottom <= sheet.bottom + 1;
      });
    });
    expect(geometry).toBe(true);
  }
  // Persist a verse from a 610-page layout, then restore it after a reload.
  await page.locator("#mushaf-variant").selectOption("14");
  const selected = page.locator('.qf-mushaf-view[data-mushaf-id="14"] [data-ayah-key="2:255"]');
  await selected.first().click();
  await expect.poll(() => page.evaluate(() => {
    const values = Object.values(localStorage).flatMap((value) => { try { return [JSON.parse(value)]; } catch { return []; } });
    return values.some((value) => value?.surahNumber === 2 && value?.ayahNumber === 255 && value?.pageNumber === 42);
  })).toBe(true);
  await page.goto("/ru/quran");
  await expect(page.locator('.qf-mushaf-view[data-mushaf-id="14"] [data-ayah-key="2:255"].is-selected')).not.toHaveCount(0, { timeout: 60_000 });
  expect(errors).toEqual([]);
});
