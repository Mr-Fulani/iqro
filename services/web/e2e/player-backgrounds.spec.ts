import { expect, test } from "@playwright/test";

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
  // With reduced motion the sound bars rest without any animation.
  const equalizer = player.getByTestId("player-equalizer");
  await expect(equalizer).toBeVisible();
  await expect(equalizer).toHaveAttribute("aria-hidden", "true");
  expect(await equalizer.evaluate((element) => element.getAnimations({ subtree: true }).length)).toBe(0);
  await expect(equalizer.locator("span").first()).toHaveCSS("transform", "matrix(1, 0, 0, 0.62, 0, 0)");
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

test("admin backgrounds fall back to English titles in Turkish", async ({ page }) => {
  await page.goto("/tr/audio");
  const player = page.getByTestId("global-audio-player");
  await player.getByRole("button", { name: "Oynatıcıyı genişlet", exact: true }).click();
  await expect(player.getByTestId("player-equalizer")).toBeVisible();
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
