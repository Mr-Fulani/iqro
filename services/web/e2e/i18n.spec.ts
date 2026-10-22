import { readFile } from "node:fs/promises";

import { expect, test, type Locator } from "@playwright/test";

async function expectHeaderWithoutOverlap(page: import("@playwright/test").Page) {
  // Menu links animate padding and font size between breakpoints.
  await page.locator(".app-header").evaluate((header) => Promise.allSettled(header
    .getAnimations({ subtree: true })
    .filter((animation) => animation instanceof CSSTransition)
    .map((animation) => animation.finished)));
  const layout = await page.locator(".app-header").evaluate((header) => {
    const box = (element: Element) => {
      const rect = element.getBoundingClientRect();
      return { left: rect.left, right: rect.right, top: rect.top, bottom: rect.bottom };
    };
    return {
      fits: header.scrollWidth <= header.clientWidth,
      groups: [...header.children].map(box),
      menu: box(header.querySelector(".app-menu")!),
      // The announced "soon" item is not rendered where the menu has no room.
      links: [...header.querySelectorAll(".menu-link")]
        .filter((link) => link.getClientRects().length > 0)
        .map(box),
      actions: [...header.querySelectorAll(".header-actions > *")].map(box),
    };
  });
  const overlaps = (
    left: { left: number; right: number; top: number; bottom: number },
    right: { left: number; right: number; top: number; bottom: number },
  ) => Math.min(left.right, right.right) - Math.max(left.left, right.left) > 0.5
    && Math.min(left.bottom, right.bottom) - Math.max(left.top, right.top) > 0.5;

  expect(layout.fits).toBe(true);
  for (let left = 0; left < layout.groups.length; left += 1) {
    for (let right = left + 1; right < layout.groups.length; right += 1) {
      expect(overlaps(layout.groups[left], layout.groups[right])).toBe(false);
    }
  }
  for (const link of layout.links) {
    expect(link.left).toBeGreaterThanOrEqual(layout.menu.left - 1);
    expect(link.right).toBeLessThanOrEqual(layout.menu.right + 1);
  }
  for (let left = 0; left < layout.links.length; left += 1) {
    for (let right = left + 1; right < layout.links.length; right += 1) {
      expect(overlaps(layout.links[left], layout.links[right])).toBe(false);
    }
  }
  for (let left = 0; left < layout.actions.length; left += 1) {
    for (let right = left + 1; right < layout.actions.length; right += 1) {
      expect(overlaps(layout.actions[left], layout.actions[right])).toBe(false);
    }
  }
}

test.beforeEach(async ({ page }) => {
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ status: 401 }));
});

test("language switch persists RU EN AR and TR while Arabic enables RTL", async ({ page }) => {
  await page.setViewportSize({ width: 1250, height: 900 });
  await page.goto("/login");

  const language = page.getByTestId("language-switcher");
  await expect(language).toHaveValue("ru");
  await expect(page.getByRole("heading", { name: "Вход в аккаунт" })).toBeVisible();
  await expectHeaderWithoutOverlap(page);

  await language.selectOption("en");
  await expect(page).toHaveURL("/en/login");
  await expect(page.locator("html")).toHaveAttribute("lang", "en");
  await expect(page.locator("html")).toHaveAttribute("dir", "ltr");
  await expect(page).toHaveTitle("Account sign-in | Quran Platform");
  await expect(page.getByRole("heading", { name: "Account sign-in" })).toBeVisible();
  await expectHeaderWithoutOverlap(page);

  await page.reload();
  await expect(page.getByTestId("language-switcher")).toHaveValue("en");
  await expect(page.getByRole("heading", { name: "Account sign-in" })).toBeVisible();

  await page.getByTestId("language-switcher").selectOption("ar");
  await expect(page).toHaveURL("/ar/login");
  await expect(page.locator("html")).toHaveAttribute("lang", "ar");
  await expect(page.locator("html")).toHaveAttribute("dir", "rtl");
  await expect(page).toHaveTitle("تسجيل الدخول | Quran Platform");
  await expect(page.getByRole("heading", { name: "تسجيل الدخول" })).toBeVisible();
  await expectHeaderWithoutOverlap(page);

  await page.getByTestId("language-switcher").selectOption("tr");
  await expect(page).toHaveURL("/tr/login");
  await expect(page.locator("html")).toHaveAttribute("lang", "tr");
  await expect(page.locator("html")).toHaveAttribute("dir", "ltr");
  await expect(page.getByRole("heading", { name: "Hesaba giriş" })).toBeVisible();
  await expectHeaderWithoutOverlap(page);
});

