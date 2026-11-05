import { devices, expect, type Locator, type Page, test } from "@playwright/test";

type Point = { x: number; y: number };

const surahs = [
  { number: 1, name_ar: "الفاتحة", name_en: "Al-Fatihah", name_ru: "Аль-Фатиха", revelation_type: "meccan", ayah_count: 7, first_page: 1 },
  { number: 2, name_ar: "البقرة", name_en: "Al-Baqarah", name_ru: "Аль-Бакара", revelation_type: "medinan", ayah_count: 3, first_page: 2 },
  { number: 113, name_ar: "الفلق", name_en: "Al-Falaq", name_ru: "Аль-Фалак", revelation_type: "meccan", ayah_count: 5, first_page: 604 },
  { number: 114, name_ar: "الناس", name_en: "An-Nas", name_ru: "Ан-Нас", revelation_type: "meccan", ayah_count: 3, first_page: 604 },
].map((surah) => ({ ...surah, id: `00000000-0000-0000-0001-${String(surah.number).padStart(12, "0")}` }));

const texts: Record<number, string[]> = {
  2: [
    "بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ الٓمٓ",
    "ذَٰلِكَ ٱلْكِتَٰبُ لَا رَيْبَ ۛ فِيهِ ۛ هُدًى لِّلْمُتَّقِينَ",
    "ٱلَّذِينَ يُؤْمِنُونَ بِٱلْغَيْبِ وَيُقِيمُونَ ٱلصَّلَوٰةَ وَمِمَّا رَزَقْنَٰهُمْ يُنفِقُونَ",
  ],
  114: [
    "بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ قُلْ أَعُوذُ بِرَبِّ ٱلنَّاسِ",
    "مَلِكِ ٱلنَّاسِ",
    "إِلَٰهِ ٱلنَّاسِ",
  ],
};

/** Al-Baqarah and an-Nas beside al-Fatiha, which the test API already has. */
async function mockSurahs(page: Page) {
  await page.route(/\/api\/v1\/quran\/editions\/madani-hafs\/surahs(\?.*)?$/, (route) => route.fulfill({ json: surahs }));
  // The page loads the surahs with these lists, which the test API lacks.
  await page.route(/\/api\/v1\/quran\/editions\/madani-hafs\/(juz|hizb|rub-el-hizb)(\?.*)?$/, (route) => route.fulfill({ json: [] }));
  await page.route(/\/api\/v1\/quran\/editions\/madani-hafs\/surahs\/(2|114)\/ayahs/, (route) => {
    const surah = Number(/surahs\/(\d+)\/ayahs/.exec(route.request().url())![1]);
    return route.fulfill({
      json: texts[surah].map((text, index) => ({
        id: `00000000-0000-0000-0002-${String(surah * 1000 + index + 1).padStart(12, "0")}`,
        edition_code: "madani-hafs",
        content_version: "1.0.0",
        surah_number: surah,
        number: index + 1,
        text_uthmani: text,
        juz_number: surah === 2 ? 1 : 30,
        hizb_number: 1,
        rub_el_hizb_number: 1,
        pages: [surah === 2 ? 2 : 604],
      })),
    });
  });
}

/** A finger moving in small steps, as a real one does (CDP touch events). */
async function finger(page: Page, from: Point, to: Point) {
  const session = await page.context().newCDPSession(page);
  await session.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [from] });
  for (let step = 1; step <= 14; step += 1) {
    const point = { x: from.x + (to.x - from.x) * step / 14, y: from.y + (to.y - from.y) * step / 14 };
    await session.send("Input.dispatchTouchEvent", { type: "touchMove", touchPoints: [point] });
    await page.waitForTimeout(16);
  }
  await session.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
  await session.detach();
}

async function centre(locator: Locator): Promise<Point> {
  const box = (await locator.boundingBox())!;
  return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
}

/** The Quran text, the cards with translation and buttons. */
async function openText(page: Page, surah = 1) {
  await page.goto(surah === 1 ? "/ru/quran" : `/ru/quran?surah=${surah}`);
  const toText = page.getByRole("button", { name: "📜 Текст", exact: true });
  const toolbar = page.getByRole("toolbar").getByRole("button", { name: "Настройки чтения", exact: true });
  const immersive = await toolbar.waitFor({ timeout: 4000 }).then(() => true, () => false);
  if (immersive) await toolbar.click();
  await toText.click();
  await expect(page.locator(`#quran-ayah-${surah}-2`)).toBeVisible();
}

