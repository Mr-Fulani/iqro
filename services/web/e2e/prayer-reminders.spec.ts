import { expect, Page, test } from "@playwright/test";

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

const method = {
  id: "01992d87-6c00-7000-8000-000000000601",
  code: "muslim-world-league",
  available: true,
  name: { ar: "رابطة العالم الإسلامي", en: "Muslim World League", ru: "Всемирная исламская лига" },
  description: { ar: "", en: "", ru: "" },
  checksum_sha256: "a".repeat(64),
};

const dubaiMethod = {
  id: "01992d87-6c00-7000-8000-000000000600",
  code: "dubai",
  available: true,
  name: { ar: "دبي", en: "Dubai", ru: "Дубай" },
  description: { ar: "", en: "", ru: "" },
  checksum_sha256: "d".repeat(64),
};

async function installSession(page: Page) {
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ json: activeSession }));
}

test("prayer profile persists the complete revisioned calculation preferences", async ({ page }) => {
  await installSession(page);
  const captured: {
    profile?: Record<string, unknown>;
    calculations: Array<Record<string, unknown>>;
  } = { calculations: [] };

  await page.route("**/api/v1/**", async (route) => {
    const request = route.request();
    const url = new URL(request.url());
    if (url.pathname === "/api/v1/prayer/methods") {
      await new Promise((resolve) => setTimeout(resolve, 100));
      return route.fulfill({
        json: {
          catalog_version: "2026.1",
          configuration_schema_version: 1,
          checksum_sha256: "b".repeat(64),
          methods: [dubaiMethod, method],
        },
      });
    }
    if (url.pathname === "/api/v1/me/prayer-profile" && request.method() === "GET") {
      return route.fulfill({
        status: 404,
        json: { code: "prayer_profile_not_found", detail: "Prayer profile not found." },
      });
    }
    if (url.pathname === "/api/v1/me/prayer-profile" && request.method() === "PUT") {
      captured.profile = request.postDataJSON() as Record<string, unknown>;
      return route.fulfill({
        json: {
          id: "01992d87-6c00-7000-8000-000000000602",
          method_config: {
            id: method.id,
            code: method.code,
            catalog_version: "2026.1",
            checksum_sha256: method.checksum_sha256,
          },
          method_available: true,
          asr_method: "standard",
          high_latitude_rule: "seventh_of_night",
          polar_resolution: "aqrab_balad",
          adjustments: {
            fajr: -3,
            sunrise: 0,
            dhuhr: 0,
            asr: 0,
            maghrib: 0,
            isha: 0,
          },
          timezone_mode: "fixed",
          fixed_timezone: "Europe/Istanbul",
          revision: 1,
          client_updated_at: "2026-08-23T16:00:00Z",
          device_id: activeSession.device.id,
          created_at: "2026-08-23T16:00:00Z",
          updated_at: "2026-08-23T16:00:00Z",
        },
      });
    }
    if (url.pathname === "/api/v1/prayer/calculate") {
      const calculation = request.postDataJSON() as Record<string, unknown>;
      captured.calculations.push(calculation);
      return route.fulfill({
        json: {
          date: "2026-08-23",
          timezone: calculation.timezone,
          method: { id: method.id, code: method.code, name: method.name },
          times: {},
        },
      });
    }
    return route.fulfill({ status: 404, json: { detail: `Unhandled ${url.pathname}` } });
  });

  await page.goto("/prayer");
  await page.getByLabel("Метод расчёта").selectOption(method.id);
  await page.getByLabel("Высокие широты").selectOption("seventh_of_night");
  await page.getByLabel("Полярная зона").selectOption("aqrab_balad");
  await page.getByLabel("Часовой пояс профиля").selectOption("fixed");
  await page.getByLabel("Фиксированный timezone").fill("Europe/Istanbul");
  await page.getByLabel("Широта (Latitude)").fill("40.7128");
  await page.getByLabel("Долгота (Longitude)").fill("-74.0060");
  await page.getByLabel("Часовой пояс (IANA)").fill("America/New_York");
  await page.getByLabel("Фаджр", { exact: true }).fill("-3");
  await page.getByRole("button", { name: "Сохранить профиль" }).click();

  await expect(page.getByText("Настройки сохранены, ревизия 1.")).toBeVisible();
  expect(captured.profile).toMatchObject({
    base_revision: 0,
    method_config_id: method.id,
    method_checksum_sha256: method.checksum_sha256,
    high_latitude_rule: "seventh_of_night",
    polar_resolution: "aqrab_balad",
    adjustments: { fajr: -3 },
    timezone_mode: "fixed",
    fixed_timezone: "Europe/Istanbul",
  });
  expect(captured.profile?.client_updated_at).toEqual(expect.any(String));

  await page.reload();
  await expect(page.getByLabel("Метод расчёта")).toHaveValue(method.id);
  await expect(page.getByLabel("Широта (Latitude)")).toHaveValue("40.7128");
  await expect(page.getByLabel("Долгота (Longitude)")).toHaveValue("-74.0060");
  await expect(page.getByLabel("Часовой пояс (IANA)")).toHaveValue("America/New_York");
  await expect(page.getByLabel("Быстрый выбор города")).toHaveValue("custom");
  await expect.poll(() => captured.calculations.at(-1)).toMatchObject({
    timezone: "America/New_York",
    location: { latitude: 40.7128, longitude: -74.006 },
  });
});

