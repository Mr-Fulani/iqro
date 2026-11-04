/**
 * Words selected in a reader, to be played from the start of the first to the
 * end of the last. Port of word_range.dart.
 */
import { splitDuaArabic } from "./dua-arabic.ts";

/** A word of the Quran: its ayah and its `position_in_verse`. */
export type QuranWord = { surah: number; ayah: number; position: number };

/** Words from `start` to `end`, both included, inside one surah. */
export type QuranWordRange = { start: QuranWord; end: QuranWord };

export function compareWords(a: QuranWord, b: QuranWord): number {
  return a.surah - b.surah || a.ayah - b.ayah || a.position - b.position;
}

export function sameWord(a: QuranWord | null | undefined, b: QuranWord | null | undefined): boolean {
  return Boolean(a && b && compareWords(a, b) === 0);
}

/** The range between two words in either order; null across surahs. */
export function wordRangeBetween(a: QuranWord, b: QuranWord): QuranWordRange | null {
  if (a.surah !== b.surah) return null;
  return compareWords(a, b) <= 0 ? { start: a, end: b } : { start: b, end: a };
}

export function sameWordRange(a: QuranWordRange | null | undefined, b: QuranWordRange | null | undefined): boolean {
  if (!a || !b) return a === b;
  return sameWord(a.start, b.start) && sameWord(a.end, b.end);
}

export function wordRangeContains(range: QuranWordRange | null | undefined, word: QuranWord): boolean {
  return Boolean(range && compareWords(range.start, word) <= 0 && compareWords(word, range.end) <= 0);
}

/** The end marker of `ayah` stands between two selected words. */
export function wordRangeSpansAyahEnd(range: QuranWordRange | null | undefined, surah: number, ayah: number): boolean {
  return Boolean(range && surah === range.start.surah && ayah >= range.start.ayah && ayah < range.end.ayah);
}

/** `surah:ayah:position`, the `data-word-key` of a word element. */
export function wordKey(word: QuranWord): string {
  return `${word.surah}:${word.ayah}:${word.position}`;
}

export function parseWordKey(value: string | undefined | null): QuranWord | null {
  const [surah, ayah, position] = (value ?? "").split(":").map(Number);
  return [surah, ayah, position].every((part) => Number.isInteger(part) && part > 0)
    ? { surah, ayah, position }
    : null;
}

const ARABIC_LETTER = /[ء-يٮ-ۓۺ-ۼ]/u;

/**
 * The words of an ayah's Uthmani text by `position_in_verse`, the first at
 * index 0. A pause or sajda mark written apart belongs to the word before it,
 * as in the Quran Foundation word list.
 */
export function quranWords(text: string): string[] {
  const words: string[] = [];
  for (const token of text.trim().split(/\s+/u)) {
    if (!token) continue;
    if (words.length > 0 && !ARABIC_LETTER.test(token)) words[words.length - 1] += ` ${token}`;
    else words.push(token);
  }
  return words;
}

/**
 * The text of an ayah in parts: the basmala written before the first ayah of
 * most surahs is not one of its words, so it carries no positions.
 */
export function ayahTextParts(surah: number, ayah: number, text: string): { text: string; words: string[] | null }[] {
  const parts = ayah === 1 && surah !== 1 && surah !== 9
    ? splitDuaArabic(text)
    : [{ text, opening: false }];
  return parts.map((part) => ({ text: part.text, words: part.opening ? null : quranWords(part.text) }));
}

/** How many words of each ayah `range` holds, given each ayah's word count. */
export function wordRangeCount(range: QuranWordRange, wordsInAyah: (ayah: number) => number): number {
  let count = 0;
  for (let ayah = range.start.ayah; ayah <= range.end.ayah; ayah += 1) {
    const from = ayah === range.start.ayah ? range.start.position : 1;
    const to = ayah === range.end.ayah ? range.end.position : wordsInAyah(ayah);
    count += Math.max(0, to - from + 1);
  }
  return count;
}

type Box = { top: number; bottom: number; left: number; right: number };

/** How far a handle's knob and its touch target reach under the selection. */
export const WORD_RANGE_HANDLE_REACH = 32;
const BAR_MARGIN = 12;
const BAR_GAP = 10;

/**
 * Where the selection bar's top-left corner goes in a viewport of `size`:
 * above `selection`, else under it and its handles, else at the bottom.
 * Centred on the selection and kept off the sides, as in the app.
 */
export function wordRangeBarPlace(
  selection: Box | null,
  size: { width: number; height: number },
  bar: { width: number; height: number },
  insets: { top: number; bottom: number } = { top: 0, bottom: 0 },
): { x: number; y: number } {
  const bottom = size.height - insets.bottom - BAR_MARGIN - bar.height;
  const visible = selection !== null && selection.bottom > 0 && selection.top < size.height;
  const centre = visible ? (selection.left + selection.right) / 2 : size.width / 2;
  const x = Math.min(Math.max(centre - bar.width / 2, BAR_MARGIN), Math.max(BAR_MARGIN, size.width - BAR_MARGIN - bar.width));
  if (!visible) return { x, y: bottom };
  const above = selection.top - BAR_GAP - bar.height;
  if (above >= insets.top + BAR_MARGIN) return { x, y: above };
  const below = selection.bottom + WORD_RANGE_HANDLE_REACH + BAR_GAP;
  if (below <= bottom) return { x, y: below };
  return { x, y: bottom };
}
