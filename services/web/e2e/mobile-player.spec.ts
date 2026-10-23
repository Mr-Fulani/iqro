import { expect, test } from "@playwright/test";
import type { ConsoleMessage, Locator, Page } from "@playwright/test";
import { recitation, surahPlayback, tracks } from "./fixtures/audio";

// The phone player follows the app's mini player (clients/iqro_mobile/lib/features/audio/mini_player.dart):
// a 66 px bar above the bottom navigation, a 60 px round button when collapsed and a
// full-screen player on tap. The mocked audio files are empty, so play() and pause()
// only report their events, as in quran-audio.spec.ts.
async function stubMedia(page: Page) {
  await page.addInitScript(() => {
    Object.defineProperty(HTMLMediaElement.prototype, "play", {
      configurable: true,
      value(this: HTMLMediaElement) {
        this.dispatchEvent(new Event("play"));
        return Promise.resolve();
      },
    });
    Object.defineProperty(HTMLMediaElement.prototype, "pause", {
      configurable: true,
      value(this: HTMLMediaElement) {
        this.dispatchEvent(new Event("pause"));
      },
    });
    Object.defineProperty(HTMLMediaElement.prototype, "load", {
      configurable: true,
      value(this: HTMLMediaElement) {
        queueMicrotask(() => this.dispatchEvent(new Event("loadedmetadata")));
      },
    });
    for (const type of ["emptied", "error"]) {
      window.addEventListener(type, (event) => {
        if (event.target instanceof HTMLMediaElement) event.stopImmediatePropagation();
      }, true);
    }
  });
  await page.route("https://audio.example.test/**", (route) =>
    route.fulfill({ status: 200, contentType: "audio/mpeg", body: "" }),
  );
  await page.route("**/api/web-auth/refresh", (route) => route.fulfill({ status: 401 }));
}

// Network failures the browser logs on its own (the guest session refresh); nothing else may reach the console.
function watchConsole(page: Page): string[] {
  const errors: string[] = [];
  page.on("pageerror", (error) => errors.push(`pageerror: ${error.message}`));
  page.on("console", (message: ConsoleMessage) => {
    if (message.type() !== "error" || message.text().startsWith("Failed to load resource")) return;
    errors.push(`console.error: ${message.text()}`);
  });
  return errors;
}

async function box(locator: Locator) {
  const bounds = await locator.boundingBox();
  expect(bounds).not.toBeNull();
  return bounds!;
}

const scrollWidth = (page: Page) => page.evaluate(() => document.documentElement.scrollWidth);

// The sheet rises for 320 ms; measurements wait for the animation to end.
async function settled(locator: Locator) {
  await expect.poll(() => locator.evaluate((element) => element.getAnimations().length)).toBe(0);
}

const PHONES = [
  { width: 360, height: 740 },
  { width: 390, height: 844 },
  { width: 412, height: 915 },
];

test.beforeEach(async ({ page }) => {
  await stubMedia(page);
});

