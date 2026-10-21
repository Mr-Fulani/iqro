import { expect, test, type Page } from "@playwright/test";

// The du'a section as the app shows it (dua_screen.dart). The mock API has two
// chapters of the "sleep" topic: «waking up» with du'a #1 (audio) and «before
// sleeping» with #100 (basmala before a surah, said three times) and #101.

const phone = { width: 390, height: 844 };
const desktop = { width: 1280, height: 900 };

async function noHorizontalScroll(page: Page) {
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
}

for (const [name, viewport, columns] of [["phone", phone, 2], ["desktop", desktop, 4]] as const) {
  test(`the catalog is a search over the grid of topics (${name})`, async ({ page }) => {
    await page.setViewportSize(viewport);
    await page.goto("/ru/dua");

    await expect(page.getByRole("heading", { level: 1, name: "Ду’а" })).toBeVisible();
    await expect(page.getByText("Ду’а и азкары из проверяемых источников")).toBeVisible();
    const card = page.locator(".dua-topic-card");
    await expect(card).toHaveCount(1);
    await expect(card).toHaveAttribute("href", "/ru/dua/topics/sleep");
    await expect(card).toContainText("Сон и пробуждение");
    await expect(card).toContainText("Перед сном, ночью и при пробуждении");
    await expect(card).toContainText("Ду’а: 3");
    expect(await page.locator(".dua-topic-grid").evaluate(
      (element) => getComputedStyle(element).gridTemplateColumns.split(" ").length,
    )).toBe(columns);
    await noHorizontalScroll(page);

    const search = page.getByRole("searchbox", { name: "Поиск" });
    await search.fill("в");
    await expect(page.getByText("Введите минимум 2 символа для поиска")).toBeVisible();

    // The chapter, printed in capitals, and the topic match by their names.
    await search.fill("пробуждении");
    await expect(page.locator(".dua-chapter-row")).toHaveCount(1);
    await expect(page.locator(".dua-chapter-row")).toContainText("Глава 1");
    await expect(page.locator(".dua-chapter-row")).toContainText("Слова поминания при пробуждении ото сна");
    await expect(page.locator(".dua-topic-tile")).toContainText("Сон и пробуждение");
    await expect(page.locator(".dua-topic-card")).toHaveCount(0);

    // The du'a themselves come from the server, under their chapter.
    await search.fill("воскресение");
    const row = page.locator(".dua-summary-row");
    await expect(row).toHaveCount(1);
    await expect(row).toHaveAttribute("href", "/ru/dua/hisn-al-muslim/1");
    await expect(row).toContainText("#1");
    await expect(page.getByRole("heading", { level: 2, name: "Слова поминания при пробуждении ото сна" })).toBeVisible();
    await expect(page).toHaveURL("/ru/dua?q=%D0%B2%D0%BE%D1%81%D0%BA%D1%80%D0%B5%D1%81%D0%B5%D0%BD%D0%B8%D0%B5");

    // «Back» from the du'a returns to the same search.
    await row.click();
    await expect(page).toHaveURL("/ru/dua/hisn-al-muslim/1");
    await page.goBack();
    await expect(search).toHaveValue("воскресение");
    await expect(page.locator(".dua-summary-row")).toHaveCount(1);

    await search.fill("несуществующее");
    await expect(page.getByText("Подходящие ду’а не найдены")).toBeVisible();
    await search.fill("");
    await expect(page.locator(".dua-topic-card")).toHaveCount(1);
  });
}

