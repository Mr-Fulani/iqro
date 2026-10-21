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
  await expect.poll(async () => (await messages(page)).map((message) => message.type)).toEqual(["LOADED"]);

  await page.evaluate(() => (window as unknown as { salah: { show: (step: string, speed: number) => void } }).salah.show("ruku", 1));
  await expect.poll(async () => (await messages(page)).find((message) => message.type === "READY")).toMatchObject({ version: "0.1.0" });
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
  await expect.poll(() => messages(page)).toEqual([{ type: "ERROR", code: "NO_WEBGL" }]);
});
