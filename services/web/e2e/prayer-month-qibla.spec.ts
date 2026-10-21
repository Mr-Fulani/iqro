import { readFileSync } from "node:fs";
import { expect, Page, test } from "@playwright/test";
import { magneticDeclination } from "../lib/geomag.ts";
import { qiblaBearing } from "../lib/qibla.ts";

type AppParityCase = { id: string; utc_minutes: number[][] };

// Month times produced by the mobile app's own engine (scripts/prayer-app-parity.dart).
const appParity = JSON.parse(
  readFileSync(new URL("../lib/prayer-engine.app-parity.json", import.meta.url), "utf8"),
) as { cases: AppParityCase[] };
const moscowJune = appParity.cases.find((item) => item.id === "moscow-mwl-hanafi")!;

const method = {
  id: "01992d87-6c00-7000-8000-000000000601",
  code: "muslim-world-league",
  available: true,
  name: { ar: "رابطة العالم الإسلامي", en: "Muslim World League", ru: "Всемирная исламская лига" },
  description: { ar: "", en: "", ru: "" },
  parameters: {
    fajr_angle: "18.00",
    isha: { type: "angle", angle: "17.00", interval_minutes: null, ramadan_interval_minutes: null },
    method_adjustments: { fajr: 0, sunrise: 0, dhuhr: 1, asr: 0, maghrib: 0, isha: 0 },
  },
  high_latitude_rules: { supported: ["middle_of_night"], default: "middle_of_night" },
  polar_resolutions: { supported: ["unresolved"], default: "unresolved" },
  checksum_sha256: "a".repeat(64),
};

async function mockPrayerApi(
  page: Page,
  {
    algorithmVersion = "4.4.4-quran.1-adhanpy.1.0.5",
    failTimezone,
  }: { algorithmVersion?: string; failTimezone?: string } = {},
) {
  const calculations: Array<Record<string, unknown>> = [];
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ status: 401 }));
  await page.route("**/api/v1/**", async (route) => {
    const request = route.request();
    const url = new URL(request.url());
    if (url.pathname === "/api/v1/prayer/methods") {
      return route.fulfill({
        json: {
          catalog_version: "2026.1",
          configuration_schema_version: 1,
          algorithm: { id: "adhan-js-python-adapter", version: algorithmVersion, upstream: "adhan" },
          timezone_database_version: "2026a",
          checksum_sha256: "b".repeat(64),
          methods: [method],
        },
      });
    }
    if (url.pathname === "/api/v1/prayer/calculate") {
      const calculation = request.postDataJSON() as Record<string, unknown>;
      calculations.push(calculation);
      if (calculation.timezone === failTimezone) {
        return route.fulfill({ status: 503, json: { detail: "Prayer calculation is unavailable." } });
      }
      return route.fulfill({
        json: {
          date: calculation.date,
          timezone: calculation.timezone,
          method: { id: method.id, code: method.code, name: method.name },
          times: {},
        },
      });
    }
    return route.fulfill({ status: 404, json: { detail: `Unhandled ${url.pathname}` } });
  });
  return calculations;
}

function moscowWallClock(epochMinutes: number): string {
  return new Intl.DateTimeFormat("ru-RU", {
    hour: "2-digit",
    minute: "2-digit",
    timeZone: "Europe/Moscow",
  }).format(epochMinutes * 60_000);
}

