import { expect, test, type Page } from "@playwright/test";

const progressKey = "names.progress.asma-al-husna";

test.beforeEach(async ({ page }) => {
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ status: 401 }));
  // Recordings live on external hosts; keep the suite offline.
  await page.route(/\.(mp3|m4a)(\?|$)/, (route) => route.fulfill({ status: 404 }));
  // Without animation the wheel is on the next name at once.
  await page.emulateMedia({ reducedMotion: "reduce" });
});

async function openWheel(page: Page, locale = "ru") {
  await page.goto(`/${locale}/names`);
  // The canvas gets its size after hydration; act only then.
  await expect(page.locator('[data-testid="names-dial"] canvas')).toHaveAttribute("width", /\d+/);
}

async function stored(page: Page) {
  return page.evaluate((key) => JSON.parse(window.localStorage.getItem(key) || "null"), progressKey);
}

test("the wheel turns by keys and by a tap on its centre; the name under it opens the card", async ({ page }) => {
  await openWheel(page);
  const dial = page.getByTestId("names-dial");
  const readout = page.getByTestId("names-readout");
  await expect(readout).toContainText("Ар-Рахман");
  await expect(page.getByTestId("names-seen")).toHaveText("0 из 4");

  await dial.focus();
  await page.keyboard.press("ArrowRight");
  await expect(readout).toContainText("Ар-Рахим");
  await expect(dial).toHaveAttribute("aria-valuenow", "2");
  await expect(page.getByTestId("names-seen")).toHaveText("1 из 4");

  // A tap on the centre: the next name, not the card.
  const box = await dial.boundingBox();
  if (!box) throw new Error("The dial has no box.");
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2);
  await expect(readout).toContainText("Малик аль-Мульк");
  await expect(page.getByTestId("names-card")).toHaveCount(0);
  await expect(page.getByTestId("names-seen")).toHaveText("2 из 4");

  await page.keyboard.press("ArrowLeft");
  await expect(readout).toContainText("Ар-Рахим");
  await page.keyboard.press("ArrowRight");

  await readout.click();
  const card = page.getByTestId("names-card");
  await expect(card).toBeVisible();
  await expect(card.getByRole("heading", { level: 2 })).toHaveText("Малик аль-Мульк");
  await expect(card).toContainText("Имя 3 из 4");
  await expect(card).toContainText("Источник: Пример: книга толкований");
  // Two words of the ayah: a link to our reader, no «Слушать».
  await expect(card.getByTestId("names-ayah")).toHaveAttribute("href", "/ru/quran?surah=3&ayah=26");
  await expect(card.getByTestId("names-listen")).toHaveCount(0);

  const learned = card.getByTestId("names-learned");
  await expect(learned).toHaveAttribute("aria-pressed", "false");
  await learned.click();
  await expect(learned).toHaveAttribute("aria-pressed", "true");
  expect((await stored(page)).lessons["malik-al-mulk"].status).toBe("completed");
  // «Выучено» is its own mark: the meter counts the names the needle stopped on.
  await expect(page.getByTestId("names-seen")).toHaveText("2 из 4");
  await learned.click();
  expect((await stored(page)).lessons["malik-al-mulk"].status).toBe("in_progress");

  // The card walks to the neighbours and the wheel follows.
  await card.getByTestId("names-card-next").click();
  await expect(card.getByRole("heading", { level: 2 })).toHaveText("Аль-Джамиль");
  await expect(card).toContainText("Источник: Пример: другая книга для этого имени");
  await expect(card.getByTestId("names-ayah")).toHaveCount(0);
  await expect(dial).toHaveAttribute("aria-valuenow", "4");
  await card.getByTestId("names-card-next").click();
  await expect(card.getByRole("heading", { level: 2 })).toHaveText("Ар-Рахман");
  await expect(card.getByTestId("names-listen")).toBeVisible();
  await expect(card.getByTestId("names-ayah")).toHaveAttribute("href", "/ru/quran?surah=55&ayah=1");

  await page.keyboard.press("Escape");
  await expect(card).toHaveCount(0);
  await expect(page.getByTestId("names-seen")).toHaveText("4 из 4");

  // The marks survive a reload.
  await page.reload();
  await expect(page.getByTestId("names-seen")).toHaveText("4 из 4");
});

