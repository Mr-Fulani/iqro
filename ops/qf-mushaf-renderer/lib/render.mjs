import { execFile } from "node:child_process";
import { lstat, readFile, unlink, writeFile } from "node:fs/promises";
import { basename, join } from "node:path";
import { promisify } from "node:util";

import { ContractError, validatePageGeometry } from "./contract.mjs";

const execFileAsync = promisify(execFile);
const FONT_FAMILY = "IqroQfPinnedMushaf";

export async function renderPage({ request, bundle, runtime, outputDirectory }) {
  validatePageGeometry(request, bundle.geometry, bundle.pageGeometry);
  const widths = [...request.output.widths].sort((left, right) => left - right);
  await assertOwnedOutputsAbsent(outputDirectory, request.page.number, widths);
  const { chromium } = await import("playwright-core");
  const browser = await chromium.launch({
    executablePath: runtime.chromium.path,
    headless: true,
    chromiumSandbox: true,
    args: [
      "--disable-background-networking",
      "--disable-breakpad",
      "--disable-component-update",
      "--disable-default-apps",
      "--disable-domain-reliability",
      "--disable-extensions",
      "--disable-features=Translate,MediaRouter,OptimizationHints",
      "--disable-font-subpixel-positioning",
      "--disable-lcd-text",
      "--disable-sync",
      "--force-color-profile=srgb",
      "--hide-scrollbars",
      "--metrics-recording-only",
      "--no-first-run",
      "--no-pings",
    ],
  });
  const canonicalPng = join(outputDirectory, "canonical.png");
  try {
    const context = await browser.newContext({
      viewport: {
        width: bundle.geometry.canonical_width,
        height: bundle.geometry.canonical_height,
      },
      deviceScaleFactor: 1,
      locale: "ar",
      timezoneId: "UTC",
      colorScheme: "light",
      reducedMotion: "reduce",
      serviceWorkers: "block",
    });
    await context.route("**/*", (route) => route.abort("blockedbyclient"));
    const page = await context.newPage();
    await page.setContent(baseDocument(), { waitUntil: "domcontentloaded" });
    const fontData = (await readFile(bundle.fontPath)).toString("base64");
    const backgroundData = (await readFile(bundle.backgroundPath)).toString("base64");
    await page.evaluate(
      async ({
        fontFamily,
        fontDataValue,
        backgroundDataValue,
        backgroundMime,
        canvasWidth,
        canvasHeight,
        words,
        boxes,
      }) => {
        const face = new FontFace(fontFamily, `url(data:font/woff2;base64,${fontDataValue})`, {
          display: "block",
        });
        await face.load();
        document.fonts.add(face);
        await document.fonts.ready;
        const sheet = document.querySelector("#page");
        if (!(sheet instanceof HTMLElement)) throw new Error("Page root is unavailable.");
        sheet.style.width = `${canvasWidth}px`;
        sheet.style.height = `${canvasHeight}px`;
        sheet.style.backgroundImage = `url(data:${backgroundMime};base64,${backgroundDataValue})`;
        const byPosition = new Map(boxes.map((box) => [box.position_in_page, box]));
        for (const word of words) {
          const box = byPosition.get(word.position_in_page);
          if (!box) throw new Error("Word geometry disappeared before rendering.");
          const node = document.createElement("span");
          node.className = "word";
          node.dataset.sourceId = String(word.id);
          node.dataset.position = String(word.position_in_page);
          node.lang = "ar";
          node.dir = "rtl";
          node.translate = false;
          node.textContent = word.text;
          node.style.left = `${box.x}px`;
          node.style.top = `${box.y}px`;
          node.style.width = `${box.width}px`;
          node.style.height = `${box.height}px`;
          node.style.fontSize = `${box.font_size}px`;
          node.style.justifyContent = box.anchor === "start"
            ? "flex-start"
            : box.anchor === "end" ? "flex-end" : "center";
          sheet.appendChild(node);
        }
      },
      {
        fontFamily: FONT_FAMILY,
        fontDataValue: fontData,
        backgroundDataValue: backgroundData,
        backgroundMime: bundle.backgroundMime,
        canvasWidth: bundle.geometry.canonical_width,
        canvasHeight: bundle.geometry.canonical_height,
        words: request.page.words,
        boxes: bundle.pageGeometry.words,
      },
    );
    await assertOnlyPinnedFont(page, request.page.words.length);
    await page.locator("#page").screenshot({
      path: canonicalPng,
      type: "png",
      animations: "disabled",
      caret: "hide",
      omitBackground: false,
      scale: "css",
    });
    await context.close();
  } finally {
    await browser.close();
  }

  const assets = [];
  try {
    for (const width of widths) {
      const height = Math.round(width * bundle.geometry.canonical_height / bundle.geometry.canonical_width);
      const filename = `page-${String(request.page.number).padStart(3, "0")}-w${width}.webp`;
      const outputPath = join(outputDirectory, filename);
      await encodeLosslessWebp(runtime.cwebp.path, canonicalPng, outputPath, width, height);
      assets.push({
        path: basename(outputPath),
        width,
        height,
        content_type: "image/webp",
      });
    }
  } finally {
    await unlink(canonicalPng).catch(() => {});
  }
  const manifest = {
    schema_version: 1,
    page_number: request.page.number,
    source_checksum_sha256: request.source.source_checksum_sha256,
    lossless: true,
    assets,
  };
  await writeFile(
    join(outputDirectory, "manifest.json"),
    `${JSON.stringify(manifest, null, 2)}\n`,
    { encoding: "utf8", flag: "wx" },
  );
  return manifest;
}

