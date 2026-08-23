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
  ayah: {
    id: "01992d87-6c00-7000-8000-000000000402",
    surah_number: 2,
    ayah_number: 5,
  },
  label: "Тестовая закладка",
  color_key: "emerald",
  note: "Исходная заметка",
  client_updated_at: "2026-08-23T16:00:00Z",
  revision: 2,
  deleted_at: null,
  device_id: activeSession.device.id,
  created_at: "2026-08-23T16:00:00Z",
  updated_at: "2026-08-23T16:00:00Z",
};

const feedbackSummary = {
  public_id: "FB-contract-test",
  category: "audio",
  subject: "Проверка аудио",
  status: "new" as string,
  priority: "normal",
  locale: "ru",
  channel: "web",
  sla_response_due_at: null,
  first_response_at: null,
  created_at: "2026-08-23T16:00:00Z",
  updated_at: "2026-08-23T16:00:00Z",
};

function feedbackDetail() {
  return {
    ...feedbackSummary,
    client_request_id: "01992d87-6c00-7000-8000-000000000501",
    contact_email: null,
    team: "content-audio",
    resolved_at: null,
    closed_at: null as string | null,
    reopened_at: null,
    reopen_count: 0,
    context: {
      edition_code: "",
      content_version: "",
      surah_number: null,
      ayah_number: null,
      page_number: null,
      reciter_id: "",
      recitation_id: "",
      audio_track_id: "",
      playback_ms: null,
      ad_campaign_id: "",
      ad_creative_id: "",
      route: "/profile",
      app_version: "1.0.0",
      app_build: "",
      client_platform: "web",
      os_version: "",
    },
    messages: [
      {
        id: "01992d87-6c00-7000-8000-000000000502",
        client_message_id: "01992d87-6c00-7000-8000-000000000503",
        author_type: "reporter",
        body: "Исходное сообщение",
        created_at: "2026-08-23T16:00:00Z",
      },
    ],
  };
}

async function installSession(page: Page) {
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ json: activeSession }));
}

function emptyReading(route: Route) {
  return route.fulfill({ status: 404, json: { detail: "Reading position not found." } });
}

test("bookmark edit and delete follow the backend revision contract", async ({ page }) => {
  await installSession(page);
  let currentBookmark = { ...bookmark };
  const captured: {
    updatePayload?: Record<string, unknown>;
    deleteQuery?: URLSearchParams;
  } = {};

  await page.route("**/api/v1/**", async (route) => {
    const request = route.request();
    const url = new URL(request.url());
    if (url.pathname.includes("/reading-position/")) return emptyReading(route);
    if (url.pathname === "/api/v1/me/bookmarks" && request.method() === "GET") {
      return route.fulfill({
        json: { next: null, previous: null, results: [currentBookmark] },
      });
    }
    if (url.pathname === `/api/v1/me/bookmarks/${bookmark.id}` && request.method() === "PATCH") {
      captured.updatePayload = request.postDataJSON() as Record<string, unknown>;
      currentBookmark = {
        ...currentBookmark,
        label: String(captured.updatePayload.label),
        note: String(captured.updatePayload.note),
        revision: 3,
      };
      return route.fulfill({ json: currentBookmark });
    }
    if (url.pathname === `/api/v1/me/bookmarks/${bookmark.id}` && request.method() === "DELETE") {
      captured.deleteQuery = url.searchParams;
      return route.fulfill({ json: { ...currentBookmark, revision: 4, deleted_at: new Date().toISOString() } });
    }
    if (url.pathname === "/api/v1/feedback/tickets") {
      return route.fulfill({ json: { next: null, previous: null, results: [] } });
    }
    return route.fulfill({ status: 404, json: { detail: `Unhandled ${url.pathname}` } });
  });

  await page.goto("/profile");
  await expect(page.getByText("Сура 2:5")).toBeVisible();
  await page.getByRole("button", { name: "Изменить" }).click();
  await page.getByLabel("Название", { exact: true }).fill("Обновлённая закладка");
  await page.getByLabel("Заметка", { exact: true }).fill("Новая заметка");
  await page.getByRole("button", { name: "Сохранить", exact: true }).click();

  await expect(page.getByText("Обновлённая закладка")).toBeVisible();
  expect(captured.updatePayload).toMatchObject({
    label: "Обновлённая закладка",
    note: "Новая заметка",
    color_key: "emerald",
    base_revision: 2,
  });
  expect(captured.updatePayload?.client_updated_at).toEqual(expect.any(String));

  await page.getByRole("button", { name: "Удалить" }).click();
  await expect(page.getByText("Обновлённая закладка")).toHaveCount(0);
  expect(captured.deleteQuery?.get("base_revision")).toBe("3");
  expect(captured.deleteQuery?.get("client_updated_at")).toBeTruthy();
});

