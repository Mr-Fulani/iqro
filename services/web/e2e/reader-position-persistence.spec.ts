import { expect, test } from "@playwright/test";

const storageKey = "iqro_quran_reading_position_v1:madani-hafs";

test("turning mushaf page saves position to localStorage immediately and restores it upon return", async ({
  page,
}) => {
  await page.goto("/ru/quran");
  const pageJumpInput = page.locator("#mushaf-page-jump");
  await expect(pageJumpInput).toBeVisible();

  // Jump to page 7
  await pageJumpInput.fill("7");
  await pageJumpInput.press("Enter");

  // Verify localStorage contains page 7
  await expect.poll(async () => {
    return page.evaluate((key) => {
      const raw = localStorage.getItem(key);
      if (!raw) return null;
      return JSON.parse(raw).pageNumber;
    }, storageKey);
  }).toBe(7);

  // Navigate away and return to /ru/quran without query params
  await page.goto("/ru");
  await page.goto("/ru/quran");

  // Verify it restored to page 7
  const restoredInput = page.locator("#mushaf-page-jump");
  await expect(restoredInput).toHaveValue("7");
});

test("saved position restores after hydration without hydration errors", async ({
  page,
}) => {
  const hydrationErrors: string[] = [];
  page.on("console", (message) => { if (/hydration|hydrated|server rendered/i.test(message.text())) hydrationErrors.push(message.text()); });
  page.on("pageerror", (error) => hydrationErrors.push(error.message));
  // Pre-seed local storage with page 18
  await page.addInitScript(
    ({ key }) => {
      localStorage.setItem(
        key,
        JSON.stringify({
          pageNumber: 18,
          surahNumber: 2,
          ayahNumber: 113,
          updatedAt: new Date().toISOString(),
        }),
      );
    },
    { key: storageKey },
  );

  await page.goto("/ru/quran");
  const pageJumpInput = page.locator("#mushaf-page-jump");
  await expect(pageJumpInput).toHaveValue("18");
  expect(hydrationErrors).toEqual([]);
});

test("explicit query parameter page takes priority over saved local position", async ({
  page,
}) => {
  // Pre-seed local storage with page 50
  await page.addInitScript(
    ({ key }) => {
      localStorage.setItem(
        key,
        JSON.stringify({
          pageNumber: 50,
          surahNumber: 3,
          ayahNumber: 1,
          updatedAt: new Date().toISOString(),
        }),
      );
    },
    { key: storageKey },
  );

  // Open with ?page=5
  await page.goto("/ru/quran?page=5");
  const pageJumpInput = page.locator("#mushaf-page-jump");
  await expect(pageJumpInput).toHaveValue("5");
});