test("prayer page shows the Qibla and a month calendar that matches the app", async ({ page }) => {
  await mockPrayerApi(page);
  await page.goto("/ru/prayer");
  // The first automatic calculation (Makkah by default) finishes restoring the form.
  await expect(page.getByTestId("prayer-qibla-bearing")).toHaveText("Вы у Каабы — молитесь лицом к ней");
  await expect(page.getByTestId("prayer-qibla-arrow")).toHaveCount(0);
  await page.getByLabel("Быстрый выбор города").selectOption({ label: "Москва (Россия)" });
  await page.getByLabel("Дата расчёта").fill("2026-06-15");
  await page.getByLabel("Мазхаб для времени Аср").selectOption("hanafi");
  await page.getByRole("button", { name: "Рассчитать расписание" }).click();

  const qibla = page.getByTestId("prayer-qibla");
  await expect(qibla.getByRole("heading", { name: "Направление Киблы" })).toBeVisible();
  await expect(page.getByTestId("prayer-qibla-bearing")).toHaveText("176° от географического севера");
  await expect(qibla.getByRole("img", { name: "Компас: Кибла на 176° от севера" })).toBeVisible();
  await expect(page.getByTestId("prayer-qibla-arrow")).toHaveAttribute(
    "transform",
    /^rotate\(176\.35\d* 100 100\)$/,
  );

  await page.getByRole("tab", { name: "Месяц" }).click();
  await expect(page.getByRole("tab", { name: "Месяц" })).toHaveAttribute("aria-selected", "true");
  await expect(page.getByTestId("prayer-month-title")).toHaveText("июнь 2026 г.");
  const rows = page.locator(".prayer-month-table tbody tr");
  await expect(rows).toHaveCount(30);
  for (const [index, minutes] of moscowJune.utc_minutes.entries()) {
    await expect(rows.nth(index).locator("td")).toHaveText(minutes.map(moscowWallClock));
  }

  await page.getByRole("button", { name: "Следующий месяц" }).click();
  await expect(page.getByTestId("prayer-month-title")).toHaveText("июль 2026 г.");
  await expect(rows).toHaveCount(31);

  await page.getByRole("tab", { name: "День" }).click();
  await expect(page.locator(".prayer-grid")).toBeVisible();
});

test("prayer month and Qibla are localized and right-to-left in Arabic", async ({ page }) => {
  await mockPrayerApi(page);
  await page.goto("/ar/prayer");
  await expect(page.locator("html")).toHaveAttribute("dir", "rtl");
  await expect(page.getByRole("heading", { name: "اتجاه القبلة" })).toBeVisible();
  await page.getByRole("tab", { name: "الشهر" }).click();
  await expect(page.locator(".prayer-month-table tbody tr").first()).toBeVisible();
  await expect(page.getByRole("button", { name: "الشهر التالي" })).toHaveText("‹");
  const direction = await page
    .locator(".prayer-month-table")
    .evaluate((element) => getComputedStyle(element).direction);
  expect(direction).toBe("rtl");
});

test("prayer month explains when the backend engine is newer than the web port", async ({ page }) => {
  await mockPrayerApi(page, { algorithmVersion: "5.0.0" });
  await page.goto("/en/prayer");
  await page.getByRole("tab", { name: "Month" }).click();
  await expect(
    page.getByText("The monthly calendar is not available for this calculation method."),
  ).toBeVisible();
});

test("invalid date and adjustments are rejected before calculation", async ({ page }) => {
  const calculations = await mockPrayerApi(page);
  await page.goto("/ru/prayer");
  await expect(page.getByTestId("prayer-qibla-bearing")).toHaveText("Вы у Каабы — молитесь лицом к ней");
  const sent = calculations.length;

  await page.getByLabel("Дата расчёта").fill("");
  await page.getByRole("button", { name: "Рассчитать расписание" }).click();
  await expect(page.getByText("Укажите дату расчёта в пределах 1900–2100 годов.")).toBeVisible();
  await page.getByRole("tab", { name: "Месяц" }).click();
  await expect(page.locator(".prayer-month-table tbody tr").first()).toBeVisible();

  await page.getByLabel("Дата расчёта").fill("2026-06-15");
  for (const value of ["1.5", "121"]) {
    await page.getByLabel("Фаджр", { exact: true }).fill(value);
    await expect(page.getByLabel("Фаджр", { exact: true })).toHaveAttribute("aria-invalid", "true");
    await expect(page.getByText("Целое число минут от −120 до 120.")).toBeVisible();
    // Native number constraints stop the form submit; the profile button reaches our own check.
    await page.getByRole("button", { name: "Рассчитать расписание" }).click();
    await page.getByRole("button", { name: "Сохранить профиль" }).click();
    await expect(page.getByText("Исправьте поправки: нужны целые минуты от −120 до 120.")).toBeVisible();
  }
  expect(calculations).toHaveLength(sent);
});

