import { expect, test } from "@playwright/test";

test.beforeEach(async ({ page }) => {
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ status: 401 }));
});

test("language switch persists RU EN AR and TR while Arabic enables RTL", async ({ page }) => {
  await page.goto("/login");

  const language = page.getByTestId("language-switcher");
  await expect(language).toHaveValue("ru");
  await expect(page.getByRole("heading", { name: "Вход в аккаунт" })).toBeVisible();

  await language.selectOption("en");
  await expect(page.locator("html")).toHaveAttribute("lang", "en");
  await expect(page.locator("html")).toHaveAttribute("dir", "ltr");
  await expect(page).toHaveTitle("Quran Platform — read and listen to the Quran");
  await expect(page.getByRole("heading", { name: "Account sign-in" })).toBeVisible();

  await page.reload();
  await expect(page.getByTestId("language-switcher")).toHaveValue("en");
  await expect(page.getByRole("heading", { name: "Account sign-in" })).toBeVisible();

  await page.getByTestId("language-switcher").selectOption("ar");
  await expect(page.locator("html")).toHaveAttribute("lang", "ar");
  await expect(page.locator("html")).toHaveAttribute("dir", "rtl");
  await expect(page).toHaveTitle("منصة القرآن — قراءة القرآن والاستماع إليه");
  await expect(page.getByRole("heading", { name: "تسجيل الدخول" })).toBeVisible();

  await page.getByTestId("language-switcher").selectOption("tr");
  await expect(page.locator("html")).toHaveAttribute("lang", "tr");
  await expect(page.locator("html")).toHaveAttribute("dir", "ltr");
  await expect(page.getByRole("heading", { name: "Hesaba giriş" })).toBeVisible();
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