for (const phone of PHONES) {
  test(`the bar sits above the navigation, opens the full player and collapses at ${phone.width}×${phone.height}`, async ({ page }) => {
    test.setTimeout(90_000);
    const errors = watchConsole(page);
    await page.setViewportSize(phone);
    await page.goto("/ru/audio");

    const bar = page.getByTestId("mobile-audio-player");
    const navigation = page.locator(".mobile-navigation");
    await expect(bar).toBeVisible();
    await expect(page.getByTestId("global-audio-player")).toHaveCount(0);
    // As in the app: 66 px tall, 10 px from the edges, a 6 px gap above the navigation.
    const barBox = await box(bar);
    const navigationBox = await box(navigation);
    expect(barBox.height).toBe(66);
    expect(barBox.x).toBe(10);
    expect(barBox.width).toBe(phone.width - 20);
    expect(barBox.y + barBox.height).toBeLessThanOrEqual(navigationBox.y - 5);
    expect(barBox.y + barBox.height).toBeGreaterThan(navigationBox.y - 8);
    // Nothing plays yet: the bar invites to listen and does not open.
    await expect(bar).toContainText("Слушайте Коран");
    await expect(bar.getByRole("button", { name: "Открыть плеер", exact: true })).toBeDisabled();
    await expect(bar.getByRole("button", { name: "Воспроизвести", exact: true })).toBeDisabled();

    await page.getByRole("button", { name: "Слушать", exact: true }).first().click();
    const audio = bar.locator("audio");
    await expect(audio).toHaveAttribute("src", tracks[0].asset.url);
    await expect(bar.getByRole("button", { name: "Поставить на паузу", exact: true })).toBeVisible();
    await expect(bar).toContainText("Сура 1");
    await expect(bar).toContainText("Махер аль-Муайкли");
    await expect(bar.getByRole("button", { name: "Предыдущая сура", exact: true })).toBeDisabled();
    for (const name of ["Открыть плеер", "Свернуть панель плеера", "Поставить на паузу", "Следующая сура"]) {
      const target = await box(bar.getByRole("button", { name, exact: true }));
      expect(target.width).toBeGreaterThanOrEqual(44);
      expect(target.height).toBeGreaterThanOrEqual(44);
    }
    // The artwork, the collapse button, the title, then the three transport buttons.
    const artwork = await box(bar.locator(".mobile-player-artwork"));
    const collapse = await box(bar.getByRole("button", { name: "Свернуть панель плеера", exact: true }));
    const play = await box(bar.getByRole("button", { name: "Поставить на паузу", exact: true }));
    expect(artwork.width).toBe(44);
    expect(artwork.x).toBeLessThan(collapse.x);
    expect(collapse.x + collapse.width).toBeLessThanOrEqual(play.x);
    expect(play.width).toBe(48);

    // The page keeps its last pixel above the bar.
    await page.evaluate(() => window.scrollTo(0, document.documentElement.scrollHeight));
    const scrolledBar = await box(bar);
    const main = await box(page.locator("main"));
    const footer = await box(page.locator(".app-footer"));
    expect(main.y + main.height).toBeLessThanOrEqual(scrolledBar.y);
    expect(footer.y + footer.height).toBeLessThanOrEqual(scrolledBar.y);
    expect(await scrollWidth(page)).toBeLessThanOrEqual(phone.width);
    await audio.evaluate((element) => {
      (element as HTMLAudioElement).currentTime = 12.5;
    });

    // A tap on the bar opens the full player over everything; the page behind is inert.
    await bar.locator(".mobile-player-titles").click();
    const full = page.getByRole("dialog", { name: "Сейчас играет" });
    await expect(full).toBeVisible();
    await settled(full);
    const fullBox = await box(full);
    expect(fullBox).toEqual({ x: 0, y: 0, width: phone.width, height: phone.height });
    await expect(full.getByRole("button", { name: "Назад", exact: true })).toBeFocused();
    await expect(page.locator(".app-container")).toHaveAttribute("inert", "");
    await expect(page.locator("html")).toHaveClass(/is-mobile-player-open/);
    await expect(full).toHaveAttribute("data-player-background", "bundled:desert-night");
    await expect(full.locator(".global-audio-player-backdrop img")).toHaveAttribute("src", "/player-backgrounds/desert-night.webp");
    await expect(full.getByTestId("player-equalizer")).toHaveCSS("opacity", "1");
    await expect(full.getByRole("slider", { name: "Позиция воспроизведения" })).toBeVisible();
    await expect(full.getByLabel("Быстрая смена чтеца")).toBeVisible();
    await expect(full.getByLabel("Скорость воспроизведения")).toBeVisible();
    await expect(full.getByLabel("Таймер сна")).toBeVisible();
    await expect(full.getByLabel("Режим повтора")).toBeVisible();
    await expect(full.getByRole("button", { name: "Фон плеера" })).toBeVisible();
    const largePlay = await box(full.getByRole("button", { name: "Поставить на паузу", exact: true }));
    expect(largePlay.width).toBe(72);
    expect(largePlay.height).toBe(72);
    expect((await box(full.locator(".mobile-player-artwork"))).width).toBe(210);
    for (const name of ["Назад на 10 секунд", "Предыдущая сура", "Следующая сура", "Вперёд на 10 секунд"]) {
      await expect(full.getByRole("button", { name, exact: true })).toBeVisible();
    }
    expect(await scrollWidth(page)).toBeLessThanOrEqual(phone.width);
    // The same <audio> element keeps playing where it was.
    await expect(full.locator("audio")).toHaveAttribute("src", tracks[0].asset.url);
    expect(await full.locator("audio").evaluate((element) => (element as HTMLAudioElement).currentTime)).toBe(12.5);

    // Esc closes it and hands focus back to the bar.
    await page.keyboard.press("Escape");
    await expect(page.getByRole("dialog")).toHaveCount(0);
    await expect(bar.getByRole("button", { name: "Открыть плеер", exact: true })).toBeFocused();
    await expect(page.locator(".app-container")).not.toHaveAttribute("inert", "");
    await expect(page.locator("html")).not.toHaveClass(/is-mobile-player-open/);
    expect(await audio.evaluate((element) => (element as HTMLAudioElement).currentTime)).toBe(12.5);
    await expect(bar.getByRole("button", { name: "Поставить на паузу", exact: true })).toBeVisible();

    // The back arrow closes it too.
    await bar.locator(".mobile-player-titles").click();
    await full.getByRole("button", { name: "Назад", exact: true }).click();
    await expect(page.getByRole("dialog")).toHaveCount(0);

    // The bar collapses to the 60 px round button at the end of the row and comes back.
    await bar.getByRole("button", { name: "Свернуть панель плеера", exact: true }).click();
    const roundButton = bar.getByRole("button", { name: "Показать панель плеера", exact: true });
    await expect(roundButton).toBeVisible();
    const roundBox = await box(roundButton);
    expect(roundBox.width).toBe(60);
    expect(roundBox.height).toBe(60);
    expect(Math.abs(roundBox.x + roundBox.width - (phone.width - 10))).toBeLessThanOrEqual(1);
    await expect(bar.locator(".mobile-player-sheet-body")).toHaveAttribute("inert", "");
    await expect(bar).toHaveCSS("clip-path", /inset\(3px 0px 3px calc\(100% - 60px\) round 26px\)/);
    expect(await audio.evaluate((element) => (element as HTMLAudioElement).currentTime)).toBe(12.5);
    await roundButton.click();
    await expect(roundButton).toHaveCount(0);
    await expect(bar.locator(".mobile-player-sheet-body")).not.toHaveAttribute("inert", "");
    await expect(bar.getByRole("button", { name: "Открыть плеер", exact: true })).toBeVisible();
    expect(errors).toEqual([]);
  });

  test(`landscape ${phone.height}×${phone.width} keeps the player usable without overflow`, async ({ page }) => {
    const errors = watchConsole(page);
    await page.setViewportSize({ width: phone.height, height: phone.width });
    await page.goto("/ru/audio");
    await page.getByRole("button", { name: "Слушать", exact: true }).first().click();
    if (phone.height <= 768) {
      // Still the phone layout: the bar above the navigation, the full player scrolls.
      const bar = page.getByTestId("mobile-audio-player");
      const navigation = page.locator(".mobile-navigation");
      await expect(bar).toBeVisible();
      const barBox = await box(bar);
      expect(barBox.height).toBe(66);
      expect(barBox.y + barBox.height).toBeLessThanOrEqual((await box(navigation)).y - 5);
      await bar.locator(".mobile-player-titles").click();
      const full = page.getByRole("dialog", { name: "Сейчас играет" });
      await expect(full).toBeVisible();
      await settled(full);
      expect(await box(full)).toEqual({ x: 0, y: 0, width: phone.height, height: phone.width });
      const body = full.locator(".mobile-player-engine");
      expect(await body.evaluate((element) => element.scrollHeight > element.clientHeight)).toBe(true);
      await body.evaluate((element) => element.scrollTo(0, element.scrollHeight));
      await expect(full.getByRole("button", { name: "Фон плеера" })).toBeInViewport();
      await page.keyboard.press("Escape");
      await expect(page.getByRole("dialog")).toHaveCount(0);
    } else {
      // Wider than the bottom navigation: the site is in its desktop layout, with the desktop dock.
      const dock = page.getByTestId("global-audio-player");
      await expect(dock).toBeVisible();
      await expect(page.getByTestId("mobile-audio-player")).toHaveCount(0);
      await expect(page.locator(".mobile-navigation")).toBeHidden();
      const dockBox = await box(dock);
      expect(dockBox.y).toBeGreaterThanOrEqual(0);
      expect(dockBox.y + dockBox.height).toBeLessThanOrEqual(phone.width);
      expect(dockBox.height).toBeLessThan(200);
    }
    expect(await scrollWidth(page)).toBeLessThanOrEqual(phone.height);
    expect(errors).toEqual([]);
  });
}

