import { expect, Page, test } from "@playwright/test";

const activeSession = {
  token_type: "Bearer",
  access_token: "reading-habit-access-token",
  expires_in: 900,
  access_expires_at: "2026-08-28T12:15:00Z",
  user: {
    id: "00000000-0000-7000-8000-000000000601",
    status: "active",
    preferred_locale: "ru",
    email: "reader@example.com",
    deletion_requested_at: null,
    deletion_scheduled_for: null,
  },
  device: {
    id: "00000000-0000-7000-8000-000000000602",
    platform: "web",
    locale: "ru",
    app_version: "1.0.0",
    bootstrap_generation: 1,
  },
};

function goalSnapshot() {
  return {
    id: "019a1284-9800-7000-8000-000000000601",
    metric: "pages",
    target_amount: "3.00",
    timezone_name: "Europe/Istanbul",
    started_on: "2026-08-28",
    ended_on: null,
    status: "active",
    revision: 1,
    client_updated_at: "2026-08-28T09:00:00Z",
    device_id: activeSession.device.id,
    created_at: "2026-08-28T09:00:00Z",
    updated_at: "2026-08-28T09:00:00Z",
  };
}

function todaySnapshot(achieved: number, hasGoal: boolean) {
  const goal = hasGoal ? goalSnapshot() : null;
  return {
    local_date: "2026-08-28",
    timezone_name: "Europe/Istanbul",
    continue_reading: null,
    goal,
    progress: goal
      ? {
          goal_id: goal.id,
          local_date: "2026-08-28",
          metric: "pages",
          target_amount: "3.00",
          achieved_amount: achieved.toFixed(2),
          remaining_amount: Math.max(0, 3 - achieved).toFixed(2),
          is_completed: achieved >= 3,
          completed_at: achieved >= 3 ? "2026-08-28T09:10:00Z" : null,
        }
      : null,
    streak: {
      current_count: achieved >= 3 ? 1 : 0,
      longest_count: achieved >= 3 ? 1 : 0,
      last_qualifying_date: achieved >= 3 ? "2026-08-28" : null,
    },
  };
}

async function installReadingMocks(page: Page) {
  let hasGoal = false;
  let achieved = 0;
  const writes: Record<string, unknown>[] = [];

  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ json: activeSession }));
  await page.route("**/api/v1/**", async (route) => {
    const request = route.request();
    const url = new URL(request.url());
    if (url.pathname === "/api/v1/me/today" && request.method() === "GET") {
      return route.fulfill({
        headers: { "Cache-Control": "private, no-store" },
        json: todaySnapshot(achieved, hasGoal),
      });
    }
    if (url.pathname === "/api/v1/me/reading-goal" && request.method() === "PUT") {
      const payload = request.postDataJSON() as Record<string, unknown>;
      writes.push(payload);
      hasGoal = true;
      return route.fulfill({ status: 201, json: goalSnapshot() });
    }
    if (url.pathname === "/api/v1/me/reading-sessions/manual" && request.method() === "POST") {
      const payload = request.postDataJSON() as Record<string, unknown>;
      writes.push(payload);
      achieved += Number(payload.amount);
      return route.fulfill({
        status: 201,
        json: {
          id: payload.id,
          goal_id: goalSnapshot().id,
          source: "manual",
          status: "completed",
          timezone_name: payload.timezone_name,
          local_date: payload.local_date,
          started_at: "2026-08-28T09:10:00Z",
          ended_at: "2026-08-28T09:10:00Z",
          active_seconds: 0,
          credited_pages: 0,
          credited_ayahs: 0,
          manual_metric: payload.metric,
          manual_amount: Number(payload.amount).toFixed(2),
          revision: 1,
          client_updated_at: payload.client_updated_at,
          device_id: activeSession.device.id,
          deleted_at: null,
          created_at: "2026-08-28T09:10:00Z",
          updated_at: "2026-08-28T09:10:00Z",
        },
      });
    }
    return route.fallback();
  });

  return writes;
}

test("Today creates a daily goal and adds paper Mushaf progress", async ({ page }) => {
  const writes = await installReadingMocks(page);
  await page.goto("/");

  const today = page.getByTestId("today-reading");
  await expect(today.getByRole("heading", { name: "Сегодня" })).toBeVisible();
  await today.getByLabel("Считать норму в").selectOption("pages");
  await today.getByLabel("Норма на день").fill("3");
  await today.getByRole("button", { name: "Создать норму" }).click();

  await expect(today.getByText("0 / 3 стр.")).toBeVisible();
  expect(writes[0]).toMatchObject({
    metric: "pages",
    target_amount: 3,
    base_revision: 0,
  });

  await today.getByRole("button", { name: "Добавить вручную" }).click();
  await today.getByLabel("Прочитано — стр.").fill("3");
  await today.getByRole("button", { name: "Добавить к сегодняшнему прогрессу" }).click();

  await expect(today.getByText("Норма на сегодня выполнена")).toBeVisible();
  await expect(today.getByRole("progressbar")).toHaveAttribute("aria-valuenow", "100");
  expect(writes[1]).toMatchObject({ metric: "pages", amount: 3 });
  expect(String(writes[1].id)).toMatch(/^[0-9a-f-]{36}$/);
});
