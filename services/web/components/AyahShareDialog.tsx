"use client";

import { useCallback } from "react";
import { api } from "../lib/api";
import type { ContentShareText } from "../lib/content-share";
import { useI18n } from "../lib/i18n-context";
import { loadQuranFont, quranFontFamily } from "../lib/quran-font";
import type { ShareCardGlyph } from "../lib/share-card";
import { isTajweedMushaf } from "../lib/tajweed";
import ContentShareDialog from "./ContentShareDialog";
import { ayahGlyphs } from "./QuranFoundationMushafPage";

/** What the reader showed when the ayah was shared; missing text is fetched. */
export type AyahShareTarget = {
  ayahKey: string;
  edition: string;
  /** «Аль-Ан‘ам · 6:1». */
  title: string;
  url: string;
  arabic: string | undefined;
  /** The selected translation, also when the reader hides it, as in the app. */
  translationId: number | null;
  translation: string | undefined;
};

/**
 * The ayah in the coloured QCF V4 Tajweed page fonts of Quran.Foundation
 * Mushaf 19, over every page it spans, with the fonts loaded as the reader
 * loads them.
 */
async function tajweedGlyphs(ayahKey: string): Promise<ShareCardGlyph[]> {
  const mushaf = (await api.getQuranFoundationMushafs()).find(isTajweedMushaf);
  if (!mushaf) return [];
  const index = await api.getQuranFoundationMushafIndex(mushaf.source_id);
  const pages = await Promise.all((index.verse_pages[ayahKey] ?? [])
    .map((pageNumber) => api.getQuranFoundationMushafPage(mushaf.source_id, pageNumber)));
  await Promise.all(pages.map((page) => loadQuranFont(
    quranFontFamily(mushaf.source_id, page),
    page.rendering.available ? page.rendering.font_url : undefined,
  )));
  return pages.flatMap((page) => {
    const words = new Map(page.words.map((word) => [String(word.id), word]));
    // As the reader's bidi-override words, drawn in the order of their glyphs.
    return ayahGlyphs(mushaf, page, ayahKey).map(({ key, text, fontFamily }) => ({
      text: words.get(key)?.css_class?.split(/\s+/).includes("bidi-override") ? `\u202e${text}\u202c` : text,
      fontFamily,
    }));
  });
}

async function ayahShareText(target: AyahShareTarget): Promise<ContentShareText> {
  const [surah, ayah] = target.ayahKey.split(":").map(Number);
  const arabic = target.arabic !== undefined
    ? Promise.resolve(target.arabic)
    : api.getAyah(target.edition, surah, ayah).then((value) => value.text_uthmani);
  const translation = target.translation !== undefined || target.translationId === null
    ? Promise.resolve(target.translation ?? "")
    : api.getSurahTranslation(target.translationId, surah)
      .then((verses) => verses.find((verse) => verse.verse_key === target.ayahKey)?.text ?? "")
      .catch(() => "");
  const arabicGlyphs = tajweedGlyphs(target.ayahKey);
  arabicGlyphs.catch(() => {});
  const [arabicText, meaning] = await Promise.all([arabic, translation]);
  // Neither the picture nor the message names the translator.
  return { arabic: arabicText, arabicGlyphs, translation: meaning, reference: "" };
}

/** The ayah's picture with the Arabic, the meaning and the link. */
export default function AyahShareDialog({
  target,
  onClose,
}: {
  target: AyahShareTarget;
  onClose: () => void;
}) {
  const { t } = useI18n();
  const load = useCallback(() => ayahShareText(target), [target]);
  const [surah, ayah] = target.ayahKey.split(":");
  return (
    <ContentShareDialog
      heading={t("ayahShare.action")}
      title={target.title}
      url={target.url}
      fileName={`iqro-${surah}-${ayah}.png`}
      contentType="ayah"
      previewAlt={t("ayahShare.previewAlt", { ayah: target.ayahKey })}
      load={load}
      onClose={onClose}
    />
  );
}