test("a failed calculation keeps the previous day, Qibla and month together", async ({ page }) => {
  const calculations = await mockPrayerApi(page, { failTimezone: "Europe/Moscow" });
  await page.goto("/ru/prayer");
  await expect(page.getByTestId("prayer-qibla-bearing")).toHaveText("Вы у Каабы — молитесь лицом к ней");
  await page.getByLabel("Быстрый выбор города").selectOption({ label: "Москва (Россия)" });
  await page.getByRole("button", { name: "Рассчитать расписание" }).click();
  await expect.poll(() => calculations.at(-1)?.timezone).toBe("Europe/Moscow");
  await expect(page.locator(".alert-error")).toBeVisible();

  await expect(page.getByTestId("prayer-qibla-bearing")).toHaveText("Вы у Каабы — молитесь лицом к ней");
  await expect(page.getByText("Часовой пояс: Asia/Riyadh")).toBeVisible();
  await page.getByRole("tab", { name: "Месяц" }).click();
  await expect(page.getByText("Часовой пояс: Asia/Riyadh")).toBeVisible();
});

const MOSCOW = { latitude: 55.7558, longitude: 37.6173 };

const moscowLabels = {
  ru: {
    atKaaba: "Вы у Каабы — молитесь лицом к ней",
    quickCity: "Быстрый выбор города",
    city: "Москва (Россия)",
    calculate: "Рассчитать расписание",
  },
  en: {
    atKaaba: "You are at the Kaaba — face it directly",
    quickCity: "Quick city selection",
    city: "Moscow (Russia)",
    calculate: "Calculate schedule",
  },
};

async function showMoscowQibla(page: Page, locale: keyof typeof moscowLabels = "ru") {
  const labels = moscowLabels[locale];
  await page.goto(`/${locale}/prayer`);
  // The first automatic calculation (Makkah by default) finishes restoring the form.
  await expect(page.getByTestId("prayer-qibla-bearing")).toHaveText(labels.atKaaba);
  await page.getByLabel(labels.quickCity).selectOption({ label: labels.city });
  await page.getByRole("button", { name: labels.calculate }).click();
  await expect(page.getByTestId("prayer-qibla-arrow")).toHaveCount(1);
}

// Chrome 152+ exposes `requestPermission` too, yet still sends absolute orientation unasked.
const emulateModernChrome = (page: Page) =>
  page.addInitScript(() => {
    Object.defineProperty(DeviceOrientationEvent, "requestPermission", {
      configurable: true,
      value: async () => "granted",
    });
  });

// iOS Safari: motion access only from a tap, and no absolute orientation event.
const emulateSafari = (page: Page, answer: "granted" | "denied") =>
  page.addInitScript((result) => {
    Object.defineProperty(DeviceOrientationEvent, "requestPermission", {
      configurable: true,
      value: async () => result,
    });
    delete (window as unknown as Record<string, unknown>).ondeviceorientationabsolute;
    delete (Window.prototype as unknown as Record<string, unknown>).ondeviceorientationabsolute;
  }, answer);

const dialRotation = (page: Page) =>
  page
    .getByTestId("prayer-qibla-dial")
    .getAttribute("transform")
    .then((value) => Number(/^rotate\((-?[\d.e+-]+) 100 100\)$/.exec(value ?? "")?.[1]));

