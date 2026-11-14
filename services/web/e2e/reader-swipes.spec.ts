import { devices, expect, type Locator, type Page, test } from "@playwright/test";

type Point = { x: number; y: number };

/** A finger moving in small steps, as a real one does (CDP touch events). */
async function finger(page: Page, from: Point, to: Point, holdMs = 0) {
  const session = await page.context().newCDPSession(page);
  await session.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [from] });
  if (holdMs) await page.waitForTimeout(holdMs);
  for (let step = 1; step <= 12; step += 1) {
    const point = { x: from.x + (to.x - from.x) * step / 12, y: from.y + (to.y - from.y) * step / 12 };
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
  // A phone opens the full-screen Mushaf: the switch is in its settings.
  const immersive = await toolbar.waitFor({ timeout: 4000 }).then(() => true, () => false);
  if (immersive) await toolbar.click();
  await toText.click();
  await expect(page.locator(`#quran-ayah-${surah}-${surah === 1 ? 5 : 2}`)).toBeVisible();
}

/** A swipe across the Arabic of an ayah's card, half the screen to the right (1) or left (-1). */
async function swipeAyah(page: Page, ayah: number, way: 1 | -1, surah = 1) {
  const words = page.locator(`#quran-ayah-${surah}-${ayah} .quran-arabic-text`);
  await words.scrollIntoViewIfNeeded();
  const from = await centre(words);
  const width = page.viewportSize()!.width;
  const start = { x: way > 0 ? width * 0.25 : width * 0.75, y: from.y };
  await finger(page, start, { x: start.x + way * width * 0.5, y: from.y });
}

const plainText = (page: Page) => page.getByTestId("plain-text-reader");

const layouts = [
  { name: "a phone", use: { viewport: devices["Pixel 7"].viewport, userAgent: devices["Pixel 7"].userAgent,
    deviceScaleFactor: devices["Pixel 7"].deviceScaleFactor, isMobile: true, hasTouch: true } },
  { name: "a phone in landscape", use: { viewport: { width: 915, height: 412 }, isMobile: true, hasTouch: true } },
  { name: "a tablet", use: { viewport: { width: 820, height: 1180 }, isMobile: true, hasTouch: true } },
  { name: "a tablet in landscape", use: { viewport: { width: 1180, height: 820 }, isMobile: true, hasTouch: true } },
];

for (const layout of layouts) {
  test.describe(`text swipes on ${layout.name}`, () => {
    test.use(layout.use);

    test("a swipe right turns in the plain Arabic text at that ayah, a swipe back returns to it", async ({ page }) => {
      await openText(page);
      await swipeAyah(page, 5, 1);

      const reader = plainText(page);
      await expect(reader).toBeVisible();
      await expect(page.getByTestId("plain-text-place")).toHaveText("Аят 5 · стр. 1");
      // Only the Arabic: no translation, no ayah buttons, no close button.
      await expect(reader.locator(".ayah-translation, .ayah-action-buttons")).toHaveCount(0);
      // The size and, at the end, the next surah's card: nothing else.
      await expect(reader.getByRole("button")).toHaveCount(2);
      await expect(reader.getByTestId("next-surah-card")).toHaveCount(1);
      await expect(reader.locator('[data-word-key="1:5:1"]')).toHaveClass(/is-word-marked/);
      await expect(reader.locator('[data-word-key="1:4:1"]')).not.toHaveClass(/is-word-marked/);

      const sheet = await centre(reader.locator(".plain-text-scroll"));
      const width = page.viewportSize()!.width;
      await finger(page, { x: width * 0.75, y: sheet.y }, { x: width * 0.25, y: sheet.y });
      await expect(reader).toHaveCount(0);
      await expect(page.locator("#quran-ayah-1-5")).toHaveClass(/is-navigation-target/);
    });

    test("a finger that drifts sideways leaves the text in place; a clear swipe still pulls it", async ({ page }) => {
      await openText(page);
      const surface = page.locator(".reader-swipe-surface");
      const words = page.locator("#quran-ayah-1-5 .quran-arabic-text");
      await words.scrollIntoViewIfNeeded();
      const from = await centre(words);
      const session = await page.context().newCDPSession(page);
      /** The text's sideways shift with the finger still down, `to` away from where it touched. */
      const shiftAt = async (to: Point) => {
        await session.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [from] });
        for (let step = 1; step <= 8; step += 1) {
          await session.send("Input.dispatchTouchEvent", { type: "touchMove",
            touchPoints: [{ x: from.x + to.x * step / 8, y: from.y + to.y * step / 8 }] });
        }
        const shift = await surface.evaluate((element) => new DOMMatrix(getComputedStyle(element).transform).m41);
        await session.send("Input.dispatchTouchEvent", { type: "touchEnd", touchPoints: [] });
        await expect(surface).toHaveCSS("transform", "none");
        return shift;
      };
      // A thumb resting on the text and shifting a little.
      expect(await shiftAt({ x: 20, y: 2 })).toBe(0);
      // A scroll that starts aslant.
      expect(await shiftAt({ x: 70, y: -40 })).toBe(0);
      expect(await shiftAt({ x: -70, y: 40 })).toBe(0);
      // Across the text: it follows the finger.
      expect(await shiftAt({ x: 90, y: 6 })).toBeGreaterThan(20);
      await session.detach();
      await expect(plainText(page)).toHaveCount(0);
    });

    // The page turning in is checked where the test API has the Mushaf page:
    // quran-audio.spec.ts, «a swipe left on the text turns in its Mushaf page».
    test("a swipe left opens the Mushaf", async ({ page }) => {
      await openText(page);
      await swipeAyah(page, 6, -1);
      await expect(page.locator(".quran-page-layout").filter({ visible: true })).toHaveClass(/is-mushaf-mode/);
      await expect(plainText(page)).toHaveCount(0);
    });

    test("the size reflows the plain text and keeps its ayah", async ({ page }) => {
      await openText(page);
      await swipeAyah(page, 3, 1);
      const body = plainText(page).locator(".plain-text-body");
      // Its own height: on screen the sheet may still be turning in.
      const before = await body.evaluate((element) => (element as HTMLElement).offsetHeight);

      await page.getByTestId("plain-text-size").click();
      const range = page.getByRole("slider", { name: "Размер арабского текста" });
      await range.fill("72");
      await expect(body).toHaveCSS("font-size", "72px");
      expect(await body.evaluate((element) => (element as HTMLElement).offsetHeight)).toBeGreaterThan(before);
      await expect(page.getByTestId("plain-text-place")).toHaveText("Аят 3 · стр. 1");

      // A sheet on a phone, a panel by the button on a tablet.
      const panel = (await page.locator(".plain-text-size-panel").boundingBox())!;
      const viewport = page.viewportSize()!;
      const tablet = viewport.width >= 600 && viewport.height >= 600;
      expect(panel.width).toBeCloseTo(tablet ? 340 : viewport.width, -1);

      await page.reload();
      await openText(page);
      await swipeAyah(page, 3, 1);
      await expect(plainText(page).locator(".plain-text-body")).toHaveCSS("font-size", "72px");
    });
  });
}

