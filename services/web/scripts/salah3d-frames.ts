// The pose illustrations of the prayer course are stills of the schematic 3D scene
// (docs/salah/salah-3d.md): shown where the scene cannot run and as its first frame. For
// every media entry of the course snapshot with `scene`, this renders that pose with the
// scene's home camera (no camera moves) from clients/iqro_mobile/assets/salah3d (the same
// code as lib/salah3d, see salah3d-app-assets.ts) and writes a 720×720 WebP of at most
// 60 KB over the entry's file. Run from services/web after `npm run salah3d:app-assets`:
//   node scripts/salah3d-frames.ts
import { readFile, writeFile } from "node:fs/promises";

import { chromium } from "@playwright/test";

const SNAPSHOT = new URL("../../backend/src/quran_backend/modules/salah/data/hanbali-umdah-v1.json", import.meta.url);
const PAGE = new URL("../../../clients/iqro_mobile/assets/salah3d/index.html", import.meta.url);
const SIZE = 720;
const MAX_BYTES = 60 * 1024;

type Scene = { pose: string; view: string };
type Asset = { key: string; file: string; scene?: Scene };

const snapshot = JSON.parse(await readFile(SNAPSHOT, "utf8")) as { media: Asset[] };
const browser = await chromium.launch();
try {
  // Drawn at twice the size and scaled down, so the pencil lines stay smooth.
  const page = await browser.newPage({ viewport: { width: SIZE, height: SIZE }, deviceScaleFactor: 2 });
  await page.addInitScript(() => Object.assign(window, { SalahBridge: { postMessage() {} } }));
  await page.goto(PAGE.href);
  for (const asset of snapshot.media) {
    if (!asset.scene) continue;
    const dataUrl = await page.evaluate(
      async ({ scene, size, maxBytes }) => {
        type Mount = (canvas: HTMLCanvasElement, options: object) => { dispose(): void };
        const { mount } = (window as unknown as { SalahScene: { mount: Mount } }).SalahScene;
        const canvas = document.createElement("canvas");
        canvas.style.cssText = `position:fixed;inset:0;width:${size}px;height:${size}px`;
        document.body.append(canvas);
        const instance = mount(canvas, {
          view: scene.view,
          step: scene.view === "full" ? scene.pose : null,
          frozenTime: 0,
          autoCamera: false,
          preserve: true,
        });
        await new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done)));
        const still = document.createElement("canvas");
        still.width = still.height = size;
        const context = still.getContext("2d")!;
        context.imageSmoothingQuality = "high";
        context.drawImage(canvas, 0, 0, size, size);
        instance.dispose();
        canvas.remove();
        for (let quality = 0.9; quality > 0.25; quality -= 0.05) {
          const url = still.toDataURL("image/webp", quality);
          if (atob(url.slice(url.indexOf(",") + 1)).length <= maxBytes) return url;
        }
        throw new Error(`${scene.pose}: no WebP under ${maxBytes} bytes`);
      },
      { scene: asset.scene, size: SIZE, maxBytes: MAX_BYTES },
    );
    const bytes = Buffer.from(dataUrl.slice(dataUrl.indexOf(",") + 1), "base64");
    await writeFile(new URL(asset.file, SNAPSHOT), bytes);
    console.log(`${asset.file}: ${asset.scene.pose}/${asset.scene.view}, ${bytes.length} bytes`);
  }
} finally {
  await browser.close();
}