test("authenticated Russian header keeps navigation clear of account actions", async ({ page }) => {
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
  await page.setViewportSize({ width: 1250, height: 900 });

  await page.goto("/login");

  await expect(page.getByTestId("language-switcher")).toHaveValue("ru");
  await expect(page.locator(".app-header").getByRole("button", { name: "Выйти" })).toBeVisible();
  for (const width of [1250, 1236, 1235, 1201, 1150, 1001, 900, 390]) {
    await page.setViewportSize({ width, height: 900 });
    await expectHeaderWithoutOverlap(page);
  }
});

test("header logo replaces Home and the published Dua catalog follows Quran", async ({ page }) => {
  await page.goto("/ru/quran");

  const brand = page.locator(".brand-link");
  await expect(brand).toHaveAttribute("href", "/ru");
  await expect(brand).toContainText("IQRO");
  await expect(brand).toContainText("Исламский форум");
  await expect(page.locator('.app-menu a[href="/ru"]')).toHaveCount(0);
  expect(await page.locator(".app-menu a").evaluateAll((links) =>
    links.map((link) => link.getAttribute("href")),
  )).toEqual([
    "/ru/quran",
    "/ru/memorization",
    "/ru/planner",
    "/ru/dua",
    "/ru/audio",
    "/ru/prayer",
    "/ru/salah",
    "/ru/tajweed",
    "/ru/calendar",
    "/ru/profile",
  ]);
  const names = page.locator(".app-menu").getByTestId("menu-names-of-allah");
  await expect(names).toBeVisible();
  await expect(names).toHaveAttribute("aria-disabled", "true");
  await expect(names).toHaveAttribute("title", "Имена Аллаха — Скоро");

  await page.locator('.app-menu a[href="/ru/dua"]').click();
  await expect(page).toHaveURL("/ru/dua");
  await expect(page.getByRole("heading", { level: 1, name: "Ду’а" })).toBeVisible();
  // Hidden streamed route HTML may still contain another copy of this tag.
  await expect(page.locator('head meta[name="robots"]')).toHaveAttribute("content", /index, follow/);
  await expect(page.locator(".dua-topic-card")).toHaveAttribute("href", "/ru/dua/topics/sleep");
});

const duaArabic = "الْحَمْدُ للَّهِ الَّذِي أَحْيَانَا بَعْدَ مَا أَمَاتَنَا، وَإِلَيْهِ النُّشُورُ";

// Which side of the drawn card the red wax seal is on: 44 px square, 40 px
// from the top, inside 44 px margins of the 540 px card; the PNG is twice as
// dense.
function sealSide(picture: Locator) {
  return picture.evaluate(async (image: HTMLImageElement) => {
    await image.decode();
    const bitmap = await createImageBitmap(image);
    const context = new OffscreenCanvas(bitmap.width, bitmap.height).getContext("2d")!;
    context.drawImage(bitmap, 0, 0);
    const redness = (x: number) => {
      const { data } = context.getImageData(x * 2, 80, 88, 88);
      let sum = 0;
      for (let index = 0; index < data.length; index += 4) sum += data[index] - data[index + 1];
      return sum / (data.length / 4);
    };
    const [left, right] = [redness(44), redness(540 - 88)];
    // The red of the seal against the green background; nothing drawn reads alike.
    if (Math.abs(left - right) < 50) return "none";
    return left > right ? "left" : "right";
  });
}

