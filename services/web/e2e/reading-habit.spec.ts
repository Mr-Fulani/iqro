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
      current_count: achieved > 0 ? 1 : 0,
      longest_count: achieved > 0 ? 1 : 0,
      last_qualifying_date: achieved > 0 ? "2026-08-28" : null,
    },
  };
}

async function installReadingMocks(page: Page) {
  let hasGoal = false;
  let achieved = 0;
  let prayerPlan: Record<string, unknown> | null = null;
  const prayerCheckIns: Record<string, Record<string, unknown>> = {};
  const writes: Record<string, unknown>[] = [];
  const plannerRanges: number[] = [];
  let readingSessions: Record<string, unknown>[] = [
    {
      id: "019a1284-9800-7000-8000-000000000801",
      goal_id: goalSnapshot().id,
      source: "manual",
      status: "completed",
      timezone_name: "Europe/Istanbul",
      local_date: "2026-08-27",
      started_at: "2026-08-27T17:10:00Z",
      ended_at: "2026-08-27T17:10:00Z",
      active_seconds: 0,
      credited_pages: 0,
      credited_ayahs: 0,
      manual_metric: "pages",
      manual_amount: "1.00",
      revision: 1,
      client_updated_at: "2026-08-27T17:10:00Z",
      device_id: activeSession.device.id,
      deleted_at: null,
      created_at: "2026-08-27T17:10:00Z",
      updated_at: "2026-08-27T17:10:00Z",
    },
    {
      id: "019a1284-9800-7000-8000-000000000802",
      goal_id: goalSnapshot().id,
      source: "automatic",
      status: "completed",
      timezone_name: "Europe/Istanbul",
      local_date: "2026-08-28",
      started_at: "2026-08-28T08:00:00Z",
      ended_at: "2026-08-28T08:01:30Z",
      active_seconds: 90,
      credited_pages: 1,
      credited_ayahs: 5,
      manual_metric: null,
      manual_amount: null,
      revision: 1,
      client_updated_at: "2026-08-28T08:01:30Z",
      device_id: activeSession.device.id,
      deleted_at: null,
      created_at: "2026-08-28T08:01:30Z",
      updated_at: "2026-08-28T08:01:30Z",
    },
  ];

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
    if (url.pathname === "/api/v1/me/reading-planner" && request.method() === "GET") {
      const days = Number(url.searchParams.get("days") || 30);
      plannerRanges.push(days);
      const yesterdayManual = readingSessions.find(
        (item) => item.source === "manual" && item.local_date === "2026-08-27",
      );
      const yesterdayAmount = Number(yesterdayManual?.manual_amount || 0);
      const history = Array.from({ length: days }, (_, index) => {
        const date = new Date(Date.UTC(2026, 7, 28 - (days - 1 - index), 12));
        const localDate = date.toISOString().slice(0, 10);
        if (localDate === "2026-08-28") {
          return {
            local_date: localDate,
            state: "pending",
            has_reading: true,
            goal: {
              id: goalSnapshot().id,
              metric: "pages",
              target_amount: "3.00",
              achieved_amount: "1.00",
              remaining_amount: "2.00",
            },
            prayer_check_ins: [],
            prayer_pages: 0,
            prayer_count: 0,
            automatic_sessions: 1,
            automatic_active_seconds: 90,
            automatic_pages: 1,
            automatic_ayahs: 5,
          };
        }
        if (localDate === "2026-08-27") {
          return {
            local_date: localDate,
            state:
              yesterdayAmount >= 3 ? "completed" : yesterdayAmount > 0 ? "partial" : "missed",
            has_reading: yesterdayAmount > 0,
            goal: {
              id: goalSnapshot().id,
              metric: "pages",
              target_amount: "3.00",
              achieved_amount: yesterdayAmount.toFixed(2),
              remaining_amount: Math.max(0, 3 - yesterdayAmount).toFixed(2),
            },
            prayer_check_ins: [
              {
                id: "019a1284-9800-7000-8000-000000000803",
                prayer: "fajr",
                local_date: localDate,
                timezone_name: "Europe/Istanbul",
                pages: 3,
                reading_session_id: null,
                revision: 1,
                client_updated_at: "2026-08-27T03:20:00Z",
                device_id: activeSession.device.id,
                created_at: "2026-08-27T03:20:00Z",
                updated_at: "2026-08-27T03:20:00Z",
              },
            ],
            prayer_pages: 3,
            prayer_count: 1,
            automatic_sessions: 0,
            automatic_active_seconds: 0,
            automatic_pages: 0,
            automatic_ayahs: 0,
          };
        }
        return {
          local_date: localDate,
          state: "missed",
          has_reading: false,
          goal: {
            id: goalSnapshot().id,
            metric: "pages",
            target_amount: "3.00",
            achieved_amount: "0.00",
            remaining_amount: "3.00",
          },
          prayer_check_ins: [],
          prayer_pages: 0,
          prayer_count: 0,
          automatic_sessions: 0,
          automatic_active_seconds: 0,
          automatic_pages: 0,
          automatic_ayahs: 0,
        };
      });
      return route.fulfill({
        headers: { "Cache-Control": "private, no-store" },
        json: {
          local_date: "2026-08-28",
          timezone_name: "Europe/Istanbul",
          days: history,
        },
      });
    }
    if (url.pathname === "/api/v1/me/reading-sessions" && request.method() === "GET") {
      return route.fulfill({
        headers: { "Cache-Control": "private, no-store" },
        json: { results: readingSessions },
      });
    }
    if (
      url.pathname.startsWith("/api/v1/me/reading-sessions/") &&
      request.method() === "PATCH"
    ) {
      const payload = request.postDataJSON() as Record<string, unknown>;
      writes.push(payload);
      const sessionId = url.pathname.split("/").at(-1);
      const session = readingSessions.find((item) => item.id === sessionId);
      if (!session) return route.fulfill({ status: 404, json: { detail: "Not found" } });
      session.manual_metric = payload.metric;
      session.manual_amount = Number(payload.amount).toFixed(2);
      session.local_date = payload.local_date;
      session.revision = Number(session.revision) + 1;
      session.client_updated_at = payload.client_updated_at;
      return route.fulfill({ json: session });
    }
    if (
      url.pathname.startsWith("/api/v1/me/reading-sessions/") &&
      request.method() === "DELETE"
    ) {
      const sessionId = url.pathname.split("/").at(-1);
      const session = readingSessions.find((item) => item.id === sessionId);
      if (!session) return route.fulfill({ status: 404, json: { detail: "Not found" } });
      readingSessions = readingSessions.filter((item) => item.id !== sessionId);
      return route.fulfill({ json: { ...session, status: "discarded" } });
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
      const pages = Number(payload.pages || prayerPlan?.pages_per_prayer || 2);
      const checkIn = {
        id: payload.id,
        prayer: payload.prayer,
        local_date: payload.local_date,
        timezone_name: payload.timezone_name,
        pages,
        reading_session_id: payload.session_id,
        revision: 1,
        client_updated_at: payload.client_updated_at,
        device_id: activeSession.device.id,
        created_at: "2026-08-28T09:10:00Z",
        updated_at: "2026-08-28T09:10:00Z",
      };
      prayerCheckIns[String(payload.prayer)] = checkIn;
      achieved += pages;
      return route.fulfill({ status: 201, json: checkIn });
    }
    if (
      url.pathname.startsWith("/api/v1/me/prayer-reading-check-ins/") &&
      request.method() === "PATCH"
    ) {
      const payload = request.postDataJSON() as Record<string, unknown>;
      writes.push(payload);
      const checkInId = url.pathname.split("/").at(-1);
      const entry = Object.entries(prayerCheckIns).find(([, item]) => item.id === checkInId);
      if (!entry) return route.fulfill({ status: 404, json: { detail: "Not found" } });
      const previousPages = Number(entry[1].pages);
      entry[1].pages = Number(payload.pages);
      entry[1].revision = Number(entry[1].revision) + 1;
      entry[1].client_updated_at = payload.client_updated_at;
      achieved += Number(payload.pages) - previousPages;
      return route.fulfill({ json: entry[1] });
    }
    if (
      url.pathname.startsWith("/api/v1/me/prayer-reading-check-ins/") &&
      request.method() === "DELETE"
    ) {
      const checkInId = url.pathname.split("/").at(-1);
      const entry = Object.entries(prayerCheckIns).find(([, item]) => item.id === checkInId);
      if (entry) {
        achieved -= Number(entry[1].pages);
        delete prayerCheckIns[entry[0]];
      }
      return route.fulfill({ status: 204, body: "" });
    }
    return route.fallback();
  });

  return { plannerRanges, writes };
}

