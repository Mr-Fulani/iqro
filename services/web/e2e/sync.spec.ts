import { expect, Page, Route, test } from "@playwright/test";

const activeSession = {
  token_type: "Bearer",
  access_token: "active-access-token",
  expires_in: 900,
  access_expires_at: "2026-08-23T18:15:00Z",
  user: {
    id: "00000000-0000-7000-8000-000000000102",
    status: "active",
    preferred_locale: "ru",
    email: "reader@example.com",
  },
  device: {
    id: "00000000-0000-7000-8000-000000000201",
    platform: "web",
    locale: "ru",
    app_version: "1.0.0",
    bootstrap_generation: 1,
  },
};

const bookmark = {
  id: "01992d87-6c00-7000-8000-000000000401",
  entity_type: "bookmark",
  edition_code: "madani-hafs",
  page_number: 3,
  ayah: null,
  label: "Синхронизируемая закладка",
  color_key: "emerald",
  note: "",
  client_updated_at: "2026-08-23T16:00:00Z",
  revision: 2,
  deleted_at: null,
  device_id: activeSession.device.id,
  created_at: "2026-08-23T16:00:00Z",
  updated_at: "2026-08-23T16:00:00Z",
};

const storageKey = `quran_platform_sync_v1:${activeSession.user.id}`;

async function installSession(page: Page) {
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ json: activeSession }));
}

function emptyReading(route: Route) {
  return route.fulfill({ status: 404, json: { detail: "Reading position not found." } });
}

function fulfillProfileRead(route: Route): boolean {
  const request = route.request();
  const url = new URL(request.url());
  if (url.pathname.includes("/reading-position/")) {
    void emptyReading(route);
    return true;
  }
  if (url.pathname === "/api/v1/me/bookmarks" && request.method() === "GET") {
    void route.fulfill({ json: { next: null, previous: null, results: [bookmark] } });
    return true;
  }
  if (url.pathname === "/api/v1/feedback/tickets") {
    void route.fulfill({ json: { next: null, previous: null, results: [] } });
    return true;
  }
  if (url.pathname === "/api/v1/me/reminders" && request.method() === "GET") {
    void route.fulfill({
      json: {
        mode: "full_snapshot",
        authoritative: true,
        generated_at: "2026-08-23T16:00:00Z",
        count: 0,
        reminders: [],
      },
    });
    return true;
  }
  if (url.pathname === "/api/v1/me/web-push" && request.method() === "GET") {
    void route.fulfill({
      json: {
        available: false,
        enabled: false,
        vapid_public_key: "",
        timezone_name: null,
        locale: null,
        prayer_location_configured: false,
        prayer_profile_configured: false,
        supported_reminder_types: ["prayer", "quran_review"],
      },
    });
    return true;
  }
  return false;
}

test("sync push drains the durable outbox and advances only the pull cursor", async ({ page }) => {
  await installSession(page);
  const operation = {
    operation_id: "01992d87-6c00-7000-8000-000000000801",
    entity_type: "bookmark",
    entity_id: bookmark.id,
    action: "upsert",
    base_revision: 2,
    client_updated_at: "2026-08-23T16:05:00Z",
    payload: { label: "После офлайна" },
  };
  await page.addInitScript(
    ({ key, queued }) => {
      localStorage.setItem(
        key,
        JSON.stringify({ cursor: 0, outbox: [queued], reading_position_ids: {} }),
      );
    },
    { key: storageKey, queued: operation },
  );

  let pushedPayload: Record<string, unknown> | null = null;
  await page.route("**/api/v1/**", async (route) => {
    if (fulfillProfileRead(route)) return;
    const request = route.request();
    const url = new URL(request.url());
    if (url.pathname === "/api/v1/sync/push") {
      pushedPayload = request.postDataJSON() as Record<string, unknown>;
      return route.fulfill({
        json: {
          results: [
            {
              operation_id: operation.operation_id,
              outcome: "accepted",
              replayed: false,
              entity: { ...bookmark, label: "После офлайна", revision: 3 },
              cursor: 99,
            },
          ],
          cursor: 99,
        },
      });
    }
    if (url.pathname === "/api/v1/sync/pull") {
      expect(url.searchParams.get("cursor")).toBe("0");
      return route.fulfill({
        json: {
          mode: "incremental",
          changes: [
            {
              cursor: 7,
              entity_type: "bookmark",
              entity_id: bookmark.id,
              action: "upsert",
              revision: 3,
              entity: { ...bookmark, label: "После офлайна", revision: 3 },
              server_updated_at: "2026-08-23T16:05:01Z",
            },
          ],
          next_cursor: 7,
          has_more: false,
        },
      });
    }
    return route.fulfill({ status: 404, json: { detail: `Unhandled ${url.pathname}` } });
  });

  await page.goto("/profile");
  await expect(page.getByText("Изменения ожидают отправки")).toBeVisible();
  await expect(
    page.getByText(
      "Отправить локальные изменения и получить обновления аккаунта, включая изменения с других устройств.",
      { exact: true },
    ),
  ).toBeVisible();
  await page.getByRole("button", { name: /Синхронизировать данные/ }).click();
  await expect(page.getByText(/отправлено: 1, получено изменений: 1/)).toBeVisible();
  expect(pushedPayload).toEqual({ operations: [operation] });
  const state = await page.evaluate((key) => JSON.parse(localStorage.getItem(key) || "{}"), storageKey);
  expect(state.cursor).toBe(7);
  expect(state.outbox).toEqual([]);
});

