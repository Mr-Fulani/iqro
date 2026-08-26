import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const chunksDirectory = fileURLToPath(new URL("../.next/static/chunks/", import.meta.url));
const cssFiles = (await readdir(chunksDirectory))
  .filter((name) => name.endsWith(".css"))
  .sort();

if (cssFiles.length === 0) {
  throw new Error("Production build integrity check found no compiled CSS chunks.");
}

const cssChunks = await Promise.all(
  cssFiles.map((name) => readFile(join(chunksDirectory, name), "utf8")),
);
const compiledCss = cssChunks.join("\n");
const compiledBytes = Buffer.byteLength(compiledCss);
const requiredRules = [
  ["responsive action groups", /\.responsive-actions/],
  ["Mushaf page navigation", /\.mushaf-page-navigation/],
  ["320px mobile breakpoint", /@media\s*\(max-width:\s*360px\)/],
  ["compact audio-player breakpoint", /@media\s*\(max-width:\s*520px\)/],
];

const missingRules = requiredRules
  .filter(([, pattern]) => !pattern.test(compiledCss))
  .map(([label]) => label);

if (compiledBytes < 20_000 || missingRules.length > 0) {
  throw new Error(
    `Production CSS looks incomplete (${compiledBytes} bytes). Missing: ${missingRules.join(", ") || "none"}.`,
  );
}

console.log(`Production build integrity verified: ${cssFiles.length} CSS chunk(s), ${compiledBytes} bytes.`);
