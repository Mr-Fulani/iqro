"use client";

import { useCallback } from "react";
import { api } from "../lib/api";
import type { ContentShareText } from "../lib/content-share";
import { useI18n } from "../lib/i18n-context";
import ContentShareDialog from "./ContentShareDialog";

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
  translator: string;
};

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
  const [arabicText, meaning] = await Promise.all([arabic, translation]);
  return { arabic: arabicText, translation: meaning, reference: meaning.trim() ? target.translator.trim() : "" };
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