test("the Qibla dial follows a live Android compass and lights up when the phone faces it", async ({ page }) => {
  await emulateModernChrome(page);
  await mockPrayerApi(page);
  await showMoscowQibla(page);
  // Chrome needs no tap even where it exposes requestPermission.
  await expect(page.getByRole("button", { name: "Включить компас" })).toHaveCount(0);
  // The page moves magnetic headings to true north with the same model.
  const declination = magneticDeclination(MOSCOW.latitude, MOSCOW.longitude)!;
  const bearing = qiblaBearing(MOSCOW.latitude, MOSCOW.longitude)!;
  const pointPhone = (trueHeading: number) =>
    page.evaluate((alpha) => {
      window.dispatchEvent(
        new DeviceOrientationEvent("deviceorientationabsolute", { alpha, beta: 20, gamma: -10, absolute: true }),
      );
    }, (((360 - (trueHeading - declination)) % 360) + 360) % 360);

  const qibla = page.getByTestId("prayer-qibla");
  await pointPhone(bearing + 90);
  await expect(page.getByTestId("prayer-qibla-hint")).toHaveText(
    "Компас устройства включён: держите телефон горизонтально — стрелка показывает Киблу относительно его верха.",
  );
  await expect.poll(() => dialRotation(page)).toBeCloseTo(-(bearing + 90), 0);
  await expect(page.getByTestId("prayer-qibla-status")).toHaveText("");
  await expect(qibla).not.toHaveClass(/is-facing/);
  // Without accuracy reports the page cannot tell a bad calibration, so it explains the fix.
  await expect(qibla.getByText("Если стрелка неточна", { exact: false })).toBeVisible();

  await pointPhone(bearing + 2);
  await expect.poll(() => dialRotation(page)).toBeCloseTo(-(bearing + 2), 0);
  await expect(page.getByTestId("prayer-qibla-status")).toHaveText("Вы смотрите на Киблу");
  await expect(qibla).toHaveClass(/is-facing/);
  // Hysteresis: a small drift past 3° keeps the state, leaving the 5° band drops it.
  await pointPhone(bearing - 4);
  await expect.poll(() => dialRotation(page)).toBeCloseTo(-(bearing - 4), 0);
  await expect(page.getByTestId("prayer-qibla-status")).toHaveText("Вы смотрите на Киблу");
  await pointPhone(bearing - 8);
  await expect(page.getByTestId("prayer-qibla-status")).toHaveText("");
  await expect(qibla).not.toHaveClass(/is-facing/);
});

test("on iPhone the compass starts from a tap and asks for calibration", async ({ page }) => {
  await emulateSafari(page, "granted");
  await mockPrayerApi(page);
  await showMoscowQibla(page);
  const declination = magneticDeclination(MOSCOW.latitude, MOSCOW.longitude)!;
  const bearing = qiblaBearing(MOSCOW.latitude, MOSCOW.longitude)!;
  const pointPhone = (trueHeading: number, accuracy: number) =>
    page.evaluate(
      ([heading, headingAccuracy]) => {
        const event = Object.assign(new Event("deviceorientation"), { alpha: 0, beta: 0, gamma: 0 });
        Object.defineProperties(event, {
          webkitCompassHeading: { value: heading },
          webkitCompassAccuracy: { value: headingAccuracy },
        });
        window.dispatchEvent(event);
      },
      [(((trueHeading - declination) % 360) + 360) % 360, accuracy],
    );

  await expect(page.getByTestId("prayer-qibla-hint")).toHaveText(/^Это географическое направление/);
  await page.getByRole("button", { name: "Включить компас" }).click();
  await expect(page.getByRole("button", { name: "Включить компас" })).toHaveCount(0);

  await pointPhone(bearing, -1);
  await expect(page.getByTestId("prayer-qibla-status")).toHaveText("Компас нужно откалибровать");
  await expect(page.getByTestId("prayer-qibla-hint")).toHaveText(/^Поводите телефоном в воздухе восьмёркой/);
  await expect(page.getByTestId("prayer-qibla")).not.toHaveClass(/is-facing/);

  await pointPhone(bearing, 10);
  await expect(page.getByTestId("prayer-qibla-status")).toHaveText("Вы смотрите на Киблу");
  await expect.poll(() => dialRotation(page)).toBeCloseTo(-bearing, 0);
  await expect(page.getByText("Если стрелка неточна", { exact: false })).toHaveCount(0);
});

test("a refused motion permission keeps the geographic bearing and says why", async ({ page }) => {
  await emulateSafari(page, "denied");
  await mockPrayerApi(page);
  await showMoscowQibla(page, "en");
  await page.getByRole("button", { name: "Turn on the compass" }).click();
  await expect(page.getByTestId("prayer-qibla-hint")).toHaveText(
    /^No access to motion sensors: allow it in the browser settings and reload the page\. This is a geographic bearing/,
  );
  await expect(page.getByTestId("prayer-qibla-dial")).toHaveAttribute("transform", "rotate(0 100 100)");
});
