import { expect, test } from "@playwright/test";
import type { Locator } from "@playwright/test";

test("expanded player remembers a background and keeps the scrim under reduced motion", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/audio");

  const player = page.getByTestId("global-audio-player");
  await player.getByRole("button", { name: "Развернуть плеер", exact: true }).click();

  // Desert night is the default, as in the app.
  await expect(player).toHaveAttribute("data-player-background", "bundled:desert-night");
  await expect(player).toHaveClass(/has-player-background/);
  const backdrop = player.locator(".global-audio-player-backdrop img");
  await expect(backdrop).toHaveAttribute("loading", "lazy");
  await expect(backdrop).toHaveAttribute("sizes", "min(1160px, 100vw)");
  await expect(backdrop).toHaveCSS("transition-duration", "0s");
  // Nothing plays, so the sound bars are faded out; reduced motion leaves them still.
  const equalizer = player.getByTestId("player-equalizer");
  await expect(equalizer).toHaveAttribute("aria-hidden", "true");
  await expect(equalizer).toHaveCSS("opacity", "0");
  await expect(equalizer).toHaveCSS("transition-duration", "0s");
  expect(await equalizer.evaluate((element) => element.getAnimations({ subtree: true }).length)).toBe(0);
  await expect(equalizer.locator("span").first()).toHaveCSS("transform", "matrix(1, 0, 0, 0.62, 0, 0)");
  // The preference is followed live, not only when the player opens.
  const animations = () => equalizer.evaluate((element) => element.getAnimations({ subtree: true }).length);
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await expect.poll(animations).toBe(9);
  await page.emulateMedia({ reducedMotion: "reduce" });
  await expect.poll(animations).toBe(0);
  await expect(player.locator(".global-audio-player-scrim")).toHaveCSS(
    "background-image",
    /rgba\(6, 29, 24, 0\.68\).*rgba\(6, 29, 24, 0\.77\).*rgba\(6, 29, 24, 0\.86\)/,
  );

  await player.getByRole("button", { name: "Фон плеера" }).click();
  const choices = player.getByRole("radio");
  await expect(choices).toHaveCount(7);
  await expect(player.getByRole("radio", { name: "Горы" })).toBeAttached();
  await expect(player.getByRole("radio", { name: "Ночная пустыня" })).toBeChecked();
  await expect(player.locator(".player-background-thumb img").first()).toHaveAttribute(
    "src",
    "/player-backgrounds/desert-night-192.webp",
  );
  await player.getByText("Море на рассвете", { exact: true }).click();
  await expect(player.getByRole("radio", { name: "Море на рассвете" })).toBeChecked();
  await expect(player).toHaveAttribute("data-player-background", "bundled:sea-dawn");
  await expect(backdrop).toHaveAttribute("src", "/player-backgrounds/sea-dawn.webp");

  await page.reload();
  await page.getByTestId("global-audio-player")
    .getByRole("button", { name: "Развернуть плеер", exact: true })
    .click();
  await expect(player).toHaveAttribute("data-player-background", "bundled:sea-dawn");

  // With reduced motion a video background shows only its poster.
  await player.getByRole("button", { name: "Фон плеера" }).click();
  await player.getByText("Чтец", { exact: true }).click();
  await expect(player).toHaveAttribute("data-player-background", "bundled:reciter-video");
  await expect(backdrop).toHaveAttribute("src", "/player-backgrounds/reciter-hood.webp");
  await expect(player.locator(".global-audio-player-backdrop video")).toHaveCount(0);

  await player.getByText("Классический", { exact: true }).click();
  await expect(player).toHaveAttribute("data-player-background", "bundled:classic");
  await expect(player).not.toHaveClass(/has-player-background/);
  await expect(player.locator(".global-audio-player-backdrop")).toHaveCount(0);
});