test("a dua is shared as the app's picture through Web Share", async ({ page }) => {
  await page.addInitScript(() => {
    const target = window as unknown as { sharedDua?: unknown };
    Object.defineProperty(navigator, "canShare", {
      configurable: true,
      value: (data: ShareData) => Boolean(data.files?.length),
    });
    Object.defineProperty(navigator, "share", {
      configurable: true,
      async value(data: ShareData) {
        const file = data.files?.[0];
        const picture = file ? await createImageBitmap(file) : null;
        target.sharedDua = {
          title: data.title,
          text: data.text,
          file: file && { name: file.name, type: file.type, width: picture?.width, height: picture?.height },
        };
      },
    });
  });
  await page.goto("/ru/dua/hisn-al-muslim/1");
  // The chapter, printed in capitals in the source, reads in sentence case on
  // the page, in its title and on the card alike.
  const chapter = "Слова поминания при пробуждении ото сна";
  const title = `${chapter} · #1`;
  await expect(page).toHaveTitle(`${title} | Quran Platform`);
  await expect(page.getByRole("heading", { level: 1, name: chapter, exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Поделиться ду’а", exact: true }).click();
  const dialog = page.getByRole("dialog", { name: "Поделиться ду’а" });
  await expect(dialog.getByText(title, { exact: true })).toBeVisible();
  const picture = dialog.getByRole("img", { name: "Картинка ду’а #1" });
  await expect(picture).toBeVisible();
  expect(await sealSide(picture)).toBe("left");
  await dialog.getByRole("button", { name: "Поделиться", exact: true }).click();

  const link = new URL("/ru/dua/hisn-al-muslim/1", page.url()).href;
  await expect.poll(() => page.evaluate(() => (window as unknown as { sharedDua?: unknown }).sharedDua))
    .toEqual({
      title,
      text: [
        title,
        duaArabic,
        "«Хвала Аллаху, воскресившему нас после того, как Он умертвил нас, и к Нему воскресение.»",
        "Молитвы из Корана и Сунны · Al-Bukhari 6314; Muslim 2711.",
        `Читать в IQRO: ${link}`,
      ].join("\n\n"),
      file: { name: "iqro-hisn-al-muslim-1.png", type: "image/png", width: 1080, height: 1350 },
    });
  await dialog.getByRole("button", { name: "Закрыть" }).click();
  await expect(dialog).toBeHidden();
});

test("without the share dialog's code a dua still goes as text, and the next press loads it", async ({ page }) => {
  const pageErrors: string[] = [];
  page.on("pageerror", (error) => pageErrors.push(error.message));
  await page.addInitScript(() => {
    const target = window as unknown as { copiedTexts: string[] };
    target.copiedTexts = [];
    Object.defineProperty(navigator, "share", { configurable: true, value: undefined });
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText: async (text: string) => { target.copiedTexts.push(text); } },
    });
  });
  await page.goto("/ru/dua/hisn-al-muslim/1");
  const copied = () => page.evaluate(() => (window as unknown as { copiedTexts: string[] }).copiedTexts);
  const link = new URL("/ru/dua/hisn-al-muslim/1", page.url()).href;
  const text = [
    "Слова поминания при пробуждении ото сна · #1",
    duaArabic,
    "«Хвала Аллаху, воскресившему нас после того, как Он умертвил нас, и к Нему воскресение.»",
    "Молитвы из Корана и Сунны · Al-Bukhari 6314; Muslim 2711.",
    `Читать в IQRO: ${link}`,
  ].join("\n\n");

  // A network blip or a deploy that replaced the chunk: the page stays and the text goes.
  await page.route("**/_next/static/chunks/**", (route) => route.abort());
  await page.getByRole("button", { name: "Поделиться ду’а", exact: true }).click();
  await expect(page.getByRole("status").filter({ hasText: "Текст и ссылка скопированы" })).toBeVisible();
  expect(await copied()).toEqual([text]);
  await expect(page.getByRole("dialog")).toHaveCount(0);
  await expect(page.locator(".dua-arabic")).toBeVisible();

  // Once the network is back, the next press loads the dialog; without Web
  // Share it copies the text too.
  await page.unroute("**/_next/static/chunks/**");
  await page.getByRole("button", { name: "Поделиться ду’а", exact: true }).click();
  const dialog = page.getByRole("dialog", { name: "Поделиться ду’а" });
  await expect(dialog.getByRole("img", { name: "Картинка ду’а #1" })).toBeVisible();
  await expect(dialog.getByRole("button", { name: "Поделиться", exact: true })).toHaveCount(0);
  await dialog.getByRole("button", { name: "Скопировать текст" }).click();
  await expect(dialog.getByRole("status").filter({ hasText: "Текст и ссылка скопированы" })).toBeVisible();
  expect(await copied()).toEqual([text, text]);
  expect(pageErrors).toEqual([]);
});