test("a downward swipe on the header closes the full player; a short one springs back", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/ru/audio");
  await page.getByRole("button", { name: "Слушать", exact: true }).first().click();
  const bar = page.getByTestId("mobile-audio-player");
  await bar.locator(".mobile-player-titles").click();
  const full = page.getByRole("dialog", { name: "Сейчас играет" });
  const head = full.locator(".mobile-player-full-head");
  await expect(head).toHaveCSS("touch-action", "none");
  const touch = { pointerId: 7, pointerType: "touch", isPrimary: true, button: 0, clientX: 200 };

  await head.dispatchEvent("pointerdown", { ...touch, clientY: 40 });
  await head.dispatchEvent("pointermove", { ...touch, clientY: 56 });
  await expect(full).toHaveCSS("transform", "matrix(1, 0, 0, 1, 0, 16)");
  await head.dispatchEvent("pointerup", { ...touch, clientY: 56 });
  await expect(full).toHaveCSS("transform", "none");
  await expect(full).toBeVisible();

  await head.dispatchEvent("pointerdown", { ...touch, clientY: 40 });
  await head.dispatchEvent("pointermove", { ...touch, clientY: 200 });
  await expect(full).toHaveCSS("transform", "matrix(1, 0, 0, 1, 0, 160)");
  await head.dispatchEvent("pointerup", { ...touch, clientY: 200 });
  await expect(page.getByRole("dialog")).toHaveCount(0);
  await expect(bar.getByRole("button", { name: "Открыть плеер", exact: true })).toBeVisible();
});