test("prayer switches and Quran reminders use the strict API shape", async ({
  page,
}) => {
  await installSession(page);
  await page.addInitScript(() => {
    window.localStorage.setItem(
      "quran_prayer_location_v1:00000000-0000-7000-8000-000000000102",
      JSON.stringify({
        latitude: "41.0082",
        longitude: "28.9784",
        timezone: "Europe/Istanbul",
        updated_at: "2026-08-23T16:00:00Z",
      }),
    );
    const subscription = {
      endpoint: "https://fcm.googleapis.com/fcm/send/prayer-switch-test",
      expirationTime: null,
      toJSON: () => ({
        endpoint: "https://fcm.googleapis.com/fcm/send/prayer-switch-test",
        keys: { p256dh: "test-p256dh", auth: "test-auth" },
      }),
    };
    Object.defineProperty(window, "Notification", {
      configurable: true,
      value: { permission: "granted", requestPermission: async () => "granted" },
    });
    Object.defineProperty(window, "PushManager", {
      configurable: true,
      value: function PushManager() {},
    });
    Object.defineProperty(navigator, "serviceWorker", {
      configurable: true,
      value: {
        getRegistration: async () => ({
          pushManager: { getSubscription: async () => subscription },
        }),
      },
    });
    Object.defineProperty(navigator, "geolocation", {
      configurable: true,
      value: {
        getCurrentPosition: (resolve: PositionCallback) =>
          resolve({ coords: { latitude: 41.0082, longitude: 28.9784 } } as GeolocationPosition),
      },
    });
  });
  const captured: {
    creates: Array<Record<string, unknown>>;
    patches: Array<Record<string, unknown>>;
    deletes: Array<Record<string, unknown>>;
  } = { creates: [], patches: [], deletes: [] };
  let prayerLocationPayload: Record<string, unknown> | null = null;
  let currentReminder: Record<string, unknown> | null = null;

  await page.route("**/api/v1/**", async (route) => {
    const request = route.request();
    const url = new URL(request.url());
    if (url.pathname.includes("/reading-position/")) {
      return route.fulfill({ status: 404, json: { detail: "Not found." } });
    }
    if (url.pathname === "/api/v1/me/bookmarks") {
      return route.fulfill({ json: { next: null, previous: null, results: [] } });
    }
    if (url.pathname === "/api/v1/feedback/tickets") {
      return route.fulfill({ json: { next: null, previous: null, results: [] } });
    }
    if (url.pathname === "/api/v1/me/web-push" && request.method() === "GET") {
      return route.fulfill({
        json: {
          available: true,
          enabled: true,
          vapid_public_key: "AQID",
          timezone_name: "Europe/Istanbul",
          locale: "ru",
          prayer_location_configured: false,
          prayer_profile_configured: true,
          supported_reminder_types: ["prayer", "quran_reading", "quran_review"],
        },
      });
    }
    if (url.pathname === "/api/v1/me/web-push" && request.method() === "PUT") {
      prayerLocationPayload = request.postDataJSON() as Record<string, unknown>;
      return route.fulfill({
        json: {
          available: true,
          enabled: true,
          vapid_public_key: "AQID",
          timezone_name: "Europe/Istanbul",
          locale: "ru",
          prayer_location_configured: true,
          prayer_profile_configured: true,
          supported_reminder_types: ["prayer", "quran_reading", "quran_review"],
        },
      });
    }
    if (url.pathname === "/api/v1/me/reminders" && request.method() === "GET") {
      return route.fulfill({
        json: {
          mode: "full_snapshot",
          authoritative: true,
          generated_at: "2026-08-23T16:00:00Z",
          count: currentReminder ? 1 : 0,
          reminders: currentReminder ? [currentReminder] : [],
        },
      });
    }
    if (url.pathname === "/api/v1/me/reminders" && request.method() === "POST") {
      const payload = request.postDataJSON() as Record<string, unknown>;
      captured.creates.push(payload);
      const reviewInput = payload.review_target as
        | { start_ayah_id: string; end_ayah_id: string }
        | undefined;
      currentReminder = {
        id: payload.id,
        reminder_type: payload.reminder_type,
        schedule: payload.schedule,
        review_target: reviewInput
          ? {
              start: { id: reviewInput.start_ayah_id, surah_number: 1, ayah_number: 1 },
              end: { id: reviewInput.end_ayah_id, surah_number: 1, ayah_number: 2 },
            }
          : null,
        weekdays_mask: payload.weekdays_mask,
        timezone: payload.timezone,
        delivery_mode: "local",
        signal: payload.signal,
        is_enabled: payload.is_enabled,
        revision: 1,
        client_updated_at: payload.client_updated_at,
        device_id: activeSession.device.id,
        deleted_at: null,
        created_at: "2026-08-23T16:00:00Z",
        updated_at: "2026-08-23T16:00:00Z",
      };
      return route.fulfill({ status: 201, json: currentReminder });
    }
    if (url.pathname.startsWith("/api/v1/me/reminders/") && request.method() === "PATCH") {
      const payload = request.postDataJSON() as Record<string, unknown>;
      captured.patches.push(payload);
      currentReminder = {
        ...currentReminder,
        ...payload,
        revision: Number(currentReminder?.revision || 1) + 1,
      };
      return route.fulfill({ json: currentReminder });
    }
    if (url.pathname.startsWith("/api/v1/me/reminders/") && request.method() === "DELETE") {
      captured.deletes.push(request.postDataJSON() as Record<string, unknown>);
      currentReminder = {
        ...currentReminder,
        schedule: null,
        review_target: null,
        is_enabled: false,
        deleted_at: "2026-08-23T16:10:00Z",
        revision: Number(currentReminder?.revision || 1) + 1,
      };
      return route.fulfill({ json: currentReminder });
    }
    if (url.pathname === "/api/v1/quran/editions/madani-hafs/surahs") {
      return route.fulfill({
        json: [
          {
            id: "01992d87-6c00-7000-8000-000000000701",
            number: 1,
            name_ar: "الفاتحة",
            name_en: "Al-Fatihah",
            name_ru: "Аль-Фатиха",
            revelation_type: "meccan",
            ayah_count: 7,
            first_page: 1,
          },
        ],
      });
    }
    if (url.pathname === "/api/v1/quran/editions/madani-hafs/surahs/1/ayahs") {
      return route.fulfill({
        json: [1, 2].map((number) => ({
          id: `01992d87-6c00-7000-8000-00000000070${number + 1}`,
          edition_code: "madani-hafs",
          content_version: "1.0.2",
          surah_number: 1,
          number,
          text_uthmani: "نص",
          juz_number: 1,
          hizb_number: 1,
          rub_el_hizb_number: 1,
          pages: [1],
        })),
      });
    }
    return route.fulfill({ status: 404, json: { detail: `Unhandled ${url.pathname}` } });
  });

  await page.goto("/profile");
  const reminders = page
    .getByRole("heading", { name: "Напоминания" })
    .locator("xpath=ancestor::section");
  await expect(reminders.getByText(/Местоположение настроено/)).toBeVisible();
  await expect(reminders.getByLabel("Включено")).toHaveCount(0);
  await expect(
    reminders.locator(".prayer-reminder-panel > .surface-head .status-chip"),
  ).toHaveCount(0);
  const repeatSelect = reminders.getByLabel("Повторение");
  await expect(repeatSelect).toHaveValue("every_day");
  await repeatSelect.selectOption("custom");
  await expect(reminders.getByLabel("Пн")).toBeVisible();
  await repeatSelect.selectOption("every_day");
  const maghribSwitch = reminders.getByRole("switch", { name: /^Магриб:/ });
  await expect(maghribSwitch).toHaveAttribute("aria-checked", "false");
  await maghribSwitch.click();
  await expect(maghribSwitch).toHaveAttribute("aria-checked", "true");

  expect(prayerLocationPayload).toMatchObject({
    prayer_location: { latitude: 41.0082, longitude: 28.9784 },
  });
  expect(captured.creates[0]).toMatchObject({
    base_revision: 0,
    reminder_type: "prayer",
    schedule: { kind: "prayer", prayer_event: "maghrib", prayer_offset_minutes: 0 },
    weekdays_mask: 127,
    timezone: { mode: "device_local" },
    signal: "sound",
    is_enabled: true,
  });
  await maghribSwitch.click();
  await expect(maghribSwitch).toHaveAttribute("aria-checked", "false");
  expect(captured.patches[0]).toMatchObject({ base_revision: 1, is_enabled: false });

  await reminders.getByLabel("Тип").selectOption("quran_review");
  await expect(reminders.getByLabel("Начальный аят").locator("option")).toHaveCount(2);
  await reminders.getByLabel("Начальный аят").selectOption({ index: 0 });
  await reminders.getByLabel("Конечный аят").selectOption({ index: 1 });
  await reminders.getByRole("button", { name: "Создать напоминание" }).click();

  const reviewRow = reminders
    .getByText("Повторение аятов", { exact: true })
    .locator("xpath=ancestor::div[contains(@class, 'track-row')]");
  await expect(reviewRow).toBeVisible();

  expect(captured.creates[1]).toMatchObject({
    reminder_type: "quran_review",
    schedule: { kind: "local_time", local_time: "07:30:00" },
    review_target: {
      start_ayah_id: "01992d87-6c00-7000-8000-000000000702",
      end_ayah_id: "01992d87-6c00-7000-8000-000000000703",
    },
  });
  await expect(reviewRow.getByText(/Каждый день/)).toBeVisible();
  await expect(
    reviewRow.getByText("Включено", { exact: true }),
  ).toBeVisible();
  await reminders.getByRole("button", { name: "Удалить" }).click();
  expect(captured.deletes[0]).toMatchObject({ base_revision: 1 });
});

