import { expect, test, type Page } from "@playwright/test";

// The app's offline page (clients/iqro_mobile/assets/salah3d) in Chromium, the engine of
// Android's WebView, with a stand-in for the app's SalahBridge channel.
const appPage = new URL("../../../clients/iqro_mobile/assets/salah3d/index.html", import.meta.url).href;

async function openWithBridge(page: Page) {
  await page.addInitScript(() => {
    const messages: unknown[] = [];
    Object.assign(window, {
      bridgeMessages: messages,
      SalahBridge: { postMessage: (text: string) => messages.push(JSON.parse(text)) },
    });
  });
  await page.goto(appPage);
}

const messages = (page: Page) => page.evaluate(() => (window as unknown as { bridgeMessages: { type: string }[] }).bridgeMessages);

test("the app page boots the scene through the bridge and follows commands", async ({ page }) => {
  await page.setViewportSize({ width: 360, height: 360 });
  await openWithBridge(page);
  // three.min.js and the scene are parsed from disk; give a busy machine some room.
  await expect.poll(async () => (await messages(page)).map((message) => message.type), { timeout: 20_000 }).toEqual(["LOADED"]);

  await page.evaluate(() => (window as unknown as { salah: { show: (step: string, speed: number) => void } }).salah.show("ruku", 1));
  await expect
    .poll(async () => (await messages(page)).find((message) => message.type === "READY"), { timeout: 20_000 })
    .toMatchObject({ version: "0.1.0" });
  await expect(page.locator("canvas#salah")).toHaveAttribute("aria-hidden", "true");

  // Commands from the app never throw, before or after dispose.
  await page.evaluate(() => {
    const salah = (window as unknown as { salah: Record<string, (value?: unknown) => void> }).salah;
    salah.pause();
    salah.setSpeed(0.5);
    salah.resetCamera();
    salah.play();
    salah.show("tashahhud");
    salah.dispose();
    salah.pause();
  });
  expect((await messages(page)).filter((message) => message.type === "ERROR")).toEqual([]);
});

test("without WebGL the app page says so and mounts nothing", async ({ page }) => {
  await page.addInitScript(() => {
    HTMLCanvasElement.prototype.getContext = () => null;
  });
  await openWithBridge(page);
  await expect.poll(() => messages(page), { timeout: 20_000 }).toEqual([{ type: "ERROR", code: "NO_WEBGL" }]);
});

test("the app page plays the step once, says so and replays on request", async ({ page }) => {
  await page.setViewportSize({ width: 360, height: 360 });
  await openWithBridge(page);
  await expect.poll(async () => (await messages(page)).map((message) => message.type), { timeout: 20_000 }).toEqual(["LOADED"]);
  type Salah = Record<"show" | "play" | "replay", (step?: string, speed?: number) => void>;
  const ended = async () => (await messages(page)).filter((message) => message.type === "ENDED").length;

  // The takbir takes about 2.5 s.
  await page.evaluate(() => (window as unknown as { salah: Salah }).salah.show("takbir", 1));
  await expect.poll(ended, { timeout: 20_000 }).toBe(1);
  const canvas = page.locator("canvas#salah");
  const moving = async () => {
    const before = await canvas.screenshot();
    await page.waitForTimeout(400);
    return !before.equals(await canvas.screenshot());
  };
  // The camera settles on the last frame, then nothing moves.
  await expect.poll(moving, { timeout: 20_000 }).toBe(false);
  // Play (as after the app comes back to the foreground) leaves an ended step on its last frame.
  await page.evaluate(() => (window as unknown as { salah: Salah }).salah.play());
  expect(await moving()).toBe(false);
  expect(await ended()).toBe(1);

  await page.evaluate(() => (window as unknown as { salah: Salah }).salah.replay());
  expect(await moving()).toBe(true);
  await expect.poll(ended, { timeout: 20_000 }).toBe(2);
  expect((await messages(page)).filter((message) => message.type === "ERROR")).toEqual([]);
});