test.describe("the plain text announces a quarter of a hizb", () => {
  test.use(layouts[0].use);

  test("a scroll to the quarter's first ayah shows the pill, and again after coming back", async ({ page }) => {
    // The page loads the quarters with these lists, which the test API lacks.
    await page.route(/\/api\/v1\/quran\/editions\/madani-hafs\/(juz|hizb)(\?.*)?$/, (route) => route.fulfill({ json: [] }));
    await page.route(/\/api\/v1\/quran\/editions\/madani-hafs\/rub-el-hizb(\?.*)?$/, (route) => route.fulfill({ json: [{
      number: 1, hizb_number: 1, quarter_number: 1,
      start_ayah: { id: "quarter-start", surah: 1, number: 1 },
      end_ayah: { id: "quarter-end", surah: 1, number: 7 },
      start_page: 1, end_page: 1,
    }] }));
    await openText(page);
    await swipeAyah(page, 5, 1);
    const reader = plainText(page);
    await expect(reader).toBeVisible();
    const mark = page.getByTestId("quran-quarter-mark");
    const first = reader.locator('[data-word-key="1:1:1"]');
    // Larger letters, so that the quarter's ayah is off screen from the end.
    await reader.locator(".plain-text-body").evaluate((body) => { (body as HTMLElement).style.fontSize = "72px"; });
    const scroll = (top: number) => reader.locator(".plain-text-scroll").evaluate((sheet, to) => {
      sheet.scrollTop = to < 0 ? sheet.scrollHeight : to;
    }, top);
    await scroll(-1);
    await expect(first).not.toBeInViewport();
    await page.waitForTimeout(600);
    await expect(mark).toHaveCount(0);

    await scroll(0);
    await expect(page.getByRole("status").filter({ hasText: "Джуз 1" })).toBeVisible();
    await expect(first).toHaveClass(/is-word-marked/);
    await expect(mark).toHaveCount(0, { timeout: 5_000 });
    await expect(first).not.toHaveClass(/is-word-marked/);

    await scroll(-1);
    await page.waitForTimeout(600);
    await scroll(0);
    await expect(page.getByRole("status").filter({ hasText: "Джуз 1" })).toBeVisible();
  });
});