async function assertOnlyPinnedFont(page, expectedWords) {
  const session = await page.context().newCDPSession(page);
  await session.send("DOM.enable");
  await session.send("CSS.enable");
  const documentNode = await session.send("DOM.getDocument", { depth: -1, pierce: true });
  const matches = await session.send("DOM.querySelectorAll", {
    nodeId: documentNode.root.nodeId,
    selector: "#page .word",
  });
  if (matches.nodeIds.length !== expectedWords) {
    throw new ContractError("Rendered DOM does not contain every source word.");
  }
  for (const nodeId of matches.nodeIds) {
    const result = await session.send("CSS.getPlatformFontsForNode", { nodeId });
    if (
      result.fonts.length !== 1 ||
      result.fonts[0].isCustomFont !== true ||
      result.fonts[0].glyphCount <= 0
    ) {
      throw new ContractError("Chromium used a fallback font for Quran glyphs.");
    }
  }
  await session.detach();
}

async function assertOwnedOutputsAbsent(outputDirectory, pageNumber, widths) {
  for (const width of widths) {
    const filename = `page-${String(pageNumber).padStart(3, "0")}-w${width}.webp`;
    if (await lstat(join(outputDirectory, filename)).catch(() => null)) {
      throw new ContractError("Output directory contains renderer-owned files.");
    }
  }
}

async function encodeLosslessWebp(executable, input, output, width, height) {
  try {
    await execFileAsync(
      executable,
      [
        "-quiet",
        "-lossless",
        "-exact",
        "-m",
        "6",
        "-metadata",
        "none",
        "-resize",
        String(width),
        String(height),
        input,
        "-o",
        output,
      ],
      {
        encoding: "utf8",
        maxBuffer: 64 * 1024,
        timeout: 180_000,
        windowsHide: true,
      },
    );
  } catch {
    throw new ContractError("Pinned cwebp failed to encode a lossless rendition.");
  }
}

function baseDocument() {
  return `<!doctype html>
<html lang="ar" dir="rtl" translate="no">
<head>
  <meta charset="utf-8">
  <meta name="google" content="notranslate">
  <style>
    * { box-sizing: border-box; }
    html, body { width: 100%; height: 100%; margin: 0; overflow: hidden; background: transparent; }
    #page { position: relative; overflow: hidden; background-repeat: no-repeat; background-size: 100% 100%; }
    .word {
      position: absolute;
      display: flex;
      align-items: center;
      margin: 0;
      padding: 0;
      overflow: visible;
      color: #17130d;
      direction: rtl;
      white-space: nowrap;
      font-family: "${FONT_FAMILY}";
      font-style: normal;
      font-weight: 400;
      font-synthesis: none;
      font-kerning: normal;
      font-variant-ligatures: normal;
      line-height: 1;
      text-rendering: geometricPrecision;
    }
  </style>
</head>
<body><main id="page" aria-label="Pinned Quran.Foundation Mushaf page"></main></body>
</html>`;
}
