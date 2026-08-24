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

const pendingDeletionSession = {
  ...activeSession,
  user: {
    ...activeSession.user,
    status: "pending_deletion",
    deletion_requested_at: "2026-08-23T18:00:00Z",
    deletion_scheduled_for: "2026-08-30T18:00:00Z",
  },
};

const deviceInventory = [
  {
    id: activeSession.device.id,
    platform: "web",
    locale: "ru",
    app_version: "1.0.0",
    created_at: "2026-08-20T12:00:00Z",
    last_seen_at: "2026-08-23T18:00:00Z",
    last_session_used_at: "2026-08-23T18:00:00Z",
    active_session_count: 1,
    is_current: true,
  },
  {
    id: "00000000-0000-7000-8000-000000000202",
    platform: "ios",
    locale: "en",
    app_version: "2.1.0",
    created_at: "2026-08-21T12:00:00Z",
    last_seen_at: "2026-08-22T16:00:00Z",
    last_session_used_at: "2026-08-22T16:00:00Z",
    active_session_count: 1,
    is_current: false,
  },
];

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
    } else if (path.endsWith("/me/devices")) {
      await route.fulfill({ json: deviceInventory });
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

test("pending guest changes are pushed before the account merge", async ({ page }) => {
  await installAuthMocks(page);
  const guestSyncKey = `quran_platform_sync_v1:${guestSession.user.id}`;
  const operation = {
    operation_id: "01992d87-6c00-7000-8000-000000000901",
    entity_type: "bookmark",
    entity_id: "01992d87-6c00-7000-8000-000000000902",
    action: "upsert",
    base_revision: 0,
    client_updated_at: "2026-08-23T16:00:00Z",
    payload: { edition_code: "madani-hafs", page_number: 1 },
  };
  await page.addInitScript(
    ({ key, queued }) => {
      localStorage.setItem(
        key,
        JSON.stringify({ cursor: 0, outbox: [queued], reading_position_ids: {} }),
      );
    },
    { key: guestSyncKey, queued: operation },
  );

  const order: string[] = [];
  await page.unroute("**/api/v1/**");
  await page.route("**/api/v1/**", (route) => {
    const url = new URL(route.request().url());
    if (url.pathname === "/api/v1/sync/push") {
      order.push("sync-push");
      return route.fulfill({
        json: {
          results: [
            {
              operation_id: operation.operation_id,
              outcome: "accepted",
              replayed: false,
              entity: null,
              cursor: 1,
            },
          ],
          cursor: 1,
        },
      });
    }
    if (url.pathname === "/api/v1/sync/pull") {
      order.push("sync-pull");
      return route.fulfill({
        json: { mode: "incremental", changes: [], next_cursor: 1, has_more: false },
      });
    }
    return route.fulfill({ status: 404, json: { detail: `Unhandled ${url.pathname}` } });
  });
  await page.unroute("**/api/web-auth/email/verify");
  await page.route("**/api/web-auth/email/verify", (route) => {
    order.push("email-verify");
    return route.fulfill({ json: activeSession });
  });

  await page.goto("/login");
  await page.getByLabel("Email").fill("reader@example.com");
  await page.getByRole("button", { name: "Получить код" }).click();
  await page.getByLabel("Код из письма").fill("123456");
  await page.getByRole("button", { name: "Подтвердить и войти" }).click();

  await expect(page.getByText("Вход выполнен, гостевые данные объединены с аккаунтом.")).toBeVisible();
  expect(order).toEqual(["sync-push", "sync-pull", "email-verify"]);
  expect(await page.evaluate((key) => localStorage.getItem(key), guestSyncKey)).toBeNull();
});

test("guest session keeps the email login CTA in main content, not the header", async ({ page }) => {
  await installAuthMocks(page);
  await page.unroute("**/api/web-auth/refresh");
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ json: guestSession }));

  await page.goto("/");

  await expect(page.getByText("Гостевой режим", { exact: true }).first()).toBeVisible();
  await expect(page.locator(".app-header").getByRole("link", { name: "Войти по email" })).toHaveCount(0);
  const emailLogin = page.locator("main").getByRole("link", { name: "Войти по email" }).first();
  await expect(emailLogin).toBeVisible();
  await expect(emailLogin).toHaveAttribute("href", "/login");
  await expect(page.getByRole("button", { name: "Выйти" })).toHaveCount(0);
});

test("logout all sessions requires confirmation and clears the web session", async ({ page }) => {
  await installAuthMocks(page);
  await page.unroute("**/api/web-auth/refresh");
  await page.route("**/api/web-auth/refresh", (route) =>
    route.fulfill({ json: activeSession }),
  );
  let logoutAllCalls = 0;
  await page.route("**/api/web-auth/logout-all", (route) => {
    logoutAllCalls += 1;
    return route.fulfill({ status: 204, body: "" });
  });

  await page.goto("/profile");
  await page.getByRole("button", { name: "Выйти на всех устройствах" }).click();
  await expect(page.getByText("Завершить все сессии?")).toBeVisible();
  expect(logoutAllCalls).toBe(0);

  await page.getByRole("button", { name: "Отмена" }).click();
  await expect(page.getByText("Завершить все сессии?")).toHaveCount(0);
  await page.getByRole("button", { name: "Выйти на всех устройствах" }).click();
  await page.getByRole("button", { name: "Подтвердить выход везде" }).click();

  await expect(page.getByRole("heading", { name: "Личный кабинет читателя" })).toBeVisible();
  expect(logoutAllCalls).toBe(1);
});

