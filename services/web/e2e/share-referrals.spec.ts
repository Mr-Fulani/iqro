import { expect, test } from "@playwright/test";

const activeSession = {
  token_type: "Bearer",
  access_token: "active-access-token",
  expires_in: 900,
  access_expires_at: "2026-08-30T12:15:00Z",
  user: {
    id: "00000000-0000-7000-8000-000000000102",
    status: "active",
    preferred_locale: "ru",
    email: "reader@example.com",
    deletion_requested_at: null,
    deletion_scheduled_for: null,
  },
  device: {
    id: "00000000-0000-7000-8000-000000000201",
    platform: "web",
    locale: "ru",
    app_version: "1.0.0",
    bootstrap_generation: 1,
  },
};

test("profile explains referrals, creates a personal link on demand, and hides technical IDs", async ({
  page,
  context,
}) => {
  await context.grantPermissions(["clipboard-read", "clipboard-write"]);
  await page.route("**/api/web-auth/refresh", (route) =>
    route.fulfill({ json: activeSession }),
  );

  let linkRequests = 0;
  await page.route("**/api/v1/**", async (route) => {
    const request = route.request();
    const url = new URL(request.url());

    if (url.pathname.includes("/reading-position/")) {
      return route.fulfill({ status: 404, json: { detail: "Not found" } });
    }
    if (url.pathname === "/api/v1/me/bookmarks") {
      return route.fulfill({ json: { next: null, previous: null, results: [] } });
    }
    if (url.pathname === "/api/v1/me/dua-favorites") {
      return route.fulfill({ json: { results: [] } });
    }
    if (url.pathname === "/api/v1/feedback/tickets") {
      return route.fulfill({ json: { next: null, previous: null, results: [] } });
    }
    if (url.pathname === "/api/v1/me/devices") {
      return route.fulfill({ json: [] });
    }
    if (url.pathname === "/api/v1/share/config") {
      return route.fulfill({
        json: {
          available: true,
          fallback_reason: null,
          requested_locale: "ru",
          used_fallback: false,
          campaign: {
            key: "app-invite",
            config_version: 2,
            updated_at: "2026-08-30T12:00:00Z",
            locale: "ru",
            title: "Пригласить друзей в IQRO",
            message: "Читайте Коран вместе с IQRO.",
            cta_label: "Поделиться",
            canonical_download_url: "https://staging.iqro.forum/",
            ios_url: "",
            android_url: "",
            referral_enabled: true,
          },
        },
      });
    }
    if (url.pathname === "/api/v1/me/referrals/summary") {
      return route.fulfill({
        json: {
          campaign_key: "app-invite",
          invited: 4,
          qualified: 2,
          reward_balance: 50,
          pending_reward: 25,
        },
      });
    }
    if (url.pathname === "/api/v1/me/referrals/links" && request.method() === "POST") {
      linkRequests += 1;
      expect(request.postDataJSON()).toEqual({ campaign_key: "app-invite" });
      return route.fulfill({
        status: 201,
        json: {
          campaign_key: "app-invite",
          code: "IQRO-TEST",
          short_url: "https://staging.iqro.forum/r/IQRO-TEST",
          is_enabled: true,
          created_at: "2026-08-30T12:00:00Z",
        },
      });
    }
    if (url.pathname === "/api/v1/share/events") {
      return route.fulfill({ status: 201, json: { accepted: true } });
    }
    return route.fulfill({ status: 404, json: { detail: `Unhandled ${url.pathname}` } });
  });

  await page.goto("/profile");

  await expect(page.getByText("reader@example.com", { exact: true }).first()).toBeVisible();
  await expect(page.getByText(/ID пользователя|Устройство:/)).toHaveCount(0);
  await expect(page.getByRole("heading", { name: "Пригласить друзей в IQRO" })).toBeVisible();
  await expect(page.getByText("Приглашено")).toBeVisible();
  await expect(page.getByText("4", { exact: true })).toBeVisible();
  await expect(page.getByLabel("Ссылка для приглашения")).toHaveCount(0);
  expect(linkRequests).toBe(0);

  await page.getByRole("button", { name: "Получить персональную ссылку" }).click();

  await expect(page.getByLabel("Ссылка для приглашения")).toHaveValue(
    "https://staging.iqro.forum/r/IQRO-TEST",
  );
  await expect(page.getByText("IQRO-TEST", { exact: true })).toBeVisible();
  expect(linkRequests).toBe(1);

  await page.getByRole("button", { name: "Скопировать", exact: true }).click();
  await expect(page.getByText("Ссылка скопирована.")).toBeVisible();

  await page.setViewportSize({ width: 320, height: 760 });
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(
    await page.evaluate(() => document.documentElement.clientWidth),
  );
  await expect(page.getByLabel("Ссылка для приглашения")).toBeVisible();
});
