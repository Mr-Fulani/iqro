import { expect, Page, test } from "@playwright/test";

const guestSession = {
  token_type: "Bearer",
  access_token: "guest-access-token",
  expires_in: 900,
  access_expires_at: "2026-08-23T18:15:00Z",
  user: {
    id: "00000000-0000-7000-8000-000000000101",
    status: "guest",
    preferred_locale: "ru",
    email: null,
  },
  device: {
    id: "00000000-0000-7000-8000-000000000201",
    platform: "web",
    locale: "ru",
    app_version: "1.0.0",
    bootstrap_generation: 1,
  },
};

const activeSession = {
  ...guestSession,
  access_token: "active-access-token",
  user: {
    ...guestSession.user,
    id: "00000000-0000-7000-8000-000000000102",
    status: "active",
    email: "reader@example.com",
  },
  merged_guest: true,
  replayed: false,
};

async function installAuthMocks(page: Page) {
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ status: 401 }));
  await page.route("**/api/web-auth/guest", (route) => route.fulfill({ json: guestSession }));
  await page.route("**/api/web-auth/email/start", (route) =>
    route.fulfill({
      status: 202,
      json: {
        challenge_id: "00000000-0000-7000-8000-000000000301",
        expires_in: 600,
        expires_at: "2026-08-23T18:10:00Z",
      },
    }),
  );
  await page.route("**/api/web-auth/email/verify", (route) =>
    route.fulfill({ json: activeSession }),
  );
  await page.route("**/api/v1/**", async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path.includes("reading-position")) {
      await route.fulfill({ status: 404, json: { detail: "Not found" } });
    } else if (path.endsWith("/bookmarks")) {
      await route.fulfill({ json: { next: null, previous: null, results: [] } });
    } else if (path.endsWith("/feedback/tickets")) {
      await route.fulfill({ json: [] });
    } else {
      await route.fulfill({ status: 404, json: { detail: `Unhandled ${path}` } });
    }
  });
}

test("verified email login merges the guest without persisting tokens in localStorage", async ({
  page,
}) => {
  await installAuthMocks(page);
  await page.goto("/login");

  await page.getByLabel("Email").fill("reader@example.com");
  await page.getByRole("button", { name: "Получить код" }).click();
  await expect(page.getByText(/Код отправлен на reader@example.com/)).toBeVisible();

  await page.getByLabel("Код из письма").fill("123456");
  await page.getByRole("button", { name: "Подтвердить и войти" }).click();

  await expect(page.getByText("Вход выполнен, гостевые данные объединены с аккаунтом.")).toBeVisible();
  await expect(page.getByText("reader@example.com", { exact: true })).toBeVisible();
  await expect(page.getByRole("link", { name: "В личный кабинет" })).toBeVisible();
  const storageDump = await page.evaluate(() => JSON.stringify({ ...localStorage }));
  expect(storageDump).not.toContain("guest-access-token");
  expect(storageDump).not.toContain("active-access-token");
  expect(storageDump).not.toContain("refresh_token");
  expect(storageDump).not.toContain("installation_credential");
});
