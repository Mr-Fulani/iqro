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

function todaySnapshot(achieved: number, hasGoal: boolean, metric = "pages", target = 3) {
  const goal = hasGoal ? { ...goalSnapshot(), metric, target_amount: target.toFixed(2) } : null;
  return {
    local_date: "2026-08-28",
    timezone_name: "Europe/Istanbul",
    continue_reading: null,
    goal,
    progress: goal
      ? {
          goal_id: goal.id,
          local_date: "2026-08-28",
          metric,
          target_amount: target.toFixed(2),
          achieved_amount: achieved.toFixed(2),
          remaining_amount: Math.max(0, target - achieved).toFixed(2),
          is_completed: achieved >= target,
          completed_at: achieved >= target ? "2026-08-28T09:10:00Z" : null,
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
  let goalMetric = "pages";
  let goalTarget = 3;
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
        json: todaySnapshot(achieved, hasGoal, goalMetric, goalTarget),
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
      goalMetric = String(payload.metric);
      goalTarget = Number(payload.target_amount);
      return route.fulfill({ status: 201, json: { ...goalSnapshot(), metric: goalMetric, target_amount: goalTarget.toFixed(2) } });
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
          goal: todaySnapshot(achieved, hasGoal, goalMetric, goalTarget).goal,
          target_amount: goalTarget.toFixed(2), achieved_amount: achieved.toFixed(2),
          remaining_amount: Math.max(0, goalTarget - achieved).toFixed(2),
          targets: Object.fromEntries(["fajr", "dhuhr", "asr", "maghrib", "isha"].map((prayer, index) => {
            const scale = goalMetric === "minutes" ? 100 : 1;
            const units = Math.round(goalTarget * scale);
            return [prayer, ((Math.floor(units / 5) + (index < units % 5 ? 1 : 0)) / scale).toFixed(2)];
          })),
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
      const existingRevision = Number(prayerPlan?.revision || 0);
      prayerPlan = {
        id: "019a1284-9800-7000-8000-000000000701",
        pages_per_prayer: payload.pages_per_prayer,
        notifications_enabled: payload.notifications_enabled,
        timezone_name: payload.timezone_name,
        revision: existingRevision + 1,
        client_updated_at: payload.client_updated_at,
        device_id: activeSession.device.id,
        created_at: "2026-08-28T09:00:00Z",
        updated_at: "2026-08-28T09:00:00Z",
      };
      return route.fulfill({ status: existingRevision ? 200 : 201, json: prayerPlan });
    }
    if (url.pathname === "/api/v1/me/prayer-reading-check-ins" && request.method() === "POST") {
      const payload = request.postDataJSON() as Record<string, unknown>;
      writes.push(payload);
      const amount = Number(payload.amount ?? payload.pages ?? 2);
      const metric = String(payload.metric || "pages");
      const pages = metric === "pages" ? amount : 0;
      const checkIn = {
        id: payload.id,
        prayer: payload.prayer,
        local_date: payload.local_date,
        timezone_name: payload.timezone_name,
        pages, metric, amount: amount.toFixed(2),
        reading_session_id: payload.session_id,
        revision: 1,
        client_updated_at: payload.client_updated_at,
        device_id: activeSession.device.id,
        created_at: "2026-08-28T09:10:00Z",
        updated_at: "2026-08-28T09:10:00Z",
      };
      prayerCheckIns[String(payload.prayer)] = checkIn;
      achieved += amount;
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
      const previousPages = Number(entry[1].amount);
      const amount = Number(payload.amount ?? payload.pages);
      entry[1].amount = amount.toFixed(2);
      entry[1].metric = payload.metric || "pages";
      entry[1].pages = entry[1].metric === "pages" ? amount : 0;
      entry[1].revision = Number(entry[1].revision) + 1;
      entry[1].client_updated_at = payload.client_updated_at;
      achieved += amount - previousPages;
      return route.fulfill({ json: entry[1] });
    }
    if (
      url.pathname.startsWith("/api/v1/me/prayer-reading-check-ins/") &&
      request.method() === "DELETE"
    ) {
      const checkInId = url.pathname.split("/").at(-1);
      const entry = Object.entries(prayerCheckIns).find(([, item]) => item.id === checkInId);
      if (entry) {
        achieved -= Number(entry[1].amount);
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
  await expect(today.getByRole("progressbar", { name: "Прогресс чтения" })).toHaveAttribute("aria-valuenow", "100");
  expect(writes[1]).toMatchObject({ metric: "pages", amount: 3 });
  expect(String(writes[1].id)).toMatch(/^[0-9a-f-]{36}$/);
});

test("home Today card grows the date palm from the app's planner window", async ({ page }) => {
  const { plannerRanges } = await installReadingMocks(page);
  await page.goto("/");

  const today = page.getByTestId("today-reading");
  const palm = today.getByTestId("palm-growth");
  // Yesterday's manual page is the only reading in the window: a sprout that
  // rests until today's reading.
  await expect(palm).toHaveAttribute("data-stage", "sprout");
  await expect(palm).toHaveAttribute("data-mood", "resting");
  expect(plannerRanges).toContain(90);
  await expect(palm.getByText("Росток", { exact: true })).toBeVisible();
  await expect(palm.getByText("Дальше: Саженец", { exact: true })).toBeVisible();
  // A 320px card on a 1x screen takes the 480w file, not the 960w one.
  await expect
    .poll(() => palm.locator("img").evaluate((image: HTMLImageElement) => image.currentSrc))
    .toMatch(/\/images\/palm\/palm-stage-1-480\.webp$/);

  const restingText = palm.getByText("Пальма отдыхает в тени", { exact: false });
  await expect(restingText).toBeHidden();
  await palm.getByRole("button", { name: "Как растёт пальма" }).click();
  await expect(restingText).toBeVisible();
  await expect(palm.getByText("День чтения — +1, выполненная цель — +2", { exact: false })).toBeVisible();

  await today.getByLabel("Считать норму в").selectOption("pages");
  await today.getByLabel("Норма на день").fill("3");
  await today.getByRole("button", { name: "Создать норму" }).click();
  await today.getByRole("button", { name: "Добавить вручную" }).click();
  await today.getByLabel("Прочитано — стр.").fill("3");
  await today.getByRole("button", { name: "Добавить к сегодняшнему прогрессу" }).click();

  // A completed goal is two points: 3 of the 6 a seedling needs, 40% of the way.
  await expect(palm).toHaveAttribute("data-mood", "flourishing");
  await expect(palm).toHaveAttribute("data-stage", "sprout");
  await expect(palm.getByRole("progressbar", { name: "Дальше: Саженец" })).toHaveAttribute("aria-valuenow", "40");

  await page.setViewportSize({ width: 320, height: 760 });
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(
    await page.evaluate(() => document.documentElement.clientWidth),
  );
});

test("a new palm stage grows in; reduced motion keeps it still", async ({ page }) => {
  await installReadingMocks(page);
  let achieved = 0;
  await page.route(
    (url) => url.pathname === "/api/v1/me/today",
    (route) => route.fulfill({ json: todaySnapshot(achieved, true) }),
  );
  await page.route(
    (url) => url.pathname === "/api/v1/me/reading-planner",
    (route) =>
      route.fulfill({
        json: {
          local_date: "2026-08-28",
          timezone_name: "Europe/Istanbul",
          days: [23, 24, 25, 26, 27].map((date) => ({
            local_date: `2026-08-${date}`,
            state: "partial",
            has_reading: true,
            goal: null,
            prayer_check_ins: [],
            prayer_pages: 0,
            prayer_count: 0,
            automatic_sessions: 0,
            automatic_active_seconds: 0,
            automatic_pages: 0,
            automatic_ayahs: 0,
          })),
        },
      }),
  );
  await page.goto("/");

  const palm = page.getByTestId("palm-growth");
  await expect(palm).toHaveAttribute("data-stage", "sprout");
  await expect(palm.locator("img.is-growing")).toHaveCount(0);

  // Five reading days and today's first page make six points: a seedling.
  achieved = 1;
  await page.evaluate(() => window.dispatchEvent(new Event("quran-reading-progress-changed")));
  await expect(palm).toHaveAttribute("data-stage", "seedling");
  const photo = palm.locator("img.is-growing");
  await expect(photo).toHaveAttribute("src", "/images/palm/palm-stage-2-480.webp");
  expect(await photo.evaluate((image) => getComputedStyle(image).animationName)).toBe("today-palm-grow");

  await page.emulateMedia({ reducedMotion: "reduce" });
  expect(await photo.evaluate((image) => getComputedStyle(image).animationName)).toBe("none");
});

test("today's progress does not wait for the palm and leaves with the reader", async ({ page }) => {
  await installReadingMocks(page);
  await page.route(
    (url) => url.pathname === "/api/v1/me/today",
    (route) => route.fulfill({ json: todaySnapshot(1, true) }),
  );
  let releasePlanner = () => {};
  const plannerHeld = new Promise<void>((resolve) => {
    releasePlanner = resolve;
  });
  await page.route(
    (url) => url.pathname === "/api/v1/me/reading-planner",
    async (route) => {
      await plannerHeld;
      await route.fallback();
    },
  );
  await page.route("**/api/web-auth/logout", (route) => route.fulfill({ status: 204, body: "" }));
  await page.goto("/");

  const today = page.getByTestId("today-reading");
  await expect(today.getByText("1 / 3 стр.")).toBeVisible();
  await expect(today.getByTestId("palm-growth")).toHaveCount(0);
  releasePlanner();
  await expect(today.getByTestId("palm-growth")).toBeVisible();

  await page.getByRole("button", { name: "Выйти" }).click();
  await expect(today.getByRole("button", { name: "Создать норму" })).toBeVisible();
  await expect(today.getByTestId("palm-growth")).toHaveCount(0);
  await expect(today.getByText("1 / 3 стр.")).toHaveCount(0);
});

test("palm photographs load only with the palm card", async ({ page }) => {
  const palmImages: string[] = [];
  page.on("request", (request) => {
    if (request.url().includes("/images/palm/")) palmImages.push(request.url());
  });
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ status: 401 }));
  await page.goto("/ru");

  const today = page.getByTestId("today-reading");
  await expect(today.getByRole("button", { name: "Создать норму" })).toBeVisible();
  await expect(today.getByTestId("palm-growth")).toHaveCount(0);
  await page.goto("/ru/quran");
  await page.waitForLoadState("networkidle");
  expect(palmImages).toEqual([]);
});