test("browser push waits for the first service worker to become active", async ({ page }) => {
  await installSession(page);
  await page.addInitScript(() => {
    const subscription = {
      endpoint: "https://fcm.googleapis.com/fcm/send/browser-test",
      expirationTime: null,
      toJSON: () => ({
        endpoint: "https://fcm.googleapis.com/fcm/send/browser-test",
        keys: { p256dh: "test-p256dh", auth: "test-auth" },
      }),
      unsubscribe: async () => true,
    };
    let currentSubscription: typeof subscription | null = null;
    const activeRegistration = {
      active: {},
      pushManager: {
        getSubscription: async () => currentSubscription,
        subscribe: async () => {
          currentSubscription = subscription;
          return subscription;
        },
      },
    };
    const installingRegistration = {
      active: null,
      pushManager: {
        getSubscription: async () => {
          throw new Error("PushManager was used before the service worker became active");
        },
      },
    };

    const notificationMock = {
      permission: "default",
      requestPermission: async () => {
        notificationMock.permission = "granted";
        return "granted";
      },
    };
    Object.defineProperty(window, "Notification", {
      configurable: true,
      value: notificationMock,
    });
    Object.defineProperty(window, "PushManager", {
      configurable: true,
      value: function PushManager() {},
    });
    Object.defineProperty(navigator, "serviceWorker", {
      configurable: true,
      value: {
        register: async () => installingRegistration,
        ready: Promise.resolve(activeRegistration),
        getRegistration: async () => activeRegistration,
      },
    });
  });

  let pushPayload: Record<string, unknown> | null = null;
  await page.route("**/api/v1/**", async (route) => {
    const request = route.request();
    const url = new URL(request.url());
    if (url.pathname.includes("/reading-position/")) {
      return route.fulfill({ status: 404, json: { detail: "Not found." } });
    }
    if (url.pathname === "/api/v1/me/bookmarks") {
      return route.fulfill({ json: { next: null, previous: null, results: [] } });
    }
    if (url.pathname === "/api/v1/feedback/tickets") {
      return route.fulfill({ json: { next: null, previous: null, results: [] } });
    }
    if (url.pathname === "/api/v1/me/reminders") {
      return route.fulfill({
        json: {
          mode: "full_snapshot",
          authoritative: true,
          generated_at: "2026-08-23T16:00:00Z",
          count: 0,
          reminders: [],
        },
      });
    }
    if (url.pathname === "/api/v1/me/web-push" && request.method() === "GET") {
      return route.fulfill({
        json: {
          available: true,
          enabled: false,
          vapid_public_key: "AQID",
          timezone_name: null,
          locale: null,
          prayer_location_configured: false,
          prayer_profile_configured: true,
          supported_reminder_types: ["prayer", "quran_reading", "quran_review"],
        },
      });
    }
    if (url.pathname === "/api/v1/me/web-push" && request.method() === "PUT") {
      pushPayload = request.postDataJSON() as Record<string, unknown>;
      return route.fulfill({
        json: {
          available: true,
          enabled: true,
          vapid_public_key: "AQID",
          timezone_name: "Europe/Istanbul",
          locale: "ru",
          prayer_location_configured: false,
          prayer_profile_configured: true,
          supported_reminder_types: ["prayer", "quran_reading", "quran_review"],
        },
      });
    }
    return route.fulfill({ status: 404, json: { detail: `Unhandled ${url.pathname}` } });
  });

  await page.goto("/profile");
  const reminders = page
    .getByRole("heading", { name: "Напоминания" })
    .locator("xpath=ancestor::section");
  await reminders.getByRole("button", { name: "Разрешить уведомления" }).click();

  await expect(reminders.getByText("Уведомления включены на этом устройстве.")).toBeVisible();
  await expect(reminders.getByText("Подключены", { exact: true })).toBeVisible();
  expect(pushPayload).toMatchObject({
    endpoint: "https://fcm.googleapis.com/fcm/send/browser-test",
    keys: { p256dh: "test-p256dh", auth: "test-auth" },
    expiration_time: null,
    locale: "ru",
  });
  await expect(reminders.getByRole("button", { name: "Проверить сейчас" })).toHaveCount(0);
  await expect(reminders.getByRole("button", { name: "Отключить уведомления" })).toBeVisible();
});

