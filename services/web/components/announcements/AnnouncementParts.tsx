"use client";

import type { ReactNode } from "react";
import { boldSegments, bodyBlocks, type Announcement } from "../../lib/announcements";
import type { MessageKey } from "../../lib/i18n";
import { useI18n } from "../../lib/i18n-context";
import { useHydrated } from "../../lib/use-hydrated";

const ICON_PATHS: Record<string, ReactNode> = {
  headphones: <path d="M3 18v-6a9 9 0 0 1 18 0v6M21 19a2 2 0 0 1-2 2h-1v-6h3zM3 19a2 2 0 0 0 2 2h1v-6H3z" />,
  sparkle: <><path d="M12 3l1.8 4.6L18 9.5l-4.2 1.9L12 16l-1.8-4.6L6 9.5l4.2-1.9z" /><path d="M19 15l.8 2 2 .8-2 .8-.8 2-.8-2-2-.8 2-.8z" /></>,
  arrow_up: <path d="M12 19V6M6 11l6-6 6 6" />,
  book: <><path d="M2 5h7a3 3 0 0 1 3 3v13a2 2 0 0 0-2-2H2z" /><path d="M22 5h-7a3 3 0 0 0-3 3v13a2 2 0 0 1 2-2h8z" /></>,
  megaphone: <><path d="M3 11v2a1 1 0 0 0 1 1h2l5 4V6L6 10H4a1 1 0 0 0-1 1z" /><path d="M15 9a4 4 0 0 1 0 6M18 6a8 8 0 0 1 0 12" /></>,
  compass: <><circle cx="12" cy="12" r="9" /><path d="M15.5 8.5l-2 5-5 2 2-5z" /></>,
  mosque: <><path d="M4 21V11h16v10" /><path d="M7 11a5 5 0 0 1 10 0" /><path d="M12 3.5V6M10 21v-4a2 2 0 0 1 4 0v4" /></>,
};

export function AnnouncementIcon({ name, size = 24 }: { name: string; size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      {ICON_PATHS[name] ?? ICON_PATHS.megaphone}
    </svg>
  );
}

/**
 * The publication date. The server renders in UTC, the visitor may already be
 * in the next day: the first paint uses UTC on both sides, then the local date.
 */
export function AnnouncementDate({ item, year = false }: { item: Announcement; year?: boolean }) {
  const { formatDate } = useI18n();
  const hydrated = useHydrated();
  const date = formatDate(item.starts_at, {
    day: "numeric",
    month: "long",
    ...(year ? { year: "numeric" as const } : {}),
    ...(hydrated ? {} : { timeZone: "UTC" }),
  });
  return <time dateTime={item.starts_at}>{date}</time>;
}

/** The portrait (or its 96 px thumbnail) when there is one, otherwise the kind's icon. */
export function AnnouncementPicture({
  item,
  size,
  thumb = false,
}: {
  item: Announcement;
  size: number;
  thumb?: boolean;
}) {
  const icon = item.bubble.icon === "portrait" ? "headphones" : item.bubble.icon;
  const source = item.image ? (thumb && item.image.thumb_url) || item.image.url : null;
  return (
    <span className="announcement-picture" style={{ width: size, height: size }} aria-hidden="true">
      {source ? (
        // eslint-disable-next-line @next/next/no-img-element -- CDN images with a server-made thumbnail.
        <img src={source} alt="" width={size} height={size} loading="lazy" decoding="async" />
      ) : (
        <AnnouncementIcon name={icon} size={Math.round(size * 0.5)} />
      )}
    </span>
  );
}

export const KIND_LABELS: Record<Announcement["kind"], MessageKey> = {
  reciter: "news.kind.reciter",
  feature: "news.kind.feature",
  app_release: "news.kind.app_release",
  content: "news.kind.content",
  fundraising: "news.kind.fundraising",
  general: "news.kind.general",
};

export function AnnouncementBody({ body }: { body: string }) {
  const blocks = bodyBlocks(body);
  if (!blocks.length) return null;
  const line = (text: string) =>
    boldSegments(text).map((part, index) =>
      part.bold ? <strong key={index}>{part.text}</strong> : <span key={index}>{part.text}</span>,
    );
  return (
    <div className="announcement-body">
      {blocks.map((block, index) =>
        block.type === "list" ? (
          <ul key={index}>{block.lines.map((item, row) => <li key={row}>{line(item)}</li>)}</ul>
        ) : (
          <p key={index}>
            {block.lines.map((item, row) => (
              <span key={row}>
                {row > 0 ? <br /> : null}
                {line(item)}
              </span>
            ))}
          </p>
        ),
      )}
    </div>
  );
}