const phone = { viewport: devices["Pixel 7"].viewport, userAgent: devices["Pixel 7"].userAgent,
  deviceScaleFactor: devices["Pixel 7"].deviceScaleFactor, isMobile: true, hasTouch: true };

test.describe("the next surah on a computer", () => {
  test("a click on the card at the end opens the next surah from its first ayah", async ({ page }) => {
    await mockSurahs(page);
    await openText(page);
    const card = page.getByTestId("next-surah-card");
    await card.scrollIntoViewIfNeeded();
    await expect(card).toContainText("2. Аль-Бакара");
    await expect(card).toContainText("Потяните вверх или нажмите");
    await card.click();
    await expect(page.locator("#quran-ayah-2-1")).toBeVisible();
    await expect(page.getByTestId("next-surah-card")).toContainText("3.");
    await expect(page.locator(".quran-content-surface")).toHaveClass(/is-next-surah/);
  });

  test("after an-Nas the Quran ends, with a way to the list of surahs", async ({ page }) => {
    await mockSurahs(page);
    await openText(page, 114);
    const end = page.getByTestId("quran-end");
    await end.scrollIntoViewIfNeeded();
    await expect(end).toContainText("Конец Корана");
    await expect(end.getByRole("link", { name: "К списку сур" })).toHaveAttribute("href", "/ru/quran/madani-hafs");
    await expect(page.getByTestId("next-surah-card")).toHaveCount(0);
  });
});

test.describe("the next surah on a phone", () => {
  test.use(phone);

  test("a pull past the end opens the next surah; a short one does not", async ({ page }) => {
    await mockSurahs(page);
    await openText(page);
    const card = page.getByTestId("next-surah-card");
    await card.scrollIntoViewIfNeeded();
    await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
    const at = await centre(card);

    await finger(page, at, { x: at.x, y: at.y - 60 });
    await page.waitForTimeout(300);
    await expect(page.locator("#quran-ayah-1-7")).toBeAttached();

    await finger(page, at, { x: at.x, y: at.y - 220 });
    await expect(page.locator("#quran-ayah-2-1")).toBeVisible();
    await expect(page.locator("#quran-ayah-1-7")).toHaveCount(0);
    // From its start: the page does not stay at the end where the pull was.
    await page.waitForTimeout(800);
    const first = (await page.locator("#quran-ayah-2-1").boundingBox())!;
    expect(first.y).toBeGreaterThan(0);
    expect(first.y).toBeLessThan(page.viewportSize()!.height / 2);
  });

  test("the plain text moves on to the next surah and draws its lines out to both edges", async ({ page }) => {
    await mockSurahs(page);
    await openText(page);
    const words = page.locator("#quran-ayah-1-5 .quran-arabic-text");
    await words.scrollIntoViewIfNeeded();
    const from = await centre(words);
    const width = page.viewportSize()!.width;
    await finger(page, { x: width * 0.25, y: from.y }, { x: width * 0.75, y: from.y });
    const reader = page.getByTestId("plain-text-reader");
    await expect(reader).toBeVisible();

    // Kashida: a line that is not an ayah's last is drawn out to the edge.
    await page.getByTestId("plain-text-size").click();
    await page.getByRole("slider", { name: "Размер арабского текста" }).fill("64");
    await page.locator(".plain-text-size-backdrop").click();
    await expect(reader.locator(".plain-text-ayah br").first()).toBeAttached();
    expect(await reader.locator(".plain-text-ayah").evaluateAll((ayahs) => ayahs.some((ayah) => ayah.textContent!.includes("ـ")))).toBe(true);

    const card = reader.getByTestId("next-surah-card");
    await card.scrollIntoViewIfNeeded();
    await expect(card).toContainText("سُورَةُ البقرة");
    await card.click();
    await expect(reader.locator('[data-word-key="2:1:1"]')).toBeVisible();
    await expect(page.getByTestId("plain-text-place")).toHaveText("Аят ١ · стр. ٢");

    // Back to the cards: on the new surah.
    const sheet = await centre(reader.locator(".plain-text-scroll"));
    await finger(page, { x: width * 0.75, y: sheet.y }, { x: width * 0.25, y: sheet.y });
    await expect(reader).toHaveCount(0);
    await expect(page.locator("#quran-ayah-2-1")).toBeVisible();
  });
});
