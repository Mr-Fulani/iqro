"use client";

import { useEffect, useId, useRef, useState } from "react";
import { trackEvent } from "../lib/analytics";
import { contentShareText, type ContentShareText } from "../lib/content-share";
import { useI18n } from "../lib/i18n-context";
import { renderShareCard } from "../lib/share-card";

type Picture = { file: File; url: string };

/**
 * The web counterpart of the app's shareContent: a picture with the Arabic,
 * the meaning and the link. Web Share sends the picture where the browser can
 * share files; the picture can always be downloaded and the link copied, and
 * the text too where the browser has no Web Share.
 * Sharing waits for a press here, once the picture is ready, because browsers
 * refuse Web Share after the time the picture takes to draw.
 */
export default function ContentShareDialog({
  heading,
  title,
  url,
  fileName,
  previewAlt,
  contentType,
  load,
  onClose,
}: {
  heading: string;
  /** «Аль-Ан‘ам · 6:1», or the du'a's chapter and number. */
  title: string;
  url: string;
  fileName: string;
  previewAlt: string;
  /** What is shared, for the visit statistics. */
  contentType: "ayah" | "dua";
  /** The text; an ayah the reader has not shown is fetched. Keep it stable. */
  load: () => ContentShareText | Promise<ContentShareText>;
  onClose: () => void;
}) {
  const { t } = useI18n();
  const dialog = useRef<HTMLDialogElement>(null);
  const titleId = useId();
  const [text, setText] = useState<string | null>(null);
  const [picture, setPicture] = useState<Picture | null>(null);
  const [failed, setFailed] = useState(false);
  const [notice, setNotice] = useState("");
  const readInIqro = t("contentShare.readInIqro");

  useEffect(() => {
    const element = dialog.current;
    if (element && !element.open) element.showModal();
  }, []);

  useEffect(() => {
    let cancelled = false;
    const objectUrls: string[] = [];
    void Promise.resolve().then(load).then(async (content) => {
      if (cancelled) return;
      setText(contentShareText(title, content, readInIqro, url));
      const { arabic, translation, reference } = content;
      const root = getComputedStyle(document.documentElement);
      // A late font brings a second picture, which replaces the first.
      await renderShareCard(
        { title, arabic, translation, reference },
        {
          arabic: root.getPropertyValue("--font-arabic").trim() || "serif",
          text: root.getPropertyValue("--font-sans").trim() || "sans-serif",
        },
        "/iqro-wax-seal-128.webp",
        (png) => {
          if (cancelled) return;
          const pictureUrl = URL.createObjectURL(png);
          objectUrls.push(pictureUrl);
          setPicture({ file: new File([png], fileName, { type: "image/png" }), url: pictureUrl });
        },
      );
    }).catch(() => {
      if (cancelled) return;
      setFailed(true);
      // Without the text the title and the link can still be shared.
      setText((current) => current ?? `${title}\n\n${readInIqro}: ${url}`);
    });
    return () => {
      cancelled = true;
      objectUrls.forEach((objectUrl) => URL.revokeObjectURL(objectUrl));
    };
  }, [fileName, load, readInIqro, title, url]);

  const canShare = typeof navigator !== "undefined" && typeof navigator.share === "function";

  const share = async () => {
    if (!text) return;
    setNotice("");
    const files = picture && navigator.canShare?.({ files: [picture.file] }) ? [picture.file] : undefined;
    try {
      await navigator.share({ title, text, files });
      trackEvent("share", { content_type: contentType, method: "native" });
    } catch (error) {
      if (!(error instanceof DOMException && error.name === "AbortError")) {
        setNotice(t("contentShare.shareError"));
      }
    }
  };

  const copyText = async () => {
    if (!text) return;
    try {
      await navigator.clipboard.writeText(text);
      setNotice(t("contentShare.textCopied"));
      trackEvent("share", { content_type: contentType, method: "copy_text" });
    } catch {
      setNotice(t("contentShare.copyTextError"));
    }
  };

  const copyLink = async () => {
    try {
      await navigator.clipboard.writeText(url);
      setNotice(t("contentShare.linkCopied"));
      trackEvent("share", { content_type: contentType, method: "copy_link" });
    } catch {
      setNotice(t("contentShare.copyError"));
    }
  };

  return (
    <dialog
      ref={dialog}
      className="ayah-annotation-dialog content-share-dialog"
      aria-labelledby={titleId}
      onClose={onClose}
    >
      <div className="ayah-annotation-dialog-head">
        <div>
          <h2 id={titleId}>{heading}</h2>
          <p className="field-help">{title}</p>
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

      <div className="content-share-preview" aria-busy={!picture && !failed}>
        {picture ? (
          // eslint-disable-next-line @next/next/no-img-element -- a local blob of the drawn card.
          <img src={picture.url} alt={previewAlt} width={540} height={675} />
        ) : (
          <p className={failed ? "alert alert-error" : "field-help"} role={failed ? "alert" : "status"}>
            {failed ? t("contentShare.imageError") : t("contentShare.preparing")}
          </p>
        )}
      </div>

      {notice && <p className="field-help" role="status">{notice}</p>}

      <div className="ayah-annotation-actions">
        <button type="button" className="btn btn-secondary" onClick={() => void copyLink()}>
          {t("contentShare.copyLink")}
        </button>
        {!canShare && (
          <button type="button" className="btn btn-secondary" onClick={() => void copyText()} disabled={!text}>
            {t("contentShare.copyText")}
          </button>
        )}
        {picture && (
          <a className="btn btn-secondary" href={picture.url} download={picture.file.name}>
            {t("contentShare.download")}
          </a>
        )}
        {canShare && (
          <button
            type="button"
            className="btn btn-primary"
            onClick={() => void share()}
            disabled={!text || (!picture && !failed)}
          >
            {t("contentShare.share")}
          </button>
        )}
      </div>
    </dialog>
  );
}
