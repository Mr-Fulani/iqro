"use client";

import { useState } from "react";
import {
  externalLink,
  forAudience,
  parseAnnouncementFeed,
  type Announcement,
  type AnnouncementFeedPage,
  type AnnouncementKind,
} from "../../lib/announcements";
import { useAuth } from "../../lib/auth-context";
import { useI18n } from "../../lib/i18n-context";
import type { MessageKey } from "../../lib/i18n";
import { IntentPrefetchLink } from "../IntentPrefetchLink";
import { clickAnnouncement, readAnnouncement, useAnnouncementState, useReceiptSync } from "./announcement-store";
import { AnnouncementDialog } from "./AnnouncementDialog";
import { AnnouncementPicture, KIND_LABELS } from "./AnnouncementParts";

const FILTERS: { kind: AnnouncementKind | null; label: MessageKey }[] = [
  { kind: null, label: "news.all" },
  { kind: "reciter", label: "news.filter.reciter" },
  { kind: "feature", label: "news.filter.feature" },
  { kind: "content", label: "news.filter.content" },
  { kind: "app_release", label: "news.filter.app_release" },
  { kind: "fundraising", label: "news.filter.fundraising" },
  { kind: "general", label: "news.filter.general" },
];

/** «What's new»: the whole history, newest first, pinned items on top. */
export function NewsFeed({ initialPage }: { initialPage: AnnouncementFeedPage }) {
  const { locale, t, formatDate } = useI18n();
  const { session } = useAuth();
  const state = useAnnouncementState();
  const [kind, setKind] = useState<AnnouncementKind | null>(null);
  const [page, setPage] = useState(initialPage);
  const [loading, setLoading] = useState(false);
  const [failed, setFailed] = useState(false);
  const [opened, setOpened] = useState<Announcement | null>(null);
  useReceiptSync(session?.user.id);

  const load = async (nextKind: AnnouncementKind | null, cursor: string | null) => {
    setLoading(true);
    setFailed(false);
    const query = new URLSearchParams({ platform: "web", locale });
    if (nextKind) query.set("kind", nextKind);
    if (cursor) query.set("cursor", cursor);
    try {
      const response = await fetch(`/api/v1/announcements?${query}`, { headers: { Accept: "application/json" } });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const next = parseAnnouncementFeed(await response.json());
      setPage((current) =>
        cursor ? { next_cursor: next.next_cursor, results: [...current.results, ...next.results] } : next,
      );
    } catch {
      setFailed(true);
    } finally {
      setLoading(false);
    }
  };

  const items = forAudience(page.results, session?.user.status === "active");

  return (
    <div className="news-feed">
      <div className="news-filters" role="group" aria-label={t("news.filterLabel")}>
        {FILTERS.map((filter) => (
          <button
            key={filter.label}
            type="button"
            className={`news-filter${kind === filter.kind ? " is-active" : ""}`}
            aria-pressed={kind === filter.kind}
            onClick={() => {
              if (kind === filter.kind) return;
              setKind(filter.kind);
              void load(filter.kind, null);
            }}
          >
            {t(filter.label)}
          </button>
        ))}
      </div>

      {failed ? <p className="alert alert-error" role="alert">{t("news.loadError")}</p> : null}
      {!items.length && !loading && !failed ? <p className="news-empty">{t("news.empty")}</p> : null}

      <ol className="news-list" aria-busy={loading}>
        {items.map((item) => {
          const unread = !state.read[item.id];
          const internal = item.action.web_path;
          const external = externalLink(item, "feed");
          const label = item.action.label;
          return (
            <li key={item.id} className={`news-item${unread ? " is-unread" : ""}`} data-testid="news-item">
              {unread ? <span className="news-unread-dot" aria-label={t("news.unread")} role="img" /> : null}
              <AnnouncementPicture item={item} size={64} thumb />
              <div className="news-item-text">
                <div className="announcement-card-meta">
                  <span className="announcement-chip">{t(KIND_LABELS[item.kind])}</span>
                  <time dateTime={item.starts_at}>
                    {formatDate(item.starts_at, { day: "numeric", month: "long", year: "numeric" })}
                  </time>
                </div>
                <h2 className="news-item-title">{item.title}</h2>
                <p className="announcement-summary">{item.summary}</p>
              </div>
              <div className="news-item-actions">
                {internal && label ? (
                  <IntentPrefetchLink href={internal} className="btn btn-primary btn-sm" onClick={() => clickAnnouncement(item, "feed")}>
                    {label}
                  </IntentPrefetchLink>
                ) : null}
                {external && label ? (
                  <a href={external} target="_blank" rel="noopener noreferrer" className="btn btn-primary btn-sm" onClick={() => clickAnnouncement(item, "feed")}>
                    {label} ↗
                  </a>
                ) : null}
                {item.steps.length || item.body ? (
                  <button
                    type="button"
                    className="btn btn-secondary btn-sm"
                    onClick={() => {
                      readAnnouncement(item, "feed");
                      setOpened(item);
                    }}
                  >
                    {item.steps.length ? t("news.howTo") : t("news.more")}
                  </button>
                ) : null}
              </div>
            </li>
          );
        })}
      </ol>

      {page.next_cursor ? (
        <button type="button" className="btn btn-secondary news-more" disabled={loading} onClick={() => void load(kind, page.next_cursor)}>
          {t("news.loadMore")}
        </button>
      ) : null}

      {opened ? <AnnouncementDialog items={[opened]} surface="feed" onClose={() => setOpened(null)} /> : null}
    </div>
  );
}
