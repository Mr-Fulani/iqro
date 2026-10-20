"use client";

import { useCallback } from "react";
import type { DuaEntry } from "../lib/api";
import { duaShareText, duaShareTitle } from "../lib/dua-share";
import { useI18n } from "../lib/i18n-context";
import { localizedPath } from "../lib/routing";
import ContentShareDialog from "./ContentShareDialog";

/** The du'a's picture with its chapter, the Arabic, the meaning and the link, as in the app. */
export default function DuaShareDialog({
  entry,
  onClose,
}: {
  entry: DuaEntry;
  onClose: () => void;
}) {
  const { locale, t } = useI18n();
  const repetitionsLabel = t("duaShare.repetitions");
  const load = useCallback(
    () => duaShareText(entry, locale, repetitionsLabel),
    [entry, locale, repetitionsLabel],
  );
  return (
    <ContentShareDialog
      heading={t("duaShare.action")}
      title={duaShareTitle(entry, locale)}
      url={new URL(
        localizedPath(locale, `/dua/${entry.collection}/${entry.source_number}`),
        window.location.origin,
      ).href}
      fileName={`iqro-${entry.collection}-${entry.source_number}.png`}
      previewAlt={t("duaShare.previewAlt", { number: entry.source_number })}
      load={load}
      onClose={onClose}
    />
  );
}
