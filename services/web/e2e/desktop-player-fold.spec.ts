import { expect, test } from "@playwright/test";
import type { Locator, Page } from "@playwright/test";

// On desktop the dock folds into a round button in the corner, as the phone
// bar does (docs/web-desktop-player-fold-2026-11-03.md). The <audio> element
// stays mounted, so the sound and its place go on, and the choice holds
// across pages and visits. The mocked audio files are empty, so play() and
// pause() only report their events and the test sets the clock itself.
async function stubMedia(page: Page) {
  await page.addInitScript(() => {
    localStorage.setItem("iqro_analytics_consent_v1", "denied");
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
        (window as unknown as { __pauses: number }).__pauses += 1;
        this.dispatchEvent(new Event("pause"));
      },
    });
    Object.defineProperty(window, "__pauses", { configurable: true, writable: true, value: 0 });
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

/** Starts the whole Quran and marks the <audio> element, so a remount would show. */
async function startPlayback(page: Page, path = "/ru/audio") {
  await page.goto(path);
  await page.getByTestId("audio-whole-quran").click();
  const player = page.getByTestId("global-audio-player");
  const audio = player.locator("audio");
  await expect(audio).toHaveAttribute("src", /audio\.example\.test/);
  await audio.evaluate((element) => {
    const media = element as HTMLAudioElement & { __mark?: string };
    media.__mark = "kept";
    media.currentTime = 1.2;
    media.dispatchEvent(new Event("timeupdate"));
  });
  return { player, audio };
}

async function soundState(audio: Locator) {
  return audio.evaluate((element) => ({
    mark: (element as HTMLAudioElement & { __mark?: string }).__mark,
    time: (element as HTMLAudioElement).currentTime,
    pauses: (window as unknown as { __pauses: number }).__pauses,
  }));
}

test.beforeEach(async ({ page }) => {
  await stubMedia(page);
});

test("the dock folds into a round button and back without stopping the sound", async ({ page }) => {
  const { player, audio } = await startPlayback(page);
  const before = await soundState(audio);
  const fab = player.getByRole("button", { name: "Показать плеер", exact: true });
  await expect(fab).toHaveCount(0);

  await player.getByRole("button", { name: "Свернуть плеер в кнопку", exact: true }).click();
  await expect(player).toHaveClass(/is-folded/);
  await expect(fab).toBeVisible();
  await expect(fab).toBeFocused();
  // Playing: the button shows pause, as the phone's.
  await expect(fab.locator("path")).toHaveAttribute("d", /^M6 19h4V5H6v14z/);
  // The button grows into place; measure once it has.
  await player.evaluate((element) => Promise.all(element.getAnimations().map((animation) => animation.finished)));
  const box = (await player.boundingBox())!;
  const viewport = page.viewportSize()!;
  expect(Math.round(box.width)).toBe(60);
  expect(Math.round(box.height)).toBe(60);
  expect(Math.round(viewport.width - box.x - box.width)).toBe(24);
  expect(Math.round(viewport.height - box.y - box.height)).toBe(24);
  // The dock's controls are out of reach while folded, but still mounted.
  await expect(player.locator(".global-audio-player-body")).toHaveAttribute("inert", "");
  await expect(player.getByRole("button", { name: "Развернуть плеер", exact: true })).toBeHidden();
  await expect(page.locator(".global-audio-player-spacer")).toHaveCSS("height", "92px");
  expect(await soundState(audio)).toEqual(before);

  // The keyboard brings the dock back, with focus on the button that folds it.
  await fab.press("Enter");
  await expect(player).not.toHaveClass(/is-folded/);
  await expect(fab).toHaveCount(0);
  const fold = player.getByRole("button", { name: "Свернуть плеер в кнопку", exact: true });
  await expect(fold).toBeFocused();
  expect((await player.boundingBox())!.height).toBeLessThan(130);
  expect(await soundState(audio)).toEqual(before);
  await expect.poll(() => page.evaluate(() => localStorage.getItem("iqro_desktop_player_folded_v1"))).toBeNull();
});

test("a folded dock stays folded on other pages and after a reload", async ({ page }) => {
  const { player, audio } = await startPlayback(page);
  const before = await soundState(audio);
  await player.getByRole("button", { name: "Свернуть плеер в кнопку", exact: true }).click();
  const fab = player.getByRole("button", { name: "Показать плеер", exact: true });
  await expect(fab).toBeVisible();

  await page.locator(".app-menu a[href='/ru/planner']").click();
  await expect(page).toHaveURL(/\/ru\/planner$/);
  await expect(fab).toBeVisible();
  expect(await soundState(audio)).toEqual(before);

  await page.goto("/ru/audio");
  await expect(page.getByTestId("global-audio-player")).toHaveClass(/is-folded/);
  await expect(fab).toBeVisible();
  // Nothing plays after the reload: the button offers play.
  await expect(fab.locator("path")).toHaveAttribute("d", "M8 5v14l11-7z");
  await fab.click();
  await expect(player).not.toHaveClass(/is-folded/);
  await page.reload();
  await expect(player.getByRole("button", { name: "Свернуть плеер в кнопку", exact: true })).toBeVisible();
  await expect(fab).toHaveCount(0);
});

test("the expanded dock folds too and comes back expanded", async ({ page }) => {
  const { player } = await startPlayback(page);
  await player.getByRole("button", { name: "Развернуть плеер", exact: true }).click();
  await expect(player).toHaveClass(/has-player-background/);
  const fold = player.getByRole("button", { name: "Свернуть плеер в кнопку", exact: true });
  // The expanded head has room for the label.
  await expect(fold.getByText("Свернуть плеер в кнопку", { exact: true })).toBeVisible();
  await fold.click();
  // The picture behind the expanded dock is not kept while folded.
  await expect(player).not.toHaveClass(/has-player-background/);
  await expect(player.locator(".global-audio-player-backdrop")).toHaveCount(0);
  await player.getByRole("button", { name: "Показать плеер", exact: true }).click();
  await expect(player).toHaveClass(/is-expanded/);
  await expect(player).toHaveClass(/has-player-background/);
  await expect(fold).toBeFocused();
});

test("in Arabic the button sits in the left corner and reduced motion skips the animation", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/ar/audio");
  const player = page.getByTestId("global-audio-player");
  await player.getByRole("button", { name: "طي المشغل إلى زر", exact: true }).click();
  const fab = player.getByRole("button", { name: "إظهار المشغل", exact: true });
  await expect(fab).toBeFocused();
  await expect(player).toHaveCSS("animation-name", "none");
  const box = (await player.boundingBox())!;
  expect(Math.round(box.x)).toBe(24);
  // The play arrow points along the reading direction.
  await expect(fab.locator("g")).toHaveCSS("transform", "matrix(-1, 0, 0, 1, 0, 0)");
  await fab.press("Space");
  await expect(player).not.toHaveClass(/is-folded/);
  await expect(player).toHaveCSS("animation-name", "none");
});

test("the phone bar has no desktop fold button", async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 });
  await page.goto("/ru/audio");
  await page.getByTestId("audio-whole-quran").click();
  await expect(page.getByTestId("mobile-audio-player")).toBeVisible();
  await expect(page.getByRole("button", { name: "Свернуть плеер в кнопку", exact: true })).toHaveCount(0);
});