test("account cabinet lists devices and revokes another device after confirmation", async ({
  page,
}) => {
  await installAuthMocks(page);
  await page.unroute("**/api/web-auth/refresh");
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ json: activeSession }));
  let revokeCalls = 0;
  await page.route(`**/api/v1/me/devices/${deviceInventory[1].id}`, (route) => {
    revokeCalls += 1;
    return route.fulfill({ status: 204, body: "" });
  });

  await page.goto("/profile");
  await expect(page.getByRole("heading", { name: "Устройства и сессии" })).toBeVisible();
  await expect(page.getByText("Web-браузер")).toBeVisible();
  await expect(page.getByText("iPhone / iPad")).toBeVisible();
  await expect(page.getByText("Текущее", { exact: true })).toBeVisible();

  await page.getByRole("button", { name: "Завершить сессии" }).click();
  expect(revokeCalls).toBe(0);
  await page.getByRole("button", { name: "Подтвердить отключение" }).click();

  await expect(page.getByText("Сессии выбранного устройства завершены.")).toBeVisible();
  await expect(page.getByText("iPhone / iPad")).toHaveCount(0);
  expect(revokeCalls).toBe(1);
});

test("account deletion uses fresh email proof, grace period, and cancellable recovery", async ({
  page,
}) => {
  await installAuthMocks(page);
  await page.unroute("**/api/web-auth/refresh");
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ json: activeSession }));
  let verifyCalls = 0;
  await page.unroute("**/api/web-auth/email/verify");
  await page.route("**/api/web-auth/email/verify", (route) => {
    verifyCalls += 1;
    return route.fulfill({
      json: verifyCalls === 1 ? activeSession : pendingDeletionSession,
    });
  });
  await page.route("**/api/v1/me/deletion-request", (route) =>
    route.fulfill({
      status: 202,
      json: { user: pendingDeletionSession.user, device: activeSession.device },
    }),
  );
  await page.route("**/api/v1/me/deletion-cancel", (route) =>
    route.fulfill({
      json: { user: activeSession.user, device: activeSession.device },
    }),
  );

  await page.goto("/profile");
  await page.getByRole("button", { name: "Удалить аккаунт" }).click();
  await expect(page.getByText("Запланировать удаление аккаунта?")).toBeVisible();
  await page.getByRole("button", { name: /Получить код на reader@example.com/ }).click();
  await page.getByLabel("Код из письма").fill("123456");
  await page.getByRole("button", { name: "Подтвердить удаление" }).click();

  await expect(page.getByRole("heading", { name: "Удаление аккаунта запланировано" })).toBeVisible();
  await expect(page.getByText(/30 авг. 2026/)).toBeVisible();
  await expect(page.getByRole("heading", { name: "Ваши закладки" })).toHaveCount(0);

  await page.getByRole("button", { name: "Отменить удаление" }).click();
  await page.getByRole("button", { name: /Получить код на reader@example.com/ }).click();
  await page.getByLabel("Код из письма").fill("654321");
  await page.getByRole("button", { name: "Восстановить аккаунт" }).click();

  await expect(page.getByRole("heading", { name: "Устройства и сессии" })).toBeVisible();
  await expect(page.getByText("Удаление аккаунта отменено.")).toBeVisible();
  expect(verifyCalls).toBe(2);
});

test("email challenge reconciles a restored guest with its installation", async ({ page }) => {
  await installAuthMocks(page);
  await page.unroute("**/api/web-auth/refresh");
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ json: guestSession }));

  const authOrder: string[] = [];
  await page.unroute("**/api/web-auth/guest");
  await page.route("**/api/web-auth/guest", (route) => {
    authOrder.push("guest");
    return route.fulfill({ json: guestSession });
  });
  await page.unroute("**/api/web-auth/email/start");
  await page.route("**/api/web-auth/email/start", (route) => {
    authOrder.push("email-start");
    return route.fulfill({
      status: 202,
      json: {
        challenge_id: "00000000-0000-7000-8000-000000000301",
        expires_in: 600,
        expires_at: "2026-08-23T18:10:00Z",
      },
    });
  });

  await page.goto("/login");
  await page.getByLabel("Email").fill("reader@example.com");
  await page.getByRole("button", { name: "Получить код" }).click();

  await expect(page.getByText(/Код отправлен на reader@example.com/)).toBeVisible();
  expect(authOrder).toEqual(["guest", "email-start"]);
});

test("invalid email challenge shows an actionable localized error", async ({ page }) => {
  await installAuthMocks(page);
  await page.unroute("**/api/web-auth/email/verify");
  await page.route("**/api/web-auth/email/verify", (route) =>
    route.fulfill({
      status: 400,
      json: {
        code: "email_challenge_invalid",
        detail: "Email verification could not be completed.",
      },
    }),
  );

  await page.goto("/login");
  await page.getByLabel("Email").fill("reader@example.com");
  await page.getByRole("button", { name: "Получить код" }).click();
  await page.getByLabel("Код из письма").fill("123456");
  await page.getByRole("button", { name: "Подтвердить и войти" }).click();

  await expect(
    page.getByText("Код неверен или сессия изменилась. Запросите новый код."),
  ).toBeVisible();
});
