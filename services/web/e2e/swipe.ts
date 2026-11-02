import type { Locator, Page } from "@playwright/test";

/**
 * A finger-like drag from the middle of the target: a positive deltaY goes
 * down, a positive deltaX to the right. The phone player rolls its bar up on a
 * swipe in any direction (lib/mini-player.ts).
 */
export async function swipe(page: Page, target: Locator, deltaY: number, deltaX = 0) {
  // As a tap would: wait until the target stands still and takes the pointer.
  await target.hover();
  const bounds = await target.boundingBox();
  if (!bounds) throw new Error("swipe target is not on screen");
  const x = bounds.x + bounds.width / 2;
  const y = bounds.y + bounds.height / 2;
  await page.mouse.move(x, y);
  await page.mouse.down();
  await page.mouse.move(x + deltaX, y + deltaY, { steps: 4 });
  await page.mouse.up();
}