test("a topic of several chapters lists them, and a chapter is a feed of du'a cards", async ({ page }) => {
  await page.setViewportSize(phone);
  await page.goto("/ru/dua");
  await page.locator(".dua-topic-card").click();

  await expect(page).toHaveURL("/ru/dua/topics/sleep");
  await expect(page.getByRole("heading", { level: 1, name: "Сон и пробуждение" })).toBeVisible();
  await expect(page.getByText("Перед сном, ночью и при пробуждении")).toBeVisible();
  await expect(page.getByRole("link", { name: "Назад" })).toHaveAttribute("href", "/ru/dua");
  const chapters = page.locator(".dua-chapter-row");
  await expect(chapters).toHaveCount(2);
  await expect(chapters.nth(0)).toContainText("Глава 1");
  await expect(chapters.nth(1)).toContainText("Глава 28");
  await expect(chapters.nth(1)).toContainText("Слова поминания перед сном");
  await expect(page.locator(".dua-card")).toHaveCount(0);

  await chapters.nth(1).click();
  await expect(page).toHaveURL("/ru/dua/hisn-al-muslim/categories/before-sleeping");
  await expect(page.locator(".dua-topbar-title")).toHaveText("Глава 28");
  await expect(page.locator(".dua-topbar-subtitle")).toHaveText("Молитвы из Корана и Сунны");
  await expect(page.getByRole("heading", { level: 1, name: "Слова поминания перед сном", exact: true })).toBeVisible();
  // The chapter returns to its topic's list, as in the app.
  await expect(page.getByRole("link", { name: "Назад" })).toHaveAttribute("href", "/ru/dua/topics/sleep");

  const cards = page.locator(".dua-card");
  await expect(cards).toHaveCount(2);
  const first = cards.first();
  // The basmala stands on its own line, before the surah.
  await expect(first.locator(".dua-arabic-opening")).toHaveText("بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ");
  await expect(first.locator(".dua-arabic-line")).toHaveText("﴿قُلْ هُوَ اللَّهُ أَحَدٌ﴾");
  await expect(first.locator(".dua-meaning")).toHaveText("Прочитать суру «Искренность» три раза.");
  await expect(first.locator(".dua-action-play")).toHaveCount(0);
  await expect(first.getByRole("link", { name: "Открыть ду’а №100" })).toHaveText("1/2");
  await expect(first.getByRole("link", { name: "Открыть ду’а №100" }))
    .toHaveAttribute("href", "/ru/dua/hisn-al-muslim/100");
  await expect(cards.nth(1).locator(".dua-counter")).toHaveCount(0);

  // The counter counts down the three repetitions and starts again.
  const counter = first.locator(".dua-counter");
  await expect(counter).toHaveAccessibleName("Осталось: 3");
  await counter.click();
  await expect(counter).toHaveAccessibleName("Осталось: 2");
  await counter.click();
  await counter.click();
  await expect(counter).toHaveAccessibleName("Готово");
  await expect(counter).toHaveClass(/is-done/);
  await counter.click();
  await expect(counter).toHaveAccessibleName("Осталось: 3");

  // The source opens the sheet with the edition and the checked reference.
  await first.getByRole("button", { name: "[Al-Bukhari 5017.]" }).click();
  const sheet = page.getByRole("dialog", { name: "Источник и проверка" });
  await expect(sheet).toBeVisible();
  await expect(sheet).toContainText("Проверено редакцией");
  await sheet.getByText("Источник и проверка").click();
  await expect(sheet.getByText("Молитвы из Корана и Сунны")).toBeVisible();
  await expect(sheet.getByText("Саид ибн Али ибн Вахб аль-Кахтани")).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(sheet).toBeHidden();

  await expect(page.locator(".dua-side-list")).toBeHidden();
  await noHorizontalScroll(page);
});