test("a drag turns the wheel", async ({ page }) => {
  await openWheel(page);
  const dial = page.getByTestId("names-dial");
  const box = await dial.boundingBox();
  if (!box) throw new Error("The dial has no box.");
  const centre = { x: box.x + box.width / 2, y: box.y + box.height / 2 };
  const radius = box.width * 0.35;
  // From twelve o'clock to three: a quarter of four names is one name.
  await page.mouse.move(centre.x, centre.y - radius);
  await page.mouse.down();
  for (let step = 1; step <= 9; step += 1) {
    const angle = -Math.PI / 2 + (Math.PI / 2) * (step / 9);
    await page.mouse.move(centre.x + radius * Math.cos(angle), centre.y + radius * Math.sin(angle));
  }
  await page.waitForTimeout(120);
  await page.mouse.up();
  await expect(page.getByTestId("names-readout")).toContainText("Ар-Рахим");
});

test("labels switch between the interface language and Arabic; the Arabic site has one script", async ({ page }) => {
  await openWheel(page);
  const arabic = page.getByTestId("names-labels-arabic");
  await expect(arabic).toHaveAttribute("aria-pressed", "false");
  await arabic.click();
  await expect(arabic).toHaveAttribute("aria-pressed", "true");
  await expect(page.getByTestId("names-labels-locale")).toHaveAttribute("aria-pressed", "false");
  // With Arabic labels the wheel runs the other way, and the keys still go to the next name.
  await page.getByTestId("names-dial").focus();
  await page.keyboard.press("ArrowRight");
  await expect(page.getByTestId("names-readout")).toContainText("Ар-Рахим");

  await openWheel(page, "ar");
  await expect(page.getByTestId("names-labels-arabic")).toHaveCount(0);
  await expect(page.getByTestId("names-readout")).toContainText("الرَّحْمَٰنُ");
  await expect(page.getByTestId("names-readout")).not.toContainText("Ар-Рахман");
});

test("the section is in the menus", async ({ page }) => {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto("/ru");
  await page.locator('.app-menu a[href="/ru/names"]').click();
  await expect(page).toHaveURL("/ru/names");
  await expect(page.getByRole("heading", { level: 1 })).toHaveText("Имена Аллаха");
});

test("a signed-in reader's marks go to the account and come back merged", async ({ page }) => {
  await page.unroute("**/api/web-auth/refresh");
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({
    json: {
      token_type: "Bearer",
      access_token: "active-access-token",
      expires_in: 900,
      access_expires_at: "2026-08-24T15:00:00Z",
      user: {
        id: "00000000-0000-7000-8000-000000000102",
        status: "active",
        preferred_locale: "ru",
        email: "reader@example.com",
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
    },
  }));
  // The account already has a name learned on another device.
  const sent: { lessons: Record<string, { status: string }> }[] = [];
  await page.route("**/api/v1/me/courses/progress/names/asma-al-husna", async (route) => {
    const body = route.request().postDataJSON() as { lessons: Record<string, { status: string }> };
    sent.push(body);
    await route.fulfill({
      json: {
        kind: "names",
        course: "asma-al-husna",
        lessons: {
          ...body.lessons,
          "al-jamil": body.lessons["al-jamil"] ?? {
            status: "completed",
            step_slug: "",
            content_version: "example-1",
            updated_at: "2026-11-01T10:00:00.000Z",
          },
        },
      },
    });
  });

  await openWheel(page);
  // What the account knows shows up on this device.
  await expect(page.getByTestId("names-seen")).toHaveText("1 из 4");
  expect((await stored(page)).lessons["al-jamil"].status).toBe("completed");

  await page.getByTestId("names-readout").click();
  await page.getByTestId("names-learned").click();
  await expect.poll(() => sent.at(-1)?.lessons["ar-rahman"]?.status).toBe("completed");
});
