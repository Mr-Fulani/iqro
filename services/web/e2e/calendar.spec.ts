import { expect, test } from "@playwright/test";
import { readFileSync } from "node:fs";
import { calendarCopy } from "../lib/calendar";

const dataRoot = "../backend/src/quran_backend/modules/calendar/data/";
const seed = JSON.parse(readFileSync(`${dataRoot}events-v1.json`, "utf8"));
const starts: number[] = JSON.parse(readFileSync(`${dataRoot}ummalqura-v1.json`, "utf8")).month_starts_mcjdn;
const dayMs = 86_400_000;

for (const locale of ["ru", "en", "ar", "tr"] as const) {
  test(`${locale} shared calendar: month, event, source and adjustment`, async ({page}) => {
    await page.setViewportSize({width: 390, height: 844});
    const copy = calendarCopy[locale];
    const requests: URL[] = [];
    await page.route("**/api/web-auth/refresh", (route) => route.fulfill({status: 401, json: {}}));
    await page.route("**/api/v1/calendar/month?*", (route) => {
      const url = new URL(route.request().url()); requests.push(url);
      const year = Number(url.searchParams.get("year") || 1448);
      const month = Number(url.searchParams.get("month") || 9);
      const adjustment = Number(url.searchParams.get("adjustment") || 0);
      const index = (year - 1356) * 12 + month - 1;
      const first = Date.UTC(1858, 10, 16) + (starts[index] - adjustment) * dayMs;
      const days = Array.from({length: starts[index + 1] - starts[index]}, (_, n) => ({
        day: n + 1, civil_date: new Date(first + n * dayMs).toISOString().slice(0, 10),
        events: seed.events.filter((e: {month: number; day_start: number; day_end: number}) =>
          e.month === month && e.day_start <= n + 1 && e.day_end >= n + 1).map((e: {code: string}) => e.code),
      }));
      return route.fulfill({json: {method: seed.method, year, month, adjustment,
        selected_day: null, first_weekday: new Date(first).getUTCDay() || 7, days, catalog: seed}});
    });
    await page.goto(`/${locale}/calendar`);
    await expect(page.getByRole("heading", {name: copy.title, exact: true})).toBeVisible();
    await expect(page.getByRole("button", {name: copy.next, exact: true})).toBeEnabled();
    await expect(page.locator("html")).toHaveAttribute("dir", locale === "ar" ? "rtl" : "ltr");
    await page.getByRole("button", {name: /^٢٣ |^23 /}).click();
    await expect(page.getByRole("heading", {name: seed.events.find((e: {code: string}) => e.code === "last_ten_nights").titles[locale]})).toBeVisible();
    await expect(page.getByRole("link", {name: /Sahih al-Bukhari 2017/})).toHaveAttribute("href", "https://sunnah.com/bukhari:2017");
    await page.getByRole("combobox", {name: copy.adjustment}).selectOption("1");
    await expect.poll(() => requests.at(-1)?.searchParams.get("adjustment")).toBe("1");
    await expect(page.getByRole("button", {name: copy.next, exact: true})).toBeEnabled();
    await page.getByRole("button", {name: copy.next, exact: true}).click();
    await expect.poll(() => requests.at(-1)?.searchParams.get("month")).toBe("10");
    await expect(page.getByRole("heading", {name: seed.events.find((e: {code: string}) => e.code === "eid_fitr").titles[locale]})).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    await page.screenshot({path: `../../tmp/calendar-${locale}-20260908.png`, fullPage: true});
  });
}

test("calendar reports failure and retry recovers without blanking the screen", async ({page}) => {
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({status: 401, json: {}}));
  await page.route("**/api/v1/calendar/month?*", (route) => route.fulfill({status: 503, json: {}}));
  await page.goto("/en/calendar");
  await expect(page.getByText(calendarCopy.en.error)).toBeVisible();
  await expect(page.getByRole("button", {name: "Refresh", exact: true})).toBeVisible();
  await page.route("**/api/v1/calendar/month?*", (route) => route.fulfill({json: {
    method: seed.method, catalog: seed, catalog_version: seed.version,
    year: 1448, month: 10, selected_day: 1, adjustment: 0, first_weekday: 3,
    days: [{day: 1, civil_date: "2027-03-10", events: ["eid_fitr"]}],
  }}));
  await page.getByRole("button", {name: "Refresh", exact: true}).click();
  await expect(page.getByText(calendarCopy.en.error)).not.toBeVisible();
  await expect(page.getByRole("heading", {name: seed.events.find((e: {code: string}) => e.code === "eid_fitr").titles.en})).toBeVisible();
});
