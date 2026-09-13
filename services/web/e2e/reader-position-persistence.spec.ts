import { expect, test } from "@playwright/test";

const storageKey = "iqro_quran_reading_position_v1:madani-hafs";

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
  // Streaming can temporarily retain a hidden copy of the reader. Assert the
  // accessible control, not both the live input and the hidden server HTML.
  const pageJumpInput = page.getByRole("spinbutton", { name: /Страница Мусхафа/ });
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
  const pageJumpInput = page.getByRole("spinbutton", { name: /Страница Мусхафа/ });
  await expect(pageJumpInput).toHaveValue("5");
});