test("a video background loops silently over its poster only in the expanded player", async ({ page }) => {
  const mediaRequests: string[] = [];
  page.on("request", (request) => {
    if (request.resourceType() === "media") mediaRequests.push(new URL(request.url()).pathname);
  });
  await page.goto("/audio");
  const player = page.getByTestId("global-audio-player");
  await player.getByRole("button", { name: "Развернуть плеер", exact: true }).click();
  await player.getByRole("button", { name: "Фон плеера" }).click();
  await player.getByText("Горы", { exact: true }).click();

  const backdrop = player.locator(".global-audio-player-backdrop");
  await expect(backdrop.locator("img")).toHaveAttribute("src", "/player-backgrounds/geometric.webp");
  const video = backdrop.locator("video");
  await expect(video).toHaveAttribute("src", "/media/audio/player-backgrounds/mountains-loop.webm");
  await expect(video).toHaveAttribute("preload", "none");
  await expect(video).toHaveAttribute("loop");
  await expect(video).toHaveAttribute("playsinline");
  // It covers the poster once it actually plays and stays under the scrim.
  await expect(video).toHaveAttribute("data-loaded", "true");
  await expect(video).toHaveCSS("opacity", "1");
  expect(await video.evaluate((element: HTMLVideoElement) => [element.muted, element.paused])).toEqual([true, false]);
  await expect(backdrop.locator("video + .global-audio-player-scrim")).toHaveCount(1);

  // A bundled video, as in the app.
  await player.getByText("Чтец", { exact: true }).click();
  await expect(video).toHaveAttribute("src", "/player-backgrounds/reciter-hood.mp4");
  await expect(backdrop.locator("img")).toHaveAttribute("src", "/player-backgrounds/reciter-hood.webp");

  await player.getByRole("button", { name: "Свернуть плеер", exact: true }).click();
  await expect(page.locator("video")).toHaveCount(0);

  // The choice is remembered, but nothing is fetched until the player is expanded.
  mediaRequests.length = 0;
  await page.reload();
  const expand = page.getByTestId("global-audio-player").getByRole("button", { name: "Развернуть плеер", exact: true });
  await expect(expand).toBeVisible();
  await expect(page.locator("video")).toHaveCount(0);
  expect(mediaRequests).toEqual([]);
  await expand.click();
  await expect(video).toHaveAttribute("src", "/player-backgrounds/reciter-hood.mp4");
  await expect.poll(() => mediaRequests).toContain("/player-backgrounds/reciter-hood.mp4");
});

test("the video code loads only for a video background, and a failed load leaves the poster until a retry", async ({ page }) => {
  const pageErrors: string[] = [];
  page.on("pageerror", (error) => pageErrors.push(error.message));
  await page.goto("/audio");
  const player = page.getByTestId("global-audio-player");
  const expand = player.getByRole("button", { name: "Развернуть плеер", exact: true });
  await expect(expand).toBeVisible();
  const chunkRequests: string[] = [];
  await page.route("**/_next/static/chunks/**", (route) => {
    chunkRequests.push(route.request().url());
    return route.abort();
  });

  // The default picture needs no extra code.
  await expand.click();
  await expect(player).toHaveAttribute("data-player-background", "bundled:desert-night");
  await expect(player.locator(".global-audio-player-backdrop img")).toHaveAttribute("data-loaded", "true");
  expect(chunkRequests).toEqual([]);

  // The chunk loader retries once; wait until the failure is final and handled.
  const chunkFailed = page.waitForEvent("console", {
    predicate: async (message) => {
      if (message.type() !== "error") return false;
      const names = await Promise.all(
        message.args().map((arg) => arg.evaluate((value) => value instanceof Error && value.name)),
      );
      return names.includes("ChunkLoadError");
    },
  });
  await player.getByRole("button", { name: "Фон плеера" }).click();
  await player.getByText("Чтец", { exact: true }).click();
  await chunkFailed;
  expect(chunkRequests.length).toBeGreaterThan(0);
  const poster = player.locator(".global-audio-player-backdrop img");
  await expect(poster).toHaveAttribute("src", "/player-backgrounds/reciter-hood.webp");
  await expect(poster).toHaveAttribute("data-loaded", "true");
  await expect(player.locator("video")).toHaveCount(0);

  // Once the network is back, the next video background loads the chunk again.
  await page.unroute("**/_next/static/chunks/**");
  await player.getByText("Горы", { exact: true }).click();
  const video = player.locator(".global-audio-player-backdrop video");
  await expect(video).toHaveAttribute("src", "/media/audio/player-backgrounds/mountains-loop.webm");
  await expect(video).toHaveAttribute("data-loaded", "true");

  await player.getByRole("button", { name: "Свернуть плеер", exact: true }).click();
  await expect(expand).toBeVisible();
  expect(pageErrors).toEqual([]);
});

