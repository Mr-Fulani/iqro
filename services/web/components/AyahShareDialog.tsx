"use client";

import { useEffect, useId, useRef, useState } from "react";
import { api } from "../lib/api";
import { useI18n } from "../lib/i18n-context";
import { renderShareCard } from "../lib/share-card";

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

type Picture = { file: File; url: string };

/**
 * The web counterpart of the app's ayah share: a picture with the Arabic, the
 * meaning and the link. Web Share sends the picture where the browser can
 * share files; the picture can always be downloaded and the link copied.
 * Sharing waits for a press here, once the picture is ready, because browsers
 * refuse Web Share after the time the picture takes to draw.
 */
export default function AyahShareDialog({
  target,
  onClose,
}: {
  target: AyahShareTarget;
  onClose: () => void;
}) {
  const { t } = useI18n();
  const dialog = useRef<HTMLDialogElement>(null);
  const titleId = useId();
  const [text, setText] = useState<string | null>(null);
  const [picture, setPicture] = useState<Picture | null>(null);
  const [failed, setFailed] = useState(false);
  const [notice, setNotice] = useState("");
  const readInIqro = t("ayahShare.readInIqro");

  useEffect(() => {
    const element = dialog.current;
    if (element && !element.open) element.showModal();
  }, []);

  useEffect(() => {
    let cancelled = false;
    const objectUrls: string[] = [];
    const [surah, ayah] = target.ayahKey.split(":").map(Number);
    const arabic = target.arabic !== undefined
      ? Promise.resolve(target.arabic)
      : api.getAyah(target.edition, surah, ayah).then((value) => value.text_uthmani);
    const translation = target.translation !== undefined || target.translationId === null
      ? Promise.resolve(target.translation ?? "")
      : api.getSurahTranslation(target.translationId, surah)
        .then((verses) => verses.find((verse) => verse.verse_key === target.ayahKey)?.text ?? "")
        .catch(() => "");
    void Promise.all([arabic, translation]).then(async ([arabicText, meaning]) => {
      const reference = meaning.trim() ? target.translator.trim() : "";
      if (cancelled) return;
      // The message of the app: the title, the Arabic, the meaning in quotes,
      // its source and the link.
      setText([
        target.title,
        arabicText.trim(),
        meaning.trim() && `«${meaning.trim()}»`,
        reference,
        `${readInIqro}: ${target.url}`,
      ].filter(Boolean).join("\n\n"));
      const root = getComputedStyle(document.documentElement);
      // A late font brings a second picture, which replaces the first.
      await renderShareCard(
        { title: target.title, arabic: arabicText, translation: meaning, reference },
        {
          arabic: root.getPropertyValue("--font-arabic").trim() || "serif",
          text: root.getPropertyValue("--font-sans").trim() || "sans-serif",
        },
        "/iqro-wax-seal-128.webp",
        (png) => {
          if (cancelled) return;
          const url = URL.createObjectURL(png);
          objectUrls.push(url);
          setPicture({ file: new File([png], `iqro-${surah}-${ayah}.png`, { type: "image/png" }), url });
        },
      );
    }).catch(() => {
      if (cancelled) return;
      setFailed(true);
      // Without the ayah's text the title and the link can still be shared.
      setText((current) => current ?? `${target.title}\n\n${readInIqro}: ${target.url}`);
    });
    return () => {
      cancelled = true;
      objectUrls.forEach((url) => URL.revokeObjectURL(url));
    };
  }, [readInIqro, target]);

  const canShare = typeof navigator !== "undefined" && typeof navigator.share === "function";

  const share = async () => {
    if (!text) return;
    setNotice("");
    const files = picture && navigator.canShare?.({ files: [picture.file] }) ? [picture.file] : undefined;
    try {
      await navigator.share({ title: target.title, text, files });
    } catch (error) {
      if (!(error instanceof DOMException && error.name === "AbortError")) {
        setNotice(t("ayahShare.shareError"));
      }
    }
  };

  const copyLink = async () => {
    try {
      await navigator.clipboard.writeText(target.url);
      setNotice(t("ayahShare.linkCopied"));
    } catch {
      setNotice(t("ayahShare.copyError"));
    }
  };

  return (
    <dialog
      ref={dialog}
      className="ayah-annotation-dialog ayah-share-dialog"
      aria-labelledby={titleId}
      onClose={onClose}
    >
      <div className="ayah-annotation-dialog-head">
        <div>
          <h2 id={titleId}>{t("ayahShare.action")}</h2>
          <p className="field-help">{target.title}</p>
        </div>
        <button
          type="button"
          className="btn btn-secondary btn-sm"
          onClick={() => dialog.current?.close()}
          aria-label={t("common.close")}
        >
          ×
        </button>
      </div>

      <div className="ayah-share-preview" aria-busy={!picture && !failed}>
        {picture ? (
          // eslint-disable-next-line @next/next/no-img-element -- a local blob of the drawn card.
          <img src={picture.url} alt={t("ayahShare.previewAlt", { ayah: target.ayahKey })} width={540} height={675} />
        ) : (
          <p className={failed ? "alert alert-error" : "field-help"} role={failed ? "alert" : "status"}>
            {failed ? t("ayahShare.imageError") : t("ayahShare.preparing")}
          </p>
        )}
      </div>

      {notice && <p className="field-help" role="status">{notice}</p>}

      <div className="ayah-annotation-actions">
        <button type="button" className="btn btn-secondary" onClick={() => void copyLink()}>
          {t("ayahShare.copyLink")}
        </button>
        {picture && (
          <a className="btn btn-secondary" href={picture.url} download={picture.file.name}>
            {t("ayahShare.download")}
          </a>
        )}
        {canShare && (
          <button
            type="button"
            className="btn btn-primary"
            onClick={() => void share()}
            disabled={!text || (!picture && !failed)}
          >
            {t("ayahShare.share")}
          </button>
        )}
      </div>
    </dialog>
  );
}
