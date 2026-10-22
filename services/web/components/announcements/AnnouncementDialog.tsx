"use client";

import { useEffect, useId, useRef, useState } from "react";
import { externalLink, type Announcement, type AnnouncementSurface } from "../../lib/announcements";
import { useI18n } from "../../lib/i18n-context";
import { IntentPrefetchLink } from "../IntentPrefetchLink";
import { clickAnnouncement, readAnnouncement } from "./announcement-store";
import { AnnouncementBody, AnnouncementPicture, KIND_LABELS } from "./AnnouncementParts";

/**
 * The window of one or several announcements: from the bubble on a phone it
 * grows out of the bubble's corner; on a computer it is the step window.
 */
export function AnnouncementDialog({
  items,
  surface,
  onClose,
}: {
  items: Announcement[];
  surface: AnnouncementSurface;
  onClose: () => void;
}) {
  const { t, formatDate } = useI18n();
  const dialog = useRef<HTMLDialogElement | null>(null);
  const titleId = useId();
  const [page, setPage] = useState(0);
  const item = items[Math.min(page, items.length - 1)];

  useEffect(() => {
    const element = dialog.current;
    if (element && !element.open) element.showModal();
  }, []);

  useEffect(() => {
    if (item) readAnnouncement(item, surface, true);
  }, [item, surface]);

  if (!item) return null;
  const internal = item.action.web_path;
  const external = externalLink(item, surface);
  const label = item.action.label || t("news.more");

  return (
    <dialog
      ref={dialog}
      className={`announcement-dialog announcement-dialog--${surface}`}
      aria-labelledby={titleId}
      onClose={onClose}
      onClick={(event) => {
        if (event.target === event.currentTarget) dialog.current?.close();
      }}
      data-testid="announcement-dialog"
    >
      <div className="announcement-dialog-head">
        <span className="announcement-dialog-counter">
          {items.length > 1
            ? `${t("news.title")} · ${t("news.counter", { current: page + 1, total: items.length })}`
            : t("news.title")}
        </span>
        <button
          type="button"
          className="announcement-close"
          onClick={() => dialog.current?.close()}
          aria-label={t("common.close")}
        >
          ×
        </button>
      </div>

      <article className="announcement-dialog-page" key={item.id}>
        <AnnouncementPicture item={item} size={item.image ? 96 : 64} />
        <p className="eyebrow">{t(KIND_LABELS[item.kind])}</p>
        <h2 id={titleId}>{item.title}</h2>
        <p className="announcement-summary">{item.summary}</p>
        <AnnouncementBody body={item.body} />
        {item.steps.length ? (
          <ol className="announcement-steps">
            {item.steps.map((step, index) => (
              <li key={index}>
                {step.image_url ? (
                  // eslint-disable-next-line @next/next/no-img-element -- step illustrations from the CDN.
                  <img src={step.image_url} alt="" width={step.width ?? undefined} height={step.height ?? undefined} loading="lazy" />
                ) : null}
                <strong>{step.title}</strong>
                {step.text ? <span>{step.text}</span> : null}
              </li>
            ))}
          </ol>
        ) : null}
        <p className="announcement-date">{formatDate(item.starts_at, { day: "numeric", month: "long" })}</p>
        {internal ? (
          <IntentPrefetchLink
            href={internal}
            className="btn btn-primary btn-lg announcement-cta"
            onClick={() => {
              clickAnnouncement(item, surface);
              dialog.current?.close();
            }}
          >
            {label}
          </IntentPrefetchLink>
        ) : external ? (
          <a
            href={external}
            target="_blank"
            rel="noopener noreferrer"
            className="btn btn-primary btn-lg announcement-cta"
            onClick={() => clickAnnouncement(item, surface)}
          >
            {label} ↗
          </a>
        ) : null}
      </article>

      {items.length > 1 ? (
        <div className="announcement-dialog-pager">
          <div className="announcement-dots" aria-hidden="true">
            {items.map((entry, index) => (
              <span key={entry.id} className={index === page ? "is-active" : undefined} />
            ))}
          </div>
          <div className="announcement-pager-buttons">
            <button
              type="button"
              className="announcement-pager-button"
              onClick={() => setPage((value) => Math.max(0, value - 1))}
              disabled={page === 0}
              aria-label={t("news.previous")}
            >
              <span aria-hidden="true">‹</span>
            </button>
            <button
              type="button"
              className="announcement-pager-button"
              onClick={() => setPage((value) => Math.min(items.length - 1, value + 1))}
              disabled={page === items.length - 1}
              aria-label={t("news.next")}
            >
              <span aria-hidden="true">›</span>
            </button>
          </div>
        </div>
      ) : null}
    </dialog>
  );
}