test("the full player seeks, steps ten seconds and moves to the next surah of the recording", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/ru/audio");
  await page.getByRole("button", { name: "Слушать", exact: true }).first().click();
  const bar = page.getByTestId("mobile-audio-player");
  const audio = bar.locator("audio");
  await expect(audio).toHaveAttribute("src", tracks[0].asset.url);
  await bar.locator(".mobile-player-titles").click();
  const full = page.getByRole("dialog", { name: "Сейчас играет" });
  await expect(full).toContainText("Сура 1 · аят");

  // The timeline covers the timed ayahs of the surah, and ten-second steps stay inside it.
  const segments = surahPlayback(recitation.id, 1)!.segments;
  const endMs = segments[segments.length - 1].end_ms;
  const slider = full.getByRole("slider", { name: "Позиция воспроизведения" });
  await expect(slider).toHaveAttribute("max", String(endMs));
  await slider.evaluate((element) => {
    const input = element as HTMLInputElement;
    const setValue = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value")!.set!;
    setValue.call(input, "1000");
    input.dispatchEvent(new Event("input", { bubbles: true }));
  });
  await expect(full.locator(".mobile-player-times")).toContainText("0:01");
  await expect.poll(() => audio.evaluate((element) => (element as HTMLAudioElement).currentTime)).toBe(1);
  // Ten seconds forward runs past the two-second range: playback finishes at its end.
  await full.getByRole("button", { name: "Вперёд на 10 секунд", exact: true }).click();
  await expect(full).toContainText("Воспроизведение завершено");
  await expect(full.getByRole("button", { name: "Воспроизвести", exact: true })).toBeVisible();
  await expect(full.getByTestId("player-equalizer")).toHaveCSS("opacity", "0");
  expect(await audio.evaluate((element) => (element as HTMLAudioElement).currentTime)).toBe(endMs / 1000);
  // Play starts the range over; ten seconds back stays at its start.
  await full.getByRole("button", { name: "Воспроизвести", exact: true }).click();
  await expect(full.getByRole("button", { name: "Поставить на паузу", exact: true })).toBeVisible();
  await expect(full.getByTestId("player-equalizer")).toHaveCSS("opacity", "1");
  expect(await audio.evaluate((element) => (element as HTMLAudioElement).currentTime)).toBe(segments[0].start_ms / 1000);
  await full.getByRole("button", { name: "Назад на 10 секунд", exact: true }).click();
  expect(await audio.evaluate((element) => (element as HTMLAudioElement).currentTime)).toBe(segments[0].start_ms / 1000);
  // Pause and play keep the place.
  await full.getByRole("button", { name: "Поставить на паузу", exact: true }).click();
  await expect(full.getByRole("button", { name: "Воспроизвести", exact: true })).toBeVisible();
  await expect(full.getByTestId("player-equalizer")).toHaveCSS("opacity", "0");
  await full.getByRole("button", { name: "Воспроизвести", exact: true }).click();
  await expect(full.getByRole("button", { name: "Поставить на паузу", exact: true })).toBeVisible();

  await full.getByRole("button", { name: "Следующая сура", exact: true }).click();
  await expect(audio).toHaveAttribute("src", tracks[1].asset.url);
  await expect(full).toContainText("Сура 2");
  await expect(full.getByRole("button", { name: "Предыдущая сура", exact: true })).toBeEnabled();
  await expect(full.getByRole("button", { name: "Поставить на паузу", exact: true })).toBeVisible();
  await page.keyboard.press("Escape");
  await expect(bar).toContainText("Сура 2");
  // The catalog follows: the second track is the selected one.
  await expect(page.locator(".track-row").nth(1)).toHaveCSS("border-color", "rgb(11, 93, 74)");
  await bar.getByRole("button", { name: "Предыдущая сура", exact: true }).click();
  await expect(audio).toHaveAttribute("src", tracks[0].asset.url);
  await expect(bar).toContainText("Сура 1");
});

