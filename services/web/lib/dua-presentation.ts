import type { DuaEntry } from "./api.ts";

export function duaEntryKey(entry: DuaEntry): string {
  return `${entry.collection}:${entry.source_number}`;
}

export function duaEntryPath(entry: DuaEntry): string {
  return `/dua/${entry.collection}/${entry.source_number}`;
}

export function duaAnchor(entry: DuaEntry): string {
  return `dua-${entry.collection}-${entry.source_number}`;
}

/** What a list shows of a du'a: the meaning, or the Arabic where there is none. */
export function duaPreview(entry: DuaEntry, locale: string): { text: string; arabic: boolean } {
  const meaning = entry.translation?.meaning_text.trim() ?? "";
  return locale === "ar" || !meaning
    ? { text: entry.arabic_text, arabic: true }
    : { text: meaning, arabic: false };
}
