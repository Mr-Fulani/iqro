import { expect, test } from "@playwright/test";
import type { Locator, Page } from "@playwright/test";
import {
  abdulBaset,
  abdulBasetRecitations,
  alternateReciter,
  alternateRecitation,
  alternateTracks,
  recitation,
  surahPlayback,
  tracks,
} from "./fixtures/audio";
import type { Recitation } from "../lib/api";

// The Audio tab's queue (docs/audio-listening-queue.md): after a surah the
// player moves on by the mode, the buttons and the lock screen step through
// the held surahs, a reciter's recordings switch in the player, and the place
// survives a reload. The mocked audio files are empty, so play() and pause()
// only report their events and a test moves the clock itself.
async function stubMedia(page: Page) {
  await page.addInitScript(() => {
    const handlers: Record<string, (() => void) | null> = {};
    Object.defineProperty(window, "__mediaSessionHandlers", { configurable: true, value: handlers });
    Object.defineProperty(window, "MediaMetadata", {
      configurable: true,
      value: class MediaMetadataMock {
        constructor(init: object) {
          Object.assign(this, init);
        }
      },
    });
    Object.defineProperty(navigator, "mediaSession", {
      configurable: true,
      value: {
        metadata: null,
        playbackState: "none",
        setActionHandler(action: string, handler: (() => void) | null) {
          handlers[action] = handler;
        },
        setPositionState() {},
      },
    });
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
    // The browser's own loading of the empty files would reset the clock; the stub keeps it.
    const clock = new WeakMap<HTMLMediaElement, number>();
    Object.defineProperty(HTMLMediaElement.prototype, "currentTime", {
      configurable: true,
      get(this: HTMLMediaElement) {
        return clock.get(this) ?? 0;
      },
      set(this: HTMLMediaElement, value: number) {
        clock.set(this, value);
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

/** Plays through the fixture surah's two timed ayahs to its end, as the clock would. */
async function finishSurah(audio: Locator) {
  await audio.evaluate((element) => {
    const media = element as HTMLAudioElement;
    media.currentTime = 1.5;
    media.dispatchEvent(new Event("timeupdate"));
    media.currentTime = 2;
    media.dispatchEvent(new Event("timeupdate"));
  });
}

async function pressMediaKey(page: Page, action: "nexttrack" | "previoustrack") {
  await page.evaluate((name) => {
    (window as unknown as { __mediaSessionHandlers: Record<string, (() => void) | null> })
      .__mediaSessionHandlers[name]?.();
  }, action);
}

test.beforeEach(async ({ page }) => {
  await stubMedia(page);
});

test("the queue moves on after a surah, stops in the stop mode and loops past the last surah", async ({ page }) => {
  await page.goto("/ru/audio");
  await page.getByTestId("audio-whole-quran").click();
  const player = page.getByTestId("global-audio-player");
  const audio = player.locator("audio");
  await expect(audio).toHaveAttribute("src", tracks[0].asset.url);
  // The player names the surah with its number, as the app does.
  await expect(player.locator(".segmented-audio-summary strong")).toHaveText("1 · Аль-Фатиха");
  // Compact, the dock keeps one row: the previous and next surah and the queue join its buttons.
  await expect(player.getByRole("button", { name: "Предыдущая сура", exact: true })).toBeDisabled();
  await expect(player.getByRole("button", { name: "Следующая сура", exact: true })).toBeEnabled();
  expect((await player.boundingBox())!.height).toBeLessThan(130);
  await player.getByRole("button", { name: "Развернуть плеер", exact: true }).click();
  await expect(player.locator(".listening-queue-up-next")).toHaveText("Далее: Сура 2");

  // "Continue": the next surah starts by itself.
  await finishSurah(audio);
  await expect(audio).toHaveAttribute("src", tracks[1].asset.url);
  await expect(player.getByText("Воспроизводится", { exact: true })).toBeVisible();

  // "Stop": the surah ends and the player rests.
  await player.locator(".listening-queue-bar").getByLabel("После суры").selectOption("stop");
  await expect(player.locator(".listening-queue-up-next")).toHaveText("");
  await finishSurah(audio);
  await expect(player.getByText("Воспроизведение завершено", { exact: true })).toBeVisible();
  await expect(audio).toHaveAttribute("src", tracks[1].asset.url);

  // The buttons and the lock screen step by surah.
  await player.getByRole("button", { name: "Следующая сура", exact: true }).click();
  await expect(audio).toHaveAttribute("src", tracks[2].asset.url);
  await pressMediaKey(page, "nexttrack");
  await expect(audio).toHaveAttribute("src", tracks[3].asset.url);
  await pressMediaKey(page, "previoustrack");
  await expect(audio).toHaveAttribute("src", tracks[2].asset.url);

  // The queue list plays any surah; "Loop" goes from the last back to the first.
  await player.getByRole("button", { name: "Очередь", exact: true }).click();
  const queue = player.getByTestId("listening-queue");
  await expect(queue.locator(".listening-queue-row[aria-current='true']")).toHaveText("Сура 3");
  await queue.locator(".listening-queue-row").nth(113).click();
  await expect(audio).toHaveAttribute("src", tracks[113].asset.url);
  await expect(player.getByRole("button", { name: "Следующая сура", exact: true })).toBeDisabled();
  await queue.getByRole("button", { name: "По кругу", exact: true }).click();
  await expect(queue.getByRole("button", { name: "По кругу", exact: true })).toHaveAttribute("aria-pressed", "true");
  await expect(player.locator(".listening-queue-bar").getByLabel("После суры")).toHaveValue("loop");
  await expect(player.getByRole("button", { name: "Следующая сура", exact: true })).toBeEnabled();
  await audio.evaluate((element) => void (element as HTMLAudioElement).play());
  await finishSurah(audio);
  await expect(audio).toHaveAttribute("src", tracks[0].asset.url);
  await queue.getByRole("button", { name: "Закрыть очередь", exact: true }).click();
  await expect(queue).toBeHidden();
});

test("the saved place comes back paused after a reload and plays on from there", async ({ page }) => {
  await page.goto("/ru/audio");
  await page.locator(".track-row").nth(4).getByRole("button", { name: "Слушать отсюда", exact: true }).click();
  const player = page.getByTestId("global-audio-player");
  const audio = player.locator("audio");
  await expect(audio).toHaveAttribute("src", tracks[4].asset.url);
  await player.getByRole("button", { name: "Развернуть плеер", exact: true }).click();
  await player.locator(".listening-queue-bar").getByLabel("После суры").selectOption("loop");
  await audio.evaluate((element) => {
    const media = element as HTMLAudioElement;
    media.currentTime = 1.2;
    media.dispatchEvent(new Event("timeupdate"));
    media.pause();
  });
  await expect(player.getByText("Пауза · позиция сохранена", { exact: true })).toBeVisible();

  await page.reload();
  await expect(audio).toHaveAttribute("src", tracks[4].asset.url);
  await player.getByRole("button", { name: "Развернуть плеер", exact: true }).click();
  await expect(player.locator(".listening-queue-bar").getByLabel("После суры")).toHaveValue("loop");
  const resume = page.getByRole("button", { name: /Продолжить с места/ });
  await expect(resume).toContainText("Сура 5 · 0:01");
  await expect.poll(() => audio.evaluate((element) => (element as HTMLAudioElement).currentTime)).toBe(1.2);
  await expect(player.locator(".segmented-audio-summary")).toContainText("аят 5:2");

  await resume.click();
  await expect(player.getByText("Воспроизводится", { exact: true })).toBeVisible();
  expect(await audio.evaluate((element) => (element as HTMLAudioElement).currentTime)).toBe(1.2);
  await expect(resume).toBeHidden();
});

test("a partial recording shows what it holds and the queue skips the missing surahs", async ({ page }) => {
  const held = [1, 3, 114];
  await page.route("**/api/v1/recitations?*", async (route) => {
    const response = await route.fetch();
    const body = await response.json() as { results: Recitation[] };
    for (const item of body.results) {
      if (item.id !== alternateRecitation.id) continue;
      item.coverage = { ...item.coverage, surah_count: held.length, track_count: held.length, complete: false, surah_numbers: held };
    }
    await route.fulfill({ response, json: body });
  });
  await page.goto("/ru/audio");
  await page.locator("#audio-reciter-select").selectOption(alternateReciter.id);
  await page.getByTestId("audio-whole-quran").click();
  const player = page.getByTestId("global-audio-player");
  const audio = player.locator("audio");
  await expect(audio).toHaveAttribute("src", alternateTracks[0].asset.url);
  await player.getByRole("button", { name: "Развернуть плеер", exact: true }).click();
  await expect(player.locator(".listening-queue-up-next")).toHaveText("Далее: Сура 3");

  await player.getByRole("button", { name: "Очередь", exact: true }).click();
  const queue = player.getByTestId("listening-queue");
  await expect(queue).toContainText("есть 3 из 114 сур");
  await expect(queue.locator(".listening-queue-gap")).toHaveText([
    "сура 2 не загружена",
    "суры 4–113 не загружены",
  ]);
  await expect(queue.locator(".listening-queue-row")).toHaveCount(3);

  await player.getByRole("button", { name: "Следующая сура", exact: true }).click();
  await expect(audio).toHaveAttribute("src", alternateTracks[2].asset.url);
  await finishSurah(audio);
  await expect(audio).toHaveAttribute("src", alternateTracks[113].asset.url);
  await expect(player.getByRole("button", { name: "Следующая сура", exact: true })).toBeDisabled();
});

test("the player switches between a reciter's recordings on the same surah", async ({ page }) => {
  const variants = [abdulBasetRecitations.murattalCurrent, abdulBasetRecitations.mujawwad];
  const urlFor = (variantId: string, surah: number) => `https://audio.example.test/basit/${variantId}/${surah}.mp3`;
  await page.route("**/api/v1/recitations/*/surahs/*", async (route) => {
    const [, variantId, surah] = /recitations\/([^/]+)\/surahs\/(\d+)/.exec(route.request().url())!;
    if (!variants.some((item) => item.id === variantId)) return route.fallback();
    const playback = surahPlayback(recitation.id, Number(surah))!;
    const asset = { ...playback.track.asset, url: urlFor(variantId, Number(surah)) };
    await route.fulfill({
      json: { ...playback, track: { ...playback.track, id: `${variantId}-${surah}`, recitation_id: variantId, asset } },
    });
  });
  await page.goto("/ru/audio");
  await page.locator("#audio-reciter-select").selectOption(abdulBaset.id);
  await expect(page.locator("#audio-recitation-select option")).toHaveCount(2);
  const pageVariant = await page.locator("#audio-recitation-select").inputValue();
  await page.getByTestId("audio-whole-quran").click();
  const player = page.getByTestId("global-audio-player");
  const audio = player.locator("audio");
  await expect(audio).toHaveAttribute("src", urlFor(pageVariant, 1));
  await player.getByRole("button", { name: "Развернуть плеер", exact: true }).click();
  await player.getByRole("button", { name: "Следующая сура", exact: true }).click();
  await expect(audio).toHaveAttribute("src", urlFor(pageVariant, 2));

  const other = variants.find((item) => item.id !== pageVariant)!;
  await player.locator(".listening-queue-bar").getByLabel("Вид чтения").selectOption(other.id);
  await expect(audio).toHaveAttribute("src", urlFor(other.id, 2));
  await expect(player.getByText("Воспроизводится", { exact: true })).toBeVisible();
  await expect(page.locator("#audio-recitation-select")).toHaveValue(other.id);
});

test("the phone's full player shows what plays next and opens the queue over itself", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/ru/audio");
  await page.getByRole("button", { name: "Слушать отсюда", exact: true }).first().click();
  const bar = page.getByTestId("mobile-audio-player");
  await expect(bar.locator("audio")).toHaveAttribute("src", tracks[0].asset.url);
  await bar.locator(".mobile-player-titles").click();
  const full = page.getByRole("dialog", { name: "Сейчас играет" });
  const upNext = full.getByRole("button", { name: /Далее/ });
  await expect(upNext).toContainText("Сура 2");
  await expect(full.getByLabel("После суры")).toHaveValue("next");
  // One recording: nothing to switch between.
  await expect(full.getByLabel("Вид чтения")).toHaveCount(0);

  await upNext.click();
  const queue = full.getByTestId("listening-queue");
  await expect(queue).toBeVisible();
  await expect(queue.getByRole("button", { name: "Закрыть очередь", exact: true })).toBeFocused();
  const sheet = await queue.boundingBox();
  expect(sheet!.y + sheet!.height).toBeLessThanOrEqual(844 + 1);
  expect(await page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390);

  // Escape closes the list first and leaves the full player open.
  await page.keyboard.press("Escape");
  await expect(queue).toBeHidden();
  await expect(full).toBeVisible();
  await upNext.click();
  await queue.locator(".listening-queue-row").nth(1).click();
  await expect(bar.locator("audio")).toHaveAttribute("src", tracks[1].asset.url);
  await expect(full.locator(".mobile-player-title")).toHaveText("Сура 2");
});
