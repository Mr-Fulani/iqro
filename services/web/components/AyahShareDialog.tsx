"use client";

import { useCallback } from "react";
import { api } from "../lib/api";
import type { ContentShareText } from "../lib/content-share";
import { useI18n } from "../lib/i18n-context";
import { loadQuranFont, quranFontFamily } from "../lib/quran-font";
import { SHARE_CARD_ARABIC_FONT, type ShareCardGlyph } from "../lib/share-card";
import { ayahEndSign, wordRangeShare, type AyahShareScript } from "../lib/word-range-share";
import type { QuranWordRange } from "../lib/word-range";
import { readMushafVariantPreference, selectedMushaf } from "../lib/mushaf-script";
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
  /** The selected words, when a part of the surah is shared and not one whole ayah. */
  part?: { range: QuranWordRange; ayahs: readonly { number: number; text_uthmani: string }[] };
};

/**
 * Ayahs in the page fonts of the Mushaf the reader picked, over every page
 * they span, with the fonts loaded as the reader loads them. Nothing for a
 * Mushaf of word images and for one that paints its own colours (tajweed),
 * which cannot take the card's ink: the card then draws the plain script. The
 * app does the same (ayahShareGlyphs).
 */
async function mushafScripts(ayahKeys: string[]): Promise<Map<string, AyahShareScript>> {
  const scripts = new Map<string, AyahShareScript>();
  const mushaf = selectedMushaf(await api.getQuranFoundationMushafs(), readMushafVariantPreference());
  if (!mushaf || mushaf.rendering.mode === "word-images") return scripts;
  const index = await api.getQuranFoundationMushafIndex(mushaf.source_id);
  const numbers = [...new Set(ayahKeys.flatMap((ayahKey) => index.verse_pages[ayahKey] ?? []))];
  const pages = await Promise.all(numbers
    .map((pageNumber) => api.getQuranFoundationMushafPage(mushaf.source_id, pageNumber)));
  const coloured = pages.some((page) => !page.rendering.available || page.rendering.mode === "word-images"
    || ("color_format" in page.rendering && page.rendering.color_format)
    || page.words.some((word) => word.text_runs));
  if (pages.length === 0 || coloured) return scripts;
  await Promise.all(pages.map((page) => loadQuranFont(
    quranFontFamily(mushaf.source_id, page),
    page.rendering.available ? page.rendering.font_url : undefined,
  )));
  for (const ayahKey of ayahKeys) {
    const script: AyahShareScript = { words: [], end: null };
    for (const page of pages) {
      const words = new Map(page.words.map((word) => [String(word.id), word]));
      for (const { key, text, fontFamily } of ayahGlyphs(mushaf, page, ayahKey)) {
        // As the reader's bidi-override words, drawn in the order of their glyphs.
        const glyph = {
          text: words.get(key)?.css_class?.split(/\s+/).includes("bidi-override") ? `\u202e${text}\u202c` : text,
          fontFamily,
        };
        if (words.get(key)?.char_type_name === "end") script.end = glyph;
        else script.words.push(glyph);
      }
    }
    if (script.words.length > 0) scripts.set(ayahKey, script);
  }
  return scripts;
}

// The whole ayah, or the selected words of the target, in the Mushaf's script; null draws the plain one.
async function mushafUnits(target: AyahShareTarget): Promise<ShareCardGlyph[][] | null> {
  const part = target.part;
  if (!part) {
    const script = (await mushafScripts([target.ayahKey])).get(target.ayahKey);
    if (!script) return null;
    const units = script.words.map((word) => [word]);
    if (script.end) units[units.length - 1].push(script.end);
    return units;
  }
  const surah = part.range.start.surah;
  const keys = part.ayahs
    .filter((ayah) => ayah.number >= part.range.start.ayah && ayah.number <= part.range.end.ayah)
    .map((ayah) => `${surah}:${ayah.number}`);
  const scripts = await mushafScripts(keys).catch(() => new Map<string, AyahShareScript>());
  return wordRangeShare({
    range: part.range,
    surahName: "",
    ayahs: part.ayahs,
    partOf: () => "",
    plainFont: SHARE_CARD_ARABIC_FONT,
    scripts: new Map([...scripts].map(([key, script]) => [Number(key.split(":")[1]), script])),
  }).units;
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
  const arabicUnits = mushafUnits(target);
  arabicUnits.catch(() => {});
  const [arabicText, meaning] = await Promise.all([arabic, translation]);
  // Neither the picture nor the message names the translator.
  return {
    arabic: arabicText,
    arabicUnits,
    arabicEnd: target.part ? "" : ayahEndSign(ayah),
    cardReference: target.title,
    translation: meaning,
    reference: "",
  };
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
      fileName={`iqro-${surah}-${ayah}`}
      contentType="ayah"
      previewAlt={t("ayahShare.previewAlt", { ayah: target.ayahKey })}
      load={load}
      onClose={onClose}
    />
  );
}
