import { expect, test } from "@playwright/test";

async function expectSingleRowHeader(page: import("@playwright/test").Page) {
  const centers = await page.locator(
    ".app-header > .brand-block, .app-header > .app-menu, .app-header > .header-actions",
  ).evaluateAll((elements) => elements.map((element) => {
    const rect = element.getBoundingClientRect();
    return rect.y + rect.height / 2;
  }));
  expect(Math.max(...centers) - Math.min(...centers)).toBeLessThan(8);
  expect(await page.locator(".app-header").evaluate(
    (element) => element.scrollWidth <= element.clientWidth,
  )).toBe(true);
}

test.beforeEach(async ({ page }) => {
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ status: 401 }));
});

test("language switch persists RU EN AR and TR while Arabic enables RTL", async ({ page }) => {
  await page.setViewportSize({ width: 1250, height: 900 });
  await page.goto("/login");

  const language = page.getByTestId("language-switcher");
  await expect(language).toHaveValue("ru");
  await expect(page.getByRole("heading", { name: "Вход в аккаунт" })).toBeVisible();
  await expectSingleRowHeader(page);

  await language.selectOption("en");
  await expect(page.locator("html")).toHaveAttribute("lang", "en");
  await expect(page.locator("html")).toHaveAttribute("dir", "ltr");
  await expect(page).toHaveTitle("Quran Platform — read and listen to the Quran");
  await expect(page.getByRole("heading", { name: "Account sign-in" })).toBeVisible();
  await expectSingleRowHeader(page);

  await page.reload();
  await expect(page.getByTestId("language-switcher")).toHaveValue("en");
  await expect(page.getByRole("heading", { name: "Account sign-in" })).toBeVisible();

  await page.getByTestId("language-switcher").selectOption("ar");
  await expect(page.locator("html")).toHaveAttribute("lang", "ar");
  await expect(page.locator("html")).toHaveAttribute("dir", "rtl");
  await expect(page).toHaveTitle("منصة القرآن — قراءة القرآن والاستماع إليه");
  await expect(page.getByRole("heading", { name: "تسجيل الدخول" })).toBeVisible();
  await expectSingleRowHeader(page);

  await page.getByTestId("language-switcher").selectOption("tr");
  await expect(page.locator("html")).toHaveAttribute("lang", "tr");
  await expect(page.locator("html")).toHaveAttribute("dir", "ltr");
  await expect(page.getByRole("heading", { name: "Hesaba giriş" })).toBeVisible();
  await expectSingleRowHeader(page);
});

test.describe("browser language negotiation", () => {
  test.use({ locale: "tr-TR" });

  test("Accept-Language selects Turkish when no locale cookie exists", async ({ page }) => {
    await page.goto("/login");

    await expect(page.locator("html")).toHaveAttribute("lang", "tr");
    await expect(page.locator("html")).toHaveAttribute("dir", "ltr");
    await expect(page.getByTestId("language-switcher")).toHaveValue("tr");
    await expect(page.getByRole("heading", { name: "Hesaba giriş" })).toBeVisible();
  });
});