for (const [metric, target, first, unit] of [
  ["pages", "7", "2", "стр."], ["minutes", "1.25", "0,25", "мин."], ["ayahs", "3", "1", "аятов"],
] as const) {
  test(`one daily goal distributes ${metric} and refreshes shared progress`, async ({ page }) => {
    const { writes } = await installReadingMocks(page);
    await page.goto("/ru/planner");
    const today = page.getByTestId("today-reading");
    const plan = page.getByTestId("prayer-reading-plan");
    await today.getByLabel("Считать норму в").selectOption(metric);
    await today.getByLabel("Норма на день").fill(target);
    await today.getByRole("button", { name: "Создать норму" }).click();
    await expect(plan.getByText(`0 / ${target.replace(".", ",")} ${unit}`)).toBeVisible();
    await expect(plan.getByRole("button", { name: "Сохранить план" })).toHaveCount(0);
    const fajr = plan.locator(".prayer-reading-slot").filter({ hasText: "Фаджр" });
    await expect(fajr.getByText(`0 ${unit} · норма ${first} ${unit}`)).toBeVisible();
    await fajr.getByRole("button", { name: "Добавить вручную" }).click();
    await plan.getByLabel(`Сколько прочитано после намаза Фаджр — ${unit}`).fill(target);
    await plan.getByRole("button", { name: "Сохранить", exact: true }).click();
    await expect(today.getByText("Норма на сегодня выполнена")).toBeVisible();
    await expect(plan.getByText(`${target.replace(".", ",")} / ${target.replace(".", ",")} ${unit}`)).toBeVisible();
    expect(writes.at(-1)).toMatchObject({ prayer: "fajr", metric, amount: Number(target) });
    await fajr.getByRole("button", { name: "Изменить", exact: true }).click();
    await plan.getByRole("button", { name: "Удалить отметку" }).click();
    await expect(today.getByText(`0 / ${target.replace(".", ",")} ${unit}`)).toBeVisible();
    await page.setViewportSize({ width: 320, height: 760 });
    expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(
      await page.evaluate(() => document.documentElement.clientWidth),
    );
  });
}

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
  await expect(dayDetail.getByText("1 / 5", { exact: true })).toBeVisible();

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
