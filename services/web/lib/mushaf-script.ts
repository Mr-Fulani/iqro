import type { QuranFoundationMushafPage, QuranFoundationMushafWord } from "./api";
import { quranFontFamily } from "./quran-font.ts";

/** A word of an ayah as the selected Mushaf writes it, in its page's font. */
export type MushafScriptWord = {
  key: string;
  text: string;
  fontFamily: string;
  /** The source's own colour runs (tajweed), where it has them. */
  runs?: { text: string; color?: string }[];
  bidiOverride: boolean;
};

export type MushafAyahScript = { words: MushafScriptWord[]; end: MushafScriptWord | null };

function scriptWord(word: QuranFoundationMushafWord, fontFamily: string): MushafScriptWord {
  return {
    key: String(word.id),
    text: word.text,
    fontFamily,
    runs: word.text_runs?.map(({ text, color }) => ({ text, color })),
    bidiOverride: word.css_class?.split(/\s+/).includes("bidi-override") ?? false,
  };
}

/**
 * The ayah in the script of the selected Mushaf, for the text readers. Null
 * while one of its pages is not loaded, for a Mushaf of word images, and when
 * its words are not the `wordCount` words the reader counts: the plain text is
 * drawn then, and word selection stays right. The app does the same
 * (watchMushafAyahScript).
 */
export function mushafAyahScript(
  mushafId: number,
  ayahPages: readonly number[] | undefined,
  loaded: ReadonlyMap<number, QuranFoundationMushafPage>,
  verseKey: string,
  wordCount: number,
): MushafAyahScript | null {
  if (!ayahPages?.length) return null;
  const words: MushafScriptWord[] = [];
  let end: MushafScriptWord | null = null;
  for (const number of ayahPages) {
    const page = loaded.get(number);
    if (!page || !page.rendering.available || page.rendering.mode === "word-images") return null;
    const fontFamily = quranFontFamily(mushafId, page);
    for (const word of [...page.words].sort(
      (left, right) => left.position_in_page - right.position_in_page || left.id - right.id,
    )) {
      if (word.verse_key !== verseKey) continue;
      if (word.char_type_name === "word") words.push(scriptWord(word, fontFamily));
      else if (word.char_type_name === "end") end = scriptWord(word, fontFamily);
    }
  }
  return words.length === wordCount ? { words, end } : null;
}

/**
 * For each ayah of a reader, the Mushaf page that ended just before it, or
 * null: where the readers draw the line of a page's end.
 */
export function mushafPageEnds(pages: readonly (number | undefined)[]): (number | null)[] {
  return pages.map((page, index) => {
    const previous = pages[index - 1];
    return index > 0 && page !== undefined && previous !== undefined && page !== previous ? page - 1 : null;
  });
}

const arabicNumber = new Intl.NumberFormat("ar-EG", { useGrouping: false });

/** A number beside words of the interface: Arabic-Indic digits for a reader of Arabic, 0–9 for everyone else. */
export function readerDigits(locale: string, value: number): string {
  return locale === "ar" ? arabicNumber.format(value) : String(value);
}