test("network failure queues a bookmark mutation for a later sync push", async ({ page }) => {
  await installSession(page);
  let patchAttempts = 0;
  let pushedOperation: Record<string, unknown> | null = null;

  await page.route("**/api/v1/**", async (route) => {
    const request = route.request();
    const url = new URL(request.url());
    if (fulfillProfileRead(route)) return;
    if (
      url.pathname === `/api/v1/me/bookmarks/${bookmark.id}` &&
      request.method() === "PATCH"
    ) {
      patchAttempts += 1;
      return route.abort("internetdisconnected");
    }
    if (url.pathname === "/api/v1/sync/push") {
      const payload = request.postDataJSON() as { operations: Record<string, unknown>[] };
      pushedOperation = payload.operations[0];
      return route.fulfill({
        json: {
          results: [
            {
              operation_id: pushedOperation.operation_id,
              outcome: "accepted",
              replayed: false,
              entity: { ...bookmark, label: "Сохранено без сети", revision: 3 },
              cursor: 3,
            },
          ],
          cursor: 3,
        },
      });
    }
    if (url.pathname === "/api/v1/sync/pull") {
      return route.fulfill({
        json: { mode: "incremental", changes: [], next_cursor: 3, has_more: false },
      });
    }
    return route.fulfill({ status: 404, json: { detail: `Unhandled ${url.pathname}` } });
  });

  await page.goto("/profile");
  await page.getByRole("button", { name: "Изменить" }).click();
  await page.getByLabel("Название", { exact: true }).fill("Сохранено без сети");
  await page.getByRole("button", { name: "Сохранить", exact: true }).click();
  await expect(page.getByText(/Сеть недоступна. Изменение сохранено/)).toBeVisible();
  await expect(page.getByText("Изменения ожидают отправки")).toBeVisible();

  await page.getByRole("button", { name: /Синхронизировать данные/ }).click();
  await expect(page.getByText(/отправлено: 1/)).toBeVisible();
  expect(patchAttempts).toBe(1);
  expect(pushedOperation).toMatchObject({
    entity_type: "bookmark",
    entity_id: bookmark.id,
    action: "upsert",
    base_revision: 2,
    payload: { label: "Сохранено без сети", color_key: "emerald", note: "" },
  });
});

