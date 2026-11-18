"use client";

import { useEffect, useId, useRef, useState } from "react";
import { trackEvent } from "../lib/analytics";
import { contentShareText, type ContentShareText } from "../lib/content-share";
import { useI18n } from "../lib/i18n-context";
import {
  parseShareCardStyle,
  renderShareCards,
  SHARE_CARD_COLOURS,
  SHARE_CARD_STYLE_KEY,
  type ShareCardStyle,
} from "../lib/share-card";

type Picture = { file: File; url: string };

function storedStyle(): ShareCardStyle {
  try {
    return parseShareCardStyle(window.localStorage.getItem(SHARE_CARD_STYLE_KEY));
  } catch {
    return parseShareCardStyle(null);
  }
}

/**
 * The web counterpart of the app's share sheet: the picture of the text on
 * silk, one card or a series, in the shape and colour the reader picks. Web
 * Share sends the pictures where the browser can share files; they can always
 * be downloaded and the link copied, and the text too where the browser has
 * no Web Share. A text too long for a series goes as text.
 * Sharing waits for a press here, once the pictures are ready, because
 * browsers refuse Web Share after the time they take to draw.
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
  /** Without an extension: «iqro-2-286»; a series adds «-1», «-2». */
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
  const [style, setStyle] = useState<ShareCardStyle>(storedStyle);
  const [text, setText] = useState<string | null>(null);
  // Null while the cards are drawn; empty when there is no picture.
  const [drawn, setDrawn] = useState<{ style: ShareCardStyle; pictures: Picture[]; tooLong: boolean; failed: boolean } | null>(null);
  const [shown, setShown] = useState(0);
  const [notice, setNotice] = useState("");
  const readInIqro = t("contentShare.readInIqro");
  const current = drawn?.style === style ? drawn : null;
  const pictures = current?.pictures ?? [];

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
      const cards = await renderShareCards({ ...content, cardReference: content.cardReference ?? title }, style);
      if (cancelled) return;
      setShown(0);
      setDrawn({
        style,
        tooLong: cards === null,
        failed: false,
        pictures: (cards ?? []).map((card, index, all) => {
          const pictureUrl = URL.createObjectURL(card);
          objectUrls.push(pictureUrl);
          const name = all.length > 1 ? `${fileName}-${index + 1}.jpg` : `${fileName}.jpg`;
          return { file: new File([card], name, { type: "image/jpeg" }), url: pictureUrl };
        }),
      });
    }).catch(() => {
      if (cancelled) return;
      setDrawn({ style, pictures: [], tooLong: false, failed: true });
      // Without the text the title and the link can still be shared.
      setText((known) => known ?? `${title}\n\n${readInIqro}: ${url}`);
    });
    return () => {
      cancelled = true;
      objectUrls.forEach((objectUrl) => URL.revokeObjectURL(objectUrl));
    };
  }, [fileName, load, readInIqro, style, title, url]);

  const restyle = (next: ShareCardStyle) => {
    setStyle(next);
    try {
      window.localStorage.setItem(SHARE_CARD_STYLE_KEY, `${next.format}:${next.colour}`);
    } catch {
      // The style holds for this dialog only.
    }
  };

  const canShare = typeof navigator !== "undefined" && typeof navigator.share === "function";

  const share = async () => {
    if (!text) return;
    setNotice("");
    const all = pictures.map((picture) => picture.file);
    const files = all.length > 0 && navigator.canShare?.({ files: all }) ? all : undefined;
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

  const download = () => {
    for (const picture of pictures) {
      const link = document.createElement("a");
      link.href = picture.url;
      link.download = picture.file.name;
      link.click();
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

      <div
        className="content-share-preview"
        data-format={style.format}
        aria-busy={!current}
        onScroll={(event) => {
          const { scrollLeft, clientWidth } = event.currentTarget;
          setShown(Math.round(Math.abs(scrollLeft) / clientWidth));
        }}
      >
        {pictures.length > 0 ? pictures.map((picture, index) => (
          // eslint-disable-next-line @next/next/no-img-element -- a local blob of the drawn card.
          <img
            key={picture.url}
            src={picture.url}
            alt={pictures.length > 1
              ? `${previewAlt} · ${t("contentShare.part", { number: index + 1, total: pictures.length })}`
              : previewAlt}
          />
        )) : (
          <p className={current?.failed ? "alert alert-error" : "field-help"} role={current?.failed ? "alert" : "status"}>
            {!current
              ? t("contentShare.preparing")
              : current.failed ? t("contentShare.imageError") : t("contentShare.tooLong")}
          </p>
        )}
      </div>

      {pictures.length > 1 && (
        <p className="field-help content-share-part" role="status">
          {t("contentShare.part", { number: Math.min(shown, pictures.length - 1) + 1, total: pictures.length })}
        </p>
      )}

      <div className="content-share-style">
        <div className="content-share-formats" role="group" aria-label={t("contentShare.format")}>
          {(["story", "post"] as const).map((format) => (
            <button
              key={format}
              type="button"
              className="btn btn-secondary btn-sm"
              aria-pressed={style.format === format}
              onClick={() => restyle({ ...style, format })}
            >
              {t(`contentShare.${format}`)}
            </button>
          ))}
        </div>
        <div className="content-share-colours" role="group" aria-label={t("contentShare.colour")}>
          {Object.entries(SHARE_CARD_COLOURS).map(([colour, tint]) => (
            <button
              key={colour}
              type="button"
              className="content-share-colour"
              style={{ background: tint }}
              aria-pressed={style.colour === colour}
              aria-label={t(`contentShare.colour.${colour}` as "contentShare.colour.emerald")}
              title={t(`contentShare.colour.${colour}` as "contentShare.colour.emerald")}
              onClick={() => restyle({ ...style, colour })}
            />
          ))}
        </div>
      </div>

      {notice && <p className="field-help" role="status">{notice}</p>}

      <div className="ayah-annotation-actions">
        <button type="button" className="btn btn-secondary" onClick={() => void copyLink()}>
          {t("contentShare.copyLink")}
        </button>
        {(!canShare || current?.tooLong) && (
          <button type="button" className="btn btn-secondary" onClick={() => void copyText()} disabled={!text}>
            {t("contentShare.copyText")}
          </button>
        )}
        {pictures.length > 0 && (
          <button type="button" className="btn btn-secondary" onClick={download}>
            {t(pictures.length > 1 ? "contentShare.downloadAll" : "contentShare.download")}
          </button>
        )}
        {canShare && (
          <button
            type="button"
            className="btn btn-primary"
            onClick={() => void share()}
            disabled={!text || !current}
          >
            {t("contentShare.share")}
          </button>
        )}
      </div>
    </dialog>
  );
}
