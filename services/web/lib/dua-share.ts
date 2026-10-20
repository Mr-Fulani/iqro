import type { DuaEntry } from "./api.ts";
import type { Locale } from "./i18n.ts";

const CASE_WORDS = /(^|[\s«"(\[])(аллах|allah|коран|quran|пророк|мухаммад|muhammad|ислам)/gu;

/**
 * Titles some sources print in capitals, in sentence case, as the app shows
 * them (duaDisplayTitle in dua_presentation.dart). The names that keep a
 * capital — Allah, the Quran, the Prophet — get it back; titles in ordinary
 * case or in scripts without case stay as they are. Case follows the locale,
 * so Turkish capitals keep their dotless and dotted i.
 */
export function duaDisplayTitle(title: string, locale: Locale): string {
  // Capitals with a lowercase gloss, «… МОЛИТВЫ (ду'ау-ль-истифтах)», count
  // as capitals too.
  const upper = title.match(/\p{Lu}/gu)?.length ?? 0;
  const small = title.match(/\p{Ll}/gu)?.length ?? 0;
  if (upper <= small) return title;
  return title
    .toLocaleLowerCase(locale)
    .replace(CASE_WORDS, (_, before: string, word: string) =>
      `${before}${word[0].toLocaleUpperCase(locale)}${word.slice(1)}`)
    .replace(/\p{L}/u, (letter) => letter.toLocaleUpperCase(locale));
}

/** «Слова поминания при пробуждении ото сна · #1», as the app's share title. */
export function duaShareTitle(entry: DuaEntry, locale: Locale): string {
  return `${duaDisplayTitle(entry.category.title, locale)} · #${entry.source_number}`;
}

/**
 * The du'a as the app shares it (duaContentShare): the Arabic, the meaning,
 * how many times it is said and its sources. Arabic pages show no meaning, as
 * there it repeats the du'a itself.
 */
export function duaShareText(entry: DuaEntry, locale: Locale, repetitionsLabel: string) {
  const repetition = entry.repetition_label.trim()
    || (entry.repetitions > 1 ? String(entry.repetitions) : "");
  const sources = [
    entry.source?.title.trim() || entry.source?.provider.trim() || "",
    ...entry.evidence.map((evidence) => evidence.source_reference.trim()),
  ].filter((source, index, all) => source && all.indexOf(source) === index);
  return {
    arabic: entry.arabic_text,
    translation: locale === "ar" ? "" : entry.translation?.meaning_text ?? "",
    note: repetition ? `${repetitionsLabel}: ${repetition}` : "",
    reference: sources.join(" · "),
  };
}