test("Today creates a daily goal and adds paper Mushaf progress", async ({ page }) => {
  const { writes } = await installReadingMocks(page);
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

test("prayer reading plan keeps partial and extra pages honest for each prayer", async ({ page }) => {
  const { writes } = await installReadingMocks(page);
  await page.goto("/");

  const plan = page.getByTestId("prayer-reading-plan");
  await expect(plan.getByRole("heading", { name: "Чтение после намаза" })).toBeVisible();
  await expect(plan.getByTestId("pages-per-prayer-value")).toHaveText("2");
  await expect(plan.getByText("≈ 61")).toBeVisible();
  await plan.getByRole("button", { name: "Сохранить план" }).click();

  await expect(plan.getByText("Сегодня выполнена норма после 0 из 5 намазов")).toBeVisible();
  const fajr = plan.locator(".prayer-reading-slot").filter({ hasText: "Фаджр" });
  await expect(fajr.getByText("0 из 2 стр.")).toBeVisible();
  await expect(fajr.getByRole("link", { name: "Открыть чтение после намаза Фаджр" }))
    .toHaveAttribute("href", /mode=after-prayer.*prayer=fajr/);

  await fajr.getByRole("button", { name: "Добавить вручную" }).click();
  await plan.getByLabel("Сколько прочитано после намаза Фаджр").fill("1");
  await plan.getByRole("button", { name: "Сохранить" }).click();

  await expect(plan.getByText("Сегодня выполнена норма после 0 из 5 намазов")).toBeVisible();
  await expect(plan.getByText("1 / 10 стр.")).toBeVisible();
  await expect(fajr.getByText("1 из 2 стр.")).toBeVisible();

  await fajr.getByRole("button", { name: "Изменить" }).click();
  await plan.getByLabel("Сколько прочитано после намаза Фаджр").fill("3");
  await plan.getByRole("button", { name: "Сохранить" }).click();

  await expect(plan.getByText("Сегодня выполнена норма после 1 из 5 намазов")).toBeVisible();
  await expect(plan.getByText("3 / 10 стр.")).toBeVisible();
  await expect(fajr.getByText("3 из 2 стр.")).toBeVisible();
  expect(writes[0]).toMatchObject({ pages_per_prayer: 2, base_revision: 0 });
  expect(writes[1]).toMatchObject({ prayer: "fajr", local_date: "2026-08-28", pages: 1 });
  expect(String(writes[1].id)).toMatch(/^[0-9a-f-]{36}$/);
  expect(String(writes[1].session_id)).toMatch(/^[0-9a-f-]{36}$/);
  expect(writes[2]).toMatchObject({ pages: 3, base_revision: 1 });

  await fajr.getByRole("button", { name: "Изменить" }).click();
  await plan.getByRole("button", { name: "Удалить отметку" }).click();
  await expect(plan.getByText("Сегодня выполнена норма после 0 из 5 намазов")).toBeVisible();
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

test("planner shows honest history and lets users correct manual entries", async ({ page }) => {
  const { plannerRanges, writes } = await installReadingMocks(page);
  page.on("dialog", (dialog) => dialog.accept());

  await page.goto("/ru/planner");

  const planner = page.getByTestId("reading-planner-dashboard");
  await expect(planner.getByRole("heading", { name: "Планировщик чтения" })).toBeVisible();
  await expect(planner.getByText("Пропуск не становится долгом", { exact: false })).toBeVisible();
  await expect(planner.locator(".planner-day.is-partial")).toHaveCount(1);

  await planner.locator(".planner-day.is-partial").click();
  const dayDetail = planner.getByTestId("planner-day-detail");
  await expect(dayDetail.getByText("1 / 3 стр.")).toBeVisible();
  await expect(dayDetail.getByText("1 / 5 · 3 стр.")).toBeVisible();

  const history = planner.getByTestId("reading-history");
  await expect(history.getByText("Добавлено вручную")).toBeVisible();
  await history.getByRole("button", { name: "Изменить" }).click();
  await history.getByLabel("Фактически прочитано").fill("2");
  await history.getByRole("button", { name: "Сохранить" }).click();

  await expect(history.getByText("2 стр.", { exact: true })).toBeVisible();
  expect(writes.at(-1)).toMatchObject({
    metric: "pages",
    amount: 2,
    local_date: "2026-08-27",
    base_revision: 1,
  });

  await history.getByRole("button", { name: "Удалить" }).click();
  await expect(history.getByText("За выбранный период записей чтения пока нет.")).toBeVisible();

  await planner.getByRole("button", { name: "7 дн." }).click();
  await expect.poll(() => plannerRanges.at(-1)).toBe(7);

  await page.setViewportSize({ width: 320, height: 760 });
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(
    await page.evaluate(() => document.documentElement.clientWidth),
  );
});