test("feedback create, reply, close and reopen match the backend contract", async ({ page }) => {
  await installSession(page);
  let detail: ReturnType<typeof feedbackDetail> | null = null;
  const captured: {
    createPayload?: Record<string, unknown>;
    replyPayload?: Record<string, unknown>;
  } = {};

  await page.route("**/api/v1/**", async (route) => {
    const request = route.request();
    const url = new URL(request.url());
    if (url.pathname.includes("/reading-position/")) return emptyReading(route);
    if (url.pathname === "/api/v1/me/bookmarks") {
      return route.fulfill({ json: { next: null, previous: null, results: [] } });
    }
    if (url.pathname === "/api/v1/feedback/tickets" && request.method() === "GET") {
      return route.fulfill({
        json: { next: null, previous: null, results: detail ? [detail] : [] },
      });
    }
    if (url.pathname === "/api/v1/feedback/tickets" && request.method() === "POST") {
      captured.createPayload = request.postDataJSON() as Record<string, unknown>;
      detail = feedbackDetail();
      return route.fulfill({ status: 201, json: detail });
    }
    if (url.pathname.endsWith("/messages") && request.method() === "POST" && detail) {
      captured.replyPayload = request.postDataJSON() as Record<string, unknown>;
      detail = {
        ...detail,
        messages: [
          ...detail.messages,
          {
            id: "01992d87-6c00-7000-8000-000000000504",
            client_message_id: String(captured.replyPayload.client_message_id),
            author_type: "reporter",
            body: String(captured.replyPayload.body),
            created_at: "2026-08-23T16:05:00Z",
          },
        ],
      };
      return route.fulfill({ status: 201, json: detail });
    }
    if (url.pathname.endsWith("/close") && request.method() === "POST" && detail) {
      detail = { ...detail, status: "closed", closed_at: "2026-08-23T16:06:00Z" };
      return route.fulfill({ json: detail });
    }
    if (url.pathname.endsWith("/reopen") && request.method() === "POST" && detail) {
      detail = { ...detail, status: "new", closed_at: null, reopen_count: 1 };
      return route.fulfill({ json: detail });
    }
    return route.fulfill({ status: 404, json: { detail: `Unhandled ${url.pathname}` } });
  });

  await page.goto("/profile");
  await page.getByRole("button", { name: "Создать обращение" }).click();
  await page.getByLabel("Категория обращения").selectOption("audio");
  await page.getByLabel("Тема").fill("Проверка аудио");
  await page.getByLabel("Сообщение", { exact: true }).fill("Исходное сообщение");
  await page.getByRole("button", { name: "Отправить обращение" }).click();

  expect(captured.createPayload).toMatchObject({
    category: "audio",
    subject: "Проверка аудио",
    message: "Исходное сообщение",
    locale: "ru",
    context: { route: "/profile", app_version: "1.0.0", client_platform: "web" },
  });
  expect(captured.createPayload?.client_request_id).toMatch(/^[0-9a-f-]{36}$/);
  expect(captured.createPayload?.client_message_id).toMatch(/^[0-9a-f-]{36}$/);
  await expect(page.getByText("Исходное сообщение")).toBeVisible();

  await page.getByLabel("Добавить сообщение").fill("Дополнительная информация");
  await page.getByRole("button", { name: "Отправить сообщение" }).click();
  expect(captured.replyPayload).toMatchObject({ body: "Дополнительная информация" });
  expect(captured.replyPayload?.client_message_id).toMatch(/^[0-9a-f-]{36}$/);
  await expect(page.getByText("Дополнительная информация")).toBeVisible();

  await page.getByRole("button", { name: "Закрыть обращение" }).click();
  await expect(page.getByRole("button", { name: "Открыть повторно" })).toBeVisible();
  await page.getByRole("button", { name: "Открыть повторно" }).click();
  await expect(page.getByRole("button", { name: "Закрыть обращение" })).toBeVisible();
});