test("browser push status follows the subscription on the current device", async ({ page }) => {
  await installSession(page);
  await page.addInitScript(() => {
    Object.defineProperty(window, "Notification", {
      configurable: true,
      value: {
        permission: "granted",
        requestPermission: async () => "granted",
      },
    });
    Object.defineProperty(window, "PushManager", {
      configurable: true,
      value: function PushManager() {},
    });
    Object.defineProperty(navigator, "serviceWorker", {
      configurable: true,
      value: {
        getRegistration: async () => ({
          pushManager: { getSubscription: async () => null },
        }),
      },
    });
  });

  await page.route("**/api/v1/**", async (route) => {
    const request = route.request();
    const url = new URL(request.url());
    if (url.pathname.includes("/reading-position/")) {
      return route.fulfill({ status: 404, json: { detail: "Not found." } });
    }
    if (url.pathname === "/api/v1/me/bookmarks") {
      return route.fulfill({ json: { next: null, previous: null, results: [] } });
    }
    if (url.pathname === "/api/v1/feedback/tickets") {
      return route.fulfill({ json: { next: null, previous: null, results: [] } });
    }
    if (url.pathname === "/api/v1/me/reminders") {
      return route.fulfill({
        json: {
          mode: "full_snapshot",
          authoritative: true,
          generated_at: "2026-08-23T16:00:00Z",
          count: 0,
          reminders: [],
        },
      });
    }
    if (url.pathname === "/api/v1/me/web-push" && request.method() === "GET") {
      return route.fulfill({
        json: {
          available: true,
          enabled: true,
          vapid_public_key: "AQID",
          timezone_name: "Europe/Istanbul",
          locale: "ru",
          prayer_location_configured: true,
          prayer_profile_configured: true,
          supported_reminder_types: ["prayer", "quran_reading", "quran_review"],
        },
      });
    }
    return route.fulfill({ status: 404, json: { detail: `Unhandled ${url.pathname}` } });
  });

  await page.goto("/profile");
  const reminders = page
    .getByRole("heading", { name: "Напоминания" })
    .locator("xpath=ancestor::section");
  await expect(reminders.getByText("Не подключены", { exact: true })).toBeVisible();
  await expect(
    reminders.getByRole("button", { name: "Разрешить уведомления" }),
  ).toBeVisible();
  await expect(
    reminders.getByRole("button", { name: "Отключить уведомления" }),
  ).toHaveCount(0);
});