test("the Arabic bar mirrors its layout and the full player stays within the screen", async ({ page }) => {
  const errors = watchConsole(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/ar/audio");
  await expect(page.locator("html")).toHaveAttribute("dir", "rtl");
  await page.getByRole("button", { name: "استمع", exact: true }).first().click();
  const bar = page.getByTestId("mobile-audio-player");
  await expect(bar.locator("audio")).toHaveAttribute("src", tracks[0].asset.url);
  const artwork = await box(bar.locator(".mobile-player-artwork"));
  const play = await box(bar.getByRole("button", { name: "إيقاف مؤقت", exact: true }));
  const collapse = await box(bar.getByRole("button", { name: "إخفاء شريط المشغل", exact: true }));
  // Portrait at the right edge, transport at the left.
  expect(artwork.x).toBeGreaterThan(play.x);
  expect(collapse.x).toBeLessThan(artwork.x);
  expect(collapse.x).toBeGreaterThan(play.x);
  await expect(bar.locator(".mobile-player-icon .is-directional").first()).toHaveCSS("transform", "matrix(-1, 0, 0, 1, 0, 0)");
  expect(await scrollWidth(page)).toBeLessThanOrEqual(390);

  await bar.locator(".mobile-player-titles").click();
  const full = page.getByRole("dialog", { name: "يُشغّل الآن" });
  await expect(full).toBeVisible();
  await settled(full);
  expect(await box(full)).toEqual({ x: 0, y: 0, width: 390, height: 844 });
  const back = await box(full.getByRole("button", { name: "رجوع", exact: true }));
  expect(back.x).toBeGreaterThan(390 - 60);
  expect(await scrollWidth(page)).toBeLessThanOrEqual(390);

  await bar.locator(".mobile-player-full-head").dispatchEvent("pointerdown", { pointerId: 3, pointerType: "touch", isPrimary: true, button: 0, clientX: 200, clientY: 40 });
  await bar.locator(".mobile-player-full-head").dispatchEvent("pointerup", { pointerId: 3, pointerType: "touch", isPrimary: true, button: 0, clientX: 200, clientY: 240 });
  await expect(page.getByRole("dialog")).toHaveCount(0);

  await bar.getByRole("button", { name: "إخفاء شريط المشغل", exact: true }).click();
  const roundButton = await box(bar.getByRole("button", { name: "إظهار شريط المشغل", exact: true }));
  expect(Math.abs(roundButton.x - 10)).toBeLessThanOrEqual(1);
  await expect(bar).toHaveCSS("clip-path", /inset\(3px calc\(100% - 60px\) 3px 0px round 26px\)/);
  expect(errors).toEqual([]);
});

test("with reduced motion the bar and the full player switch without transitions", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/ru/audio");
  const bar = page.getByTestId("mobile-audio-player");
  await expect(bar).toHaveCSS("transition-duration", "0s");
  await page.getByRole("button", { name: "Слушать", exact: true }).first().click();
  await bar.locator(".mobile-player-titles").click();
  const full = page.getByRole("dialog", { name: "Сейчас играет" });
  await expect(full).toHaveCSS("animation-name", "none");
  await expect(full).toHaveCSS("transition-duration", "0s");
  await page.keyboard.press("Escape");
  await expect(page.getByRole("dialog")).toHaveCount(0);
  await bar.getByRole("button", { name: "Свернуть панель плеера", exact: true }).click();
  await expect(bar.getByRole("button", { name: "Показать панель плеера", exact: true })).toHaveCSS("animation-name", "none");
});

