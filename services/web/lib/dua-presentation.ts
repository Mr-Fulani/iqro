import type { DuaEntry } from "./api.ts";
import type { MessageKey } from "./i18n.ts";

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

type Translate = (key: MessageKey, variables: Record<string, string | number>) => string;

/**
 * The source line under a du'a card in the reader's language (duaReference in
 * dua_presentation.dart): «Крепость мусульманина, № 75», «Коран, 2:126». The
 * evidence keeps the source's own English reference for the source dialog.
 */
export function duaReference(entry: DuaEntry, t: Translate): string {
  if (entry.collection === "hisn-al-muslim") {
    return t("dua.referenceHisn", { number: entry.source_number });
  }
  const quran = entry.evidence.find((item) => item.kind === "quran")?.source_reference.trim();
  if (quran) return t("dua.referenceQuran", { reference: quran });
  const source = entry.source?.title.trim() || entry.source?.provider.trim() || "";
  return source
    ? t("dua.referenceEntry", { source, number: entry.source_number })
    : `#${entry.source_number}`;
}