test("an Arabic dua picture is drawn right to left and downloads where files cannot be shared", async ({ page }) => {
  await page.addInitScript(() => {
    const target = window as unknown as { sharedDua?: unknown; copiedLink?: string };
    Object.defineProperty(navigator, "canShare", { configurable: true, value: () => false });
    Object.defineProperty(navigator, "share", {
      configurable: true,
      async value(data: ShareData) {
        target.sharedDua = { title: data.title, text: data.text, files: data.files?.length ?? 0 };
      },
    });
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText: async (text: string) => { target.copiedLink = text; } },
    });
  });
  await page.goto("/ar/dua/hisn-al-muslim/1");
  // Linux has neither Times New Roman nor Arial, the local() metric fallbacks
  // next/font lists after Amiri and Inter; the card must not depend on them.
  await page.addStyleTag({
    content: `@font-face { font-family: "Missing Fallback"; src: local("IQRO Missing Font"); }
      html:root { --font-amiri: "Amiri", "Missing Fallback"; --font-inter: "Inter", "Missing Fallback"; }`,
  });
  await page.getByRole("button", { name: "مشاركة الدعاء", exact: true }).click();
  const dialog = page.getByRole("dialog", { name: "مشاركة الدعاء" });
  const picture = dialog.getByRole("img", { name: "صورة الدعاء #1" });
  await expect(picture).toBeVisible();
  expect(await sealSide(picture)).toBe("right");

  const [download] = await Promise.all([
    page.waitForEvent("download"),
    dialog.getByRole("link", { name: "تنزيل الصورة" }).click(),
  ]);
  expect(download.suggestedFilename()).toBe("iqro-hisn-al-muslim-1.png");
  const png = await readFile(await download.path());
  expect(png.subarray(1, 4).toString("ascii")).toBe("PNG");
  expect([png.readUInt32BE(16), png.readUInt32BE(20)]).toEqual([1080, 1350]);

  const link = new URL("/ar/dua/hisn-al-muslim/1", page.url()).href;
  await dialog.getByRole("button", { name: "نسخ الرابط" }).click();
  await expect(dialog.getByRole("status").filter({ hasText: "تم نسخ الرابط" })).toBeVisible();
  expect(await page.evaluate(() => (window as unknown as { copiedLink?: string }).copiedLink)).toBe(link);

  // The text still goes; the Arabic meaning, which repeats the du'a, does not.
  await dialog.getByRole("button", { name: "مشاركة", exact: true }).click();
  const title = "أذكار الاستيقاظ من النوم · #1";
  await expect.poll(() => page.evaluate(() => (window as unknown as { sharedDua?: unknown }).sharedDua))
    .toEqual({
      title,
      text: [
        title,
        duaArabic,
        "حصن المسلم من أذكار الكتاب والسنة · Al-Bukhari 6314; Muslim 2711.",
        `اقرأ في IQRO: ${link}`,
      ].join("\n\n"),
      files: 0,
    });
});

test.describe("browser language negotiation", () => {
  test.use({ locale: "tr-TR" });

  test("Accept-Language selects Turkish when no locale cookie exists", async ({ page }) => {
    await page.goto("/login");

    await expect(page.locator("html")).toHaveAttribute("lang", "tr");
    await expect(page.locator("html")).toHaveAttribute("dir", "ltr");
    await expect(page.getByTestId("language-switcher")).toHaveValue("tr");
    await expect(page.getByRole("heading", { name: "Hesaba giriş" })).toBeVisible();
  });
});