test("a tablet shows the bar above its navigation and the desktop keeps the dock", async ({ page }) => {
  await page.setViewportSize({ width: 768, height: 1024 });
  await page.goto("/ru/audio");
  await page.getByRole("button", { name: "Слушать", exact: true }).first().click();
  const bar = page.getByTestId("mobile-audio-player");
  await expect(bar).toBeVisible();
  const barBox = await box(bar);
  expect(barBox.height).toBe(66);
  expect(barBox.width).toBe(748);
  expect(barBox.y + barBox.height).toBeLessThanOrEqual((await box(page.locator(".mobile-navigation"))).y - 5);
  await bar.locator("audio").evaluate((element) => {
    (element as HTMLAudioElement).currentTime = 7;
  });

  // Growing past the navigation's width swaps the bar for the dock around the same <audio>.
  await page.setViewportSize({ width: 1024, height: 768 });
  const dock = page.getByTestId("global-audio-player");
  await expect(dock).toBeVisible();
  await expect(bar).toHaveCount(0);
  await expect(dock.locator("audio")).toHaveAttribute("src", tracks[0].asset.url);
  expect(await dock.locator("audio").evaluate((element) => (element as HTMLAudioElement).currentTime)).toBe(7);
  await expect(dock.getByRole("button", { name: "Развернуть плеер", exact: true })).toBeVisible();
  await expect(dock.getByLabel("Быстрая смена чтеца")).toBeVisible();
});