test("data saver keeps the poster and loads no video code", async ({ page }) => {
  await page.addInitScript(() => {
    Object.defineProperty(Navigator.prototype, "connection", {
      configurable: true,
      get: () => ({ saveData: true }),
    });
  });
  await page.goto("/audio");
  const player = page.getByTestId("global-audio-player");
  const expand = player.getByRole("button", { name: "Развернуть плеер", exact: true });
  await expect(expand).toBeVisible();
  const lateRequests: string[] = [];
  page.on("request", (request) => {
    const type = request.resourceType();
    if (type === "script" || type === "media") lateRequests.push(request.url());
  });

  await expand.click();
  await player.getByRole("button", { name: "Фон плеера" }).click();
  await player.getByText("Горы", { exact: true }).click();
  const poster = player.locator(".global-audio-player-backdrop img");
  await expect(poster).toHaveAttribute("src", "/player-backgrounds/geometric.webp");
  await expect(poster).toHaveAttribute("data-loaded", "true");
  await expect(player.locator("video")).toHaveCount(0);
  expect(lateRequests).toEqual([]);
});

test("admin backgrounds fall back to English titles in Turkish", async ({ page }) => {
  await page.goto("/tr/audio");
  const player = page.getByTestId("global-audio-player");
  await player.getByRole("button", { name: "Oynatıcıyı genişlet", exact: true }).click();
  await expect(player.getByTestId("player-equalizer")).toBeAttached();
  await player.getByRole("button", { name: "Oynatıcı arka planı" }).click();
  await player.getByText("Mountains", { exact: true }).click();
  await expect(player).toHaveAttribute(
    "data-player-background",
    "remote:019a0000-0000-7000-8000-000000000901",
  );
  await expect(player.locator(".global-audio-player-backdrop img")).toHaveAttribute(
    "src",
    "/player-backgrounds/geometric.webp",
  );
  // This admin background has the sound bars switched off.
  await expect(player.getByTestId("player-equalizer")).toHaveCount(0);
});

test("sound bars never push the player buttons onto another line", async ({ page }) => {
  await page.goto("/audio");
  const player = page.getByTestId("global-audio-player");
  await player.getByRole("button", { name: "Развернуть плеер", exact: true }).click();
  const equalizer = player.getByTestId("player-equalizer");
  const top = async (locator: Locator) => (await locator.boundingBox())!.y;
  const controls = [
    player.getByLabel("Быстрая смена чтеца"),
    player.getByRole("button", { name: "Фон плеера" }),
    player.getByRole("button", { name: "Свернуть плеер", exact: true }),
  ];

  // Portrait tablets wider than the phone player (which takes over up to 768 px):
  // the bars take their own line above the controls.
  for (const width of [810, 820]) {
    await page.setViewportSize({ width, height: 1024 });
    const row = await top(controls[0]);
    for (const control of controls) expect(Math.abs((await top(control)) - row)).toBeLessThan(8);
    const bars = (await equalizer.boundingBox())!;
    expect(bars.y + bars.height).toBeLessThanOrEqual(row);
  }

  // Wider screens: the bars sit between the reciter and the buttons.
  await page.setViewportSize({ width: 1280, height: 900 });
  const row = await top(controls[0]);
  for (const control of controls) expect(Math.abs((await top(control)) - row)).toBeLessThan(8);
  expect(Math.abs((await top(equalizer)) - row)).toBeLessThan(8);
  expect((await equalizer.boundingBox())!.width).toBe(104);
});