test.describe("the hint that the text can be swiped", () => {
  test.use(layouts[0].use);

  const hint = (page: Page) => page.getByTestId("reader-swipe-hint");
  const shift = (page: Page) => page.locator(".reader-swipe-surface").evaluate((surface) => (
    new DOMMatrixReadOnly(getComputedStyle(surface).transform).m41
  ));

  /** The ayahs themselves, past the reading settings above them. */
  const toAyahs = (page: Page) => page.locator("#quran-ayah-1-4").evaluate((card) => card.scrollIntoView({ block: "center" }));

  test("once the ayahs are on screen a hand pulls the text right, then left, and goes", async ({ page }) => {
    await openText(page);
    // The settings above the text fill the screen: nothing to swipe yet.
    await page.waitForTimeout(2000);
    await expect(hint(page)).toHaveCount(0);
    await toAyahs(page);
    await expect(hint(page)).toHaveText("Свайп вправо — арабский текст, влево — Мусхаф");
    await expect(page.locator(".reader-swipe-reveal.is-right")).toHaveText(/Арабский текст/);
    await expect.poll(() => shift(page)).toBeGreaterThan(100);
    await expect(page.locator(".reader-swipe-reveal.is-left")).toHaveText(/Мусхаф/);
    await expect.poll(() => shift(page)).toBeLessThan(-100);
    await expect(hint(page)).toHaveCount(0);
    expect(await shift(page)).toBe(0);
    // It opened nothing, and is counted.
    await expect(plainText(page)).toHaveCount(0);
    expect(await page.evaluate(() => localStorage.getItem("iqro_reader_swipe_hint_v1"))).toBe("1");
  });

  test("a touch ends it at once; after a swipe it never comes", async ({ page }) => {
    await openText(page);
    await toAyahs(page);
    await expect(hint(page)).toBeVisible();
    const session = await page.context().newCDPSession(page);
    await session.send("Input.dispatchTouchEvent", { type: "touchStart", touchPoints: [{ x: 200, y: 80 }] });
    await expect(hint(page)).toHaveCount(0, { timeout: 500 });
    await session.send("Input.dispatchTouchEvent", { type: "touchCancel", touchPoints: [] });
    await session.detach();
    expect(await shift(page)).toBe(0);

    await swipeAyah(page, 5, 1);
    await expect(plainText(page)).toBeVisible();
    expect(await page.evaluate(() => localStorage.getItem("iqro_reader_swipe_hint_v1"))).toBe("3");
    await page.reload();
    await openText(page);
    await toAyahs(page);
    await page.waitForTimeout(3000);
    await expect(hint(page)).toHaveCount(0);
  });

  test("with reduced motion it stands still and the text does not move", async ({ page }) => {
    await page.emulateMedia({ reducedMotion: "reduce" });
    await openText(page);
    await toAyahs(page);
    await expect(hint(page)).toBeVisible();
    const hand = await hint(page).locator("svg").boundingBox();
    await page.waitForTimeout(1500);
    expect(await shift(page)).toBe(0);
    expect(await hint(page).locator("svg").boundingBox()).toEqual(hand);
    await expect(hint(page)).toHaveCount(0, { timeout: 5_000 });
  });
});

test.describe("text swipes leave other gestures alone", () => {
  test.use(layouts[0].use);

  test("scrolling, the screen edge and selected words turn nothing", async ({ page }) => {
    await openText(page);
    const words = page.locator("#quran-ayah-1-4 .quran-arabic-text");
    const from = await centre(words);
    // Up and down: the page scrolls.
    await finger(page, from, { x: from.x + 40, y: from.y - 200 });
    // From the very edge: the browser's back gesture.
    const edge = await centre(page.locator("#quran-ayah-1-5 .quran-arabic-text"));
    await finger(page, { x: 8, y: edge.y }, { x: 260, y: edge.y });
    await expect(plainText(page)).toHaveCount(0);
    await expect(page.locator(".quran-page-layout").filter({ visible: true })).not.toHaveClass(/is-mushaf-mode/);

    // Held, a word is selected; a swipe then pulls nothing.
    const held = page.locator('[data-word-key="1:5:2"]');
    await held.scrollIntoViewIfNeeded();
    const word = await centre(held);
    await finger(page, word, word, 450);
    await expect(page.getByTestId("word-range-bar")).toBeVisible();
    await finger(page, { x: 100, y: word.y }, { x: 320, y: word.y });
    await expect(plainText(page)).toHaveCount(0);
  });
});

test("a mouse on a computer turns no page", async ({ page }) => {
  await openText(page);
  const from = await centre(page.locator("#quran-ayah-1-5 .quran-arabic-text"));
  await page.mouse.move(from.x, from.y);
  await page.mouse.down();
  await page.mouse.move(from.x + 300, from.y, { steps: 12 });
  await page.mouse.up();
  await expect(plainText(page)).toHaveCount(0);
  // Nor is a mouse told about swipes.
  await page.locator("#quran-ayah-1-4").evaluate((card) => card.scrollIntoView({ block: "center" }));
  await page.waitForTimeout(3000);
  await expect(page.getByTestId("reader-swipe-hint")).toHaveCount(0);
  await expect(page.locator(".quran-page-layout").filter({ visible: true })).not.toHaveClass(/is-mushaf-mode/);
});
