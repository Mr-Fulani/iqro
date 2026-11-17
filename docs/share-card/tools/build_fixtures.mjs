// Writes docs/share-card/fixtures.json: word widths and the cards the site's
// composer makes of them. The app's composer must give the same cards.
//   node docs/share-card/tools/build_fixtures.mjs   (from the repository root)
import fs from "node:fs";
import { composeShareCard } from "../../../services/web/lib/share-card-compose.ts";

const layout = JSON.parse(fs.readFileSync(new URL("../layout.json", import.meta.url), "utf8"));
let seed = 7;
const random = () => {
  seed = (seed * 1103515245 + 12345) % 2147483648;
  return seed / 2147483648;
};
const words = (count, low, high) =>
  Array.from({ length: count }, () => Math.round((low + random() * (high - low)) * 1000) / 1000);

const cases = [
  ["short ayah with meaning", "story", 4, 5],
  ["short ayah, post", "post", 4, 5],
  ["no meaning", "story", 9, 0],
  ["medium ayah", "story", 29, 40],
  ["ayat al-kursi", "story", 51, 95],
  ["ayat al-kursi, post", "post", 51, 95],
  ["longest ayah", "story", 129, 260],
  ["longest ayah, post", "post", 129, 260],
  ["long dua", "story", 75, 150],
  ["too long", "post", 420, 900],
  ["one wide word", "story", 1, 0],
].map(([name, format, arabicCount, translationCount]) => {
  const arabic = { widths: name === "one wide word" ? [9.5] : words(arabicCount, 0.9, 3.2), space: 0.25 };
  const translation = { widths: words(translationCount, 0.4, 4.6), space: 0.25 };
  return { name, format, arabic, translation, pages: composeShareCard(layout, format, arabic, translation) };
});
fs.writeFileSync(new URL("../fixtures.json", import.meta.url), `${JSON.stringify({ cases }, null, 1)}\n`);
for (const { name, format, pages } of cases) {
  console.log(name.padEnd(26), format, pages
    ? pages.map((page) => `A${page.arabicSize}x${page.arabicLines.length} T${page.translationSize}x${page.translationLines.length}`).join(" | ")
    : "null");
}
