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
  let prayerPlan: Record<string, unknown> | null = null;
  const prayerCheckIns: Record<string, Record<string, unknown>> = {};
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
    if (url.pathname === "/api/v1/me/prayer-reading-plan" && request.method() === "GET") {
      const checkIns = Object.values(prayerCheckIns);
      const pagesPerPrayer = Number(prayerPlan?.pages_per_prayer || 0);
      return route.fulfill({
        json: {
          local_date: "2026-08-28",
          timezone_name: String(prayerPlan?.timezone_name || "Europe/Istanbul"),
          plan: prayerPlan,
          check_ins: checkIns,
          achieved_pages: checkIns.reduce((sum, item) => sum + Number(item.pages), 0),
          target_pages: prayerPlan ? pagesPerPrayer * 5 : 0,
          remaining_pages: prayerPlan
            ? Math.max(0, pagesPerPrayer * 5 - checkIns.reduce((sum, item) => sum + Number(item.pages), 0))
            : 0,
        },
      });
    }
    if (url.pathname === "/api/v1/me/prayer-reading-plan" && request.method() === "PUT") {
      const payload = request.postDataJSON() as Record<string, unknown>;
      writes.push(payload);
      prayerPlan = {
        id: "019a1284-9800-7000-8000-000000000701",
        pages_per_prayer: payload.pages_per_prayer,
        timezone_name: payload.timezone_name,
        revision: 1,
        client_updated_at: payload.client_updated_at,
        device_id: activeSession.device.id,
        created_at: "2026-08-28T09:00:00Z",
        updated_at: "2026-08-28T09:00:00Z",
      };
      return route.fulfill({ status: 201, json: prayerPlan });
    }
    if (url.pathname === "/api/v1/me/prayer-reading-check-ins" && request.method() === "POST") {
      const payload = request.postDataJSON() as Record<string, unknown>;
      writes.push(payload);
      const checkIn = {
        id: payload.id,
        prayer: payload.prayer,
        local_date: payload.local_date,
        timezone_name: payload.timezone_name,
        pages: Number(prayerPlan?.pages_per_prayer || 2),
        reading_session_id: payload.session_id,
        revision: 1,
        client_updated_at: payload.client_updated_at,
        device_id: activeSession.device.id,
        created_at: "2026-08-28T09:10:00Z",
        updated_at: "2026-08-28T09:10:00Z",
      };
      prayerCheckIns[String(payload.prayer)] = checkIn;
      return route.fulfill({ status: 201, json: checkIn });
    }
    if (
      url.pathname.startsWith("/api/v1/me/prayer-reading-check-ins/") &&
      request.method() === "DELETE"
    ) {
      const checkInId = url.pathname.split("/").at(-1);
      const entry = Object.entries(prayerCheckIns).find(([, item]) => item.id === checkInId);
      if (entry) delete prayerCheckIns[entry[0]];
      return route.fulfill({ status: 204, body: "" });
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

test("prayer reading plan calculates the honest pace and tracks five prayer slots", async ({ page }) => {
  const writes = await installReadingMocks(page);
  await page.goto("/");

  const plan = page.getByTestId("prayer-reading-plan");
  await expect(plan.getByRole("heading", { name: "Чтение после намаза" })).toBeVisible();
  await expect(plan.getByTestId("pages-per-prayer-value")).toHaveText("2");
  await expect(plan.getByText("≈ 61")).toBeVisible();
  await plan.getByRole("button", { name: "Сохранить план" }).click();

  await expect(plan.getByText("Сегодня: 0 из 5 намазов")).toBeVisible();
  const fajr = plan.getByRole("button", { name: /после намаза Фаджр/ });
  await fajr.click();

  await expect(plan.getByText("Сегодня: 1 из 5 намазов")).toBeVisible();
  await expect(plan.getByText("2 / 10 стр.")).toBeVisible();
  await expect(fajr).toHaveAttribute("aria-pressed", "true");
  expect(writes[0]).toMatchObject({ pages_per_prayer: 2, base_revision: 0 });
  expect(writes[1]).toMatchObject({ prayer: "fajr", local_date: "2026-08-28" });
  expect(String(writes[1].id)).toMatch(/^[0-9a-f-]{36}$/);
  expect(String(writes[1].session_id)).toMatch(/^[0-9a-f-]{36}$/);

  await fajr.click();
  await expect(plan.getByText("Сегодня: 0 из 5 намазов")).toBeVisible();
  await expect(plan.getByText("0 / 10 стр.")).toBeVisible();

  await page.setViewportSize({ width: 320, height: 760 });
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(
    await page.evaluate(() => document.documentElement.clientWidth),
  );
  expect(
    await plan.locator(".prayer-reading-slots").evaluate((grid) =>
      getComputedStyle(grid).gridTemplateColumns.split(" ").length,
    ),
  ).toBe(2);
});