test("revision conflict is rebased onto the server entity with a new operation id", async ({
  page,
}) => {
  await installSession(page);
  const original = {
    operation_id: "01992d87-6c00-7000-8000-000000000811",
    entity_type: "bookmark",
    entity_id: bookmark.id,
    action: "upsert",
    base_revision: 2,
    client_updated_at: "2026-08-23T16:05:00Z",
    payload: { label: "Локальное намерение" },
  };
  await page.addInitScript(
    ({ key, queued }) => {
      localStorage.setItem(
        key,
        JSON.stringify({ cursor: 0, outbox: [queued], reading_position_ids: {} }),
      );
    },
    { key: storageKey, queued: original },
  );
  const attempts: Record<string, unknown>[] = [];

  await page.route("**/api/v1/**", async (route) => {
    if (fulfillProfileRead(route)) return;
    const request = route.request();
    const url = new URL(request.url());
    if (url.pathname === "/api/v1/sync/push") {
      const payload = request.postDataJSON() as { operations: Record<string, unknown>[] };
      const operation = payload.operations[0];
      attempts.push(operation);
      if (attempts.length === 1) {
        return route.fulfill({
          json: {
            results: [
              {
                operation_id: operation.operation_id,
                outcome: "conflict",
                replayed: false,
                conflict_reason: "revision_mismatch",
                entity: { ...bookmark, label: "Другое устройство", revision: 4 },
                cursor: 4,
              },
            ],
            cursor: 4,
          },
        });
      }
      return route.fulfill({
        json: {
          results: [
            {
              operation_id: operation.operation_id,
              outcome: "accepted",
              replayed: false,
              entity: { ...bookmark, label: "Локальное намерение", revision: 5 },
              cursor: 5,
            },
          ],
          cursor: 5,
        },
      });
    }
    if (url.pathname === "/api/v1/sync/pull") {
      return route.fulfill({
        json: { mode: "incremental", changes: [], next_cursor: 5, has_more: false },
      });
    }
    return route.fulfill({ status: 404, json: { detail: `Unhandled ${url.pathname}` } });
  });

  await page.goto("/profile");
  await page.getByRole("button", { name: /Синхронизировать данные/ }).click();
  await expect(page.getByText(/отправлено: 1/)).toBeVisible();
  expect(attempts).toHaveLength(2);
  expect(attempts[0]).toMatchObject({ operation_id: original.operation_id, base_revision: 2 });
  expect(attempts[1]).toMatchObject({
    entity_id: bookmark.id,
    base_revision: 4,
    payload: { label: "Локальное намерение" },
  });
  expect(attempts[1].operation_id).not.toBe(original.operation_id);
});

test("expired cursor completes every full-resync page before resuming incremental pull", async ({
  page,
}) => {
  await installSession(page);
  await page.addInitScript((key) => {
    localStorage.setItem(
      key,
      JSON.stringify({ cursor: 1, outbox: [], reading_position_ids: {} }),
    );
  }, storageKey);
  const requests: string[] = [];

  await page.route("**/api/v1/**", async (route) => {
    if (fulfillProfileRead(route)) return;
    const url = new URL(route.request().url());
    if (url.pathname !== "/api/v1/sync/pull") {
      return route.fulfill({ status: 404, json: { detail: `Unhandled ${url.pathname}` } });
    }
    requests.push(url.search);
    if (url.searchParams.get("cursor") === "1") {
      return route.fulfill({
        status: 410,
        contentType: "application/problem+json",
        json: {
          status: 410,
          code: "sync_cursor_expired",
          detail: "Cursor expired.",
          full_resync_required: true,
          minimum_valid_cursor: 5,
          current_cursor: 9,
        },
      });
    }
    if (url.searchParams.get("full_resync") === "true" && !url.searchParams.get("page_token")) {
      return route.fulfill({
        json: {
          mode: "full_resync",
          entities: [bookmark],
          snapshot_cursor: 9,
          next_page_token: "signed-page-2",
          has_more: true,
        },
      });
    }
    if (url.searchParams.get("page_token") === "signed-page-2") {
      return route.fulfill({
        json: {
          mode: "full_resync",
          entities: [],
          snapshot_cursor: 9,
          next_page_token: null,
          has_more: false,
        },
      });
    }
    if (url.searchParams.get("cursor") === "9") {
      return route.fulfill({
        json: {
          mode: "incremental",
          changes: [
            {
              cursor: 10,
              entity_type: "bookmark",
              entity_id: bookmark.id,
              action: "upsert",
              revision: 3,
              entity: { ...bookmark, revision: 3 },
              server_updated_at: "2026-08-23T16:10:00Z",
            },
          ],
          next_cursor: 10,
          has_more: false,
        },
      });
    }
    return route.fulfill({ status: 400, json: { detail: `Unexpected query ${url.search}` } });
  });

  await page.goto("/profile");
  await page.getByRole("button", { name: /Синхронизировать данные/ }).click();
  await expect(page.getByText(/полная сверка: 1 объектов/)).toBeVisible();
  const state = await page.evaluate((key) => JSON.parse(localStorage.getItem(key) || "{}"), storageKey);
  expect(state.cursor).toBe(10);
  expect(requests).toEqual([
    "?limit=100&cursor=1",
    "?limit=100&full_resync=true",
    "?limit=100&full_resync=true&page_token=signed-page-2",
    "?limit=100&cursor=9",
  ]);
});