test("a wide screen keeps the list of the chapter's du'a beside the feed", async ({ page }) => {
  await page.setViewportSize(desktop);
  await page.goto("/ru/dua/hisn-al-muslim/categories/before-sleeping");

  const list = page.getByRole("navigation", { name: "Ду’а на этой странице" });
  await expect(list).toBeVisible();
  const links = list.getByRole("link");
  await expect(links).toHaveCount(2);
  await expect(links.nth(0)).toHaveAttribute("href", "#dua-hisn-al-muslim-100");
  await expect(links.nth(1)).toContainText("С именем Твоим, о Аллах");
  const listBox = (await list.boundingBox())!;
  const cardBox = (await page.locator(".dua-card").first().boundingBox())!;
  expect(listBox.x + listBox.width).toBeLessThanOrEqual(cardBox.x);
  expect(Math.abs(listBox.y - cardBox.y)).toBeLessThan(2);

  await links.nth(1).click();
  await expect(page).toHaveURL(/#dua-hisn-al-muslim-101$/);
  await noHorizontalScroll(page);
});

for (const [name, viewport] of [["phone", phone], ["desktop", desktop]] as const) {
  test(`a du'a page plays its audio with repeat and speed, and saves it to favourites (${name})`, async ({ page }) => {
    // Keep the media request pending, so Chromium reports no error.
    await page.route("**/audio/ar/1.mp3", () => {});
    await page.setViewportSize(viewport);
    await page.goto("/ru/dua/hisn-al-muslim/1");

    await expect(page.locator(".dua-topbar-title")).toHaveText("Ду’а");
    await expect(page.getByRole("heading", { level: 1, name: "Слова поминания при пробуждении ото сна", exact: true }))
      .toBeVisible();
    await expect(page.getByRole("link", { name: "Назад" }))
      .toHaveAttribute("href", "/ru/dua/hisn-al-muslim/categories/waking-up");
    const card = page.locator(".dua-card");
    await expect(card.locator(".dua-transliteration")).toContainText("Аль-хамду ли-Лляхи");
    await expect(card.locator(".dua-position")).toHaveCount(0);

    const repeat = card.getByRole("button", { name: "Повтор" });
    const speed = card.getByRole("button", { name: "Скорость" });
    await expect(repeat).toBeDisabled();
    await expect(speed).toBeDisabled();
    await card.getByRole("button", { name: "Прослушать ду’а" }).click();
    const audio = page.locator("audio.dua-audio");
    await expect(audio).toHaveAttribute("src", "https://www.hisnmuslim.com/audio/ar/1.mp3");
    await audio.evaluate((element) => void (element as HTMLAudioElement).play());
    await expect(card.getByRole("button", { name: "Приостановить аудио" })).toBeVisible();

    await repeat.click();
    await expect(repeat).toHaveAttribute("aria-pressed", "true");
    expect(await audio.evaluate((element) => (element as HTMLAudioElement).loop)).toBe(true);
    for (const value of [1.25, 1.5, 0.75, 1]) {
      await speed.click();
      await expect(speed).toHaveText(`${value}×`);
      expect(await audio.evaluate((element) => (element as HTMLAudioElement).playbackRate)).toBe(value);
    }

    await card.getByRole("button", { name: "Добавить в избранное" }).click();
    await expect(page.getByRole("status").filter({ hasText: "Добавлено в избранное" })).toBeVisible();
    await expect(card.getByRole("button", { name: "Удалить из избранного" })).toHaveAttribute("aria-pressed", "true");

    // Back to the catalog the way the app goes: du'a, chapter, topic. The
    // favourites lead it and open as their own feed.
    const back = page.getByRole("link", { name: "Назад" });
    await back.click();
    await expect(page).toHaveURL("/ru/dua/hisn-al-muslim/categories/waking-up");
    await back.click();
    await expect(page).toHaveURL("/ru/dua/topics/sleep");
    await back.click();
    await expect(page).toHaveURL("/ru/dua");
    const favorites = page.locator(".dua-topic-card").first();
    await expect(favorites).toContainText("Избранное");
    await expect(favorites).toContainText("Сохранённые ду’а");
    await expect(favorites).toContainText("Ду’а: 1");
    await favorites.click();
    await expect(page).toHaveURL("/ru/dua/favorites");
    await expect(page.getByRole("heading", { level: 1, name: "Избранное" })).toBeVisible();
    await expect(page.locator(".dua-card")).toHaveCount(1);
    await page.getByRole("button", { name: "Удалить из избранного" }).click();
    await expect(page.locator(".dua-card")).toHaveCount(0);
    await expect(page.getByText("Подходящие ду’а не найдены")).toBeVisible();
    // Personal, so not indexed.
    const html = await (await page.request.get("/ru/dua/favorites")).text();
    expect(html).toMatch(/<meta name="robots" content="noindex/);
  });
}

test("Arabic pages run right to left and show no repeated meaning", async ({ page }) => {
  await page.setViewportSize(phone);
  await page.goto("/ar/dua");
  await expect(page.locator("html")).toHaveAttribute("dir", "rtl");
  await expect(page.locator(".dua-topic-card")).toContainText("عدد الأدعية: 3");

  await page.goto("/ar/dua/hisn-al-muslim/categories/before-sleeping");
  await expect(page.locator(".dua-topbar-title")).toHaveText("الباب 28");
  await expect(page.locator(".dua-meaning")).toHaveCount(0);
  // Arrows point the way the page reads; the Latin reference keeps its order.
  expect(await page.locator(".dua-back .dua-flip").evaluate(
    (element) => getComputedStyle(element).transform,
  )).toBe("matrix(-1, 0, 0, 1, 0, 0)");
  await expect(page.locator(".dua-source-link bdi").first()).toHaveText("Al-Bukhari 5017.");
  const back = (await page.locator(".dua-back").boundingBox())!;
  expect(back.x).toBeGreaterThan(phone.width / 2);
  await noHorizontalScroll(page);
});
