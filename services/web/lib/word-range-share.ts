// The selected words as shared: from one word to several ayahs of a surah.
// Port of wordRangeContentShare (ayah_share.dart).

import type { ShareCardGlyph } from "./share-card.ts";
import { ayahTextParts, type QuranWordRange } from "./word-range.ts";

/** An ayah's words in the page fonts of a Mushaf, by `position_in_verse`, and its end sign. */
export type AyahShareScript = { words: ShareCardGlyph[]; end: ShareCardGlyph | null };

const arabicDigits = new Intl.NumberFormat("ar-EG", { useGrouping: false });

/** The end sign of an ayah in the plain script: «۝٢٨٦». */
export function ayahEndSign(ayah: number): string {
  return `۝${arabicDigits.format(ayah)}`;
}

/**
 * A part of an ayah has no meaning under it, as translations are of whole
 * ayahs, and says so in its title («из аята 2:286»); an ayah's end sign is
 * drawn only after its last word. Whole ayahs carry their meanings. `scripts`
 * holds the ayahs in the Mushaf's fonts; without one of them, or when its
 * words are not the words the reader counts, the plain script is drawn in
 * `plainFont`.
 */
export function wordRangeShare({
  range,
  surahName,
  ayahs,
  partOf,
  plainFont,
  scripts = new Map(),
  translations = new Map(),
}: {
  range: QuranWordRange;
  surahName: string;
  /** The ayahs of the surah that the reader has. */
  ayahs: readonly { number: number; text_uthmani: string }[];
  partOf: (reference: string, several: boolean) => string;
  plainFont: string;
  scripts?: ReadonlyMap<number, AyahShareScript>;
  translations?: ReadonlyMap<number, string>;
}): { title: string; arabic: string; units: ShareCardGlyph[][]; translation: string } {
  const surah = range.start.surah;
  const selected = ayahs
    .filter((ayah) => ayah.number >= range.start.ayah && ayah.number <= range.end.ayah)
    .map((ayah) => ({
      number: ayah.number,
      words: ayahTextParts(surah, ayah.number, ayah.text_uthmani).flatMap((part) => part.words ?? []),
    }));
  const inScript = selected.every((ayah) => scripts.get(ayah.number)?.words.length === ayah.words.length);
  const plain: string[] = [];
  const units: ShareCardGlyph[][] = [];
  let whole = true;
  for (const { number, words } of selected) {
    const from = number === range.start.ayah ? range.start.position : 1;
    const to = number === range.end.ayah ? Math.min(range.end.position, words.length) : words.length;
    if (from > 1 || to < words.length) whole = false;
    const script = inScript ? scripts.get(number) : undefined;
    for (let position = from; position <= to; position += 1) {
      plain.push(words[position - 1]);
      const unit = [script?.words[position - 1] ?? { text: words[position - 1], fontFamily: plainFont }];
      if (position === words.length) {
        const end = script ? script.end : { text: ayahEndSign(number), fontFamily: plainFont };
        if (end) unit.push(end);
      }
      units.push(unit);
    }
  }
  const several = range.start.ayah !== range.end.ayah;
  const reference = several ? `${surah}:${range.start.ayah}–${range.end.ayah}` : `${surah}:${range.start.ayah}`;
  const meanings = selected.map((ayah) => translations.get(ayah.number)?.trim() ?? "");
  return {
    title: `${surahName} · ${whole ? reference : partOf(reference, several)}`,
    arabic: plain.join(" "),
    units,
    translation: whole && meanings.every(Boolean) ? meanings.join(" ") : "",
  };
}
