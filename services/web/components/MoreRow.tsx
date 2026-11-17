"use client";

import type { ReactNode } from "react";
import { useI18n } from "../lib/i18n-context";
import { localizedPath } from "../lib/routing";
import { IntentPrefetchLink } from "./IntentPrefetchLink";

const ICONS = {
  profile: <><circle cx="12" cy="8" r="4" /><path d="M4 21v-2a8 8 0 0 1 16 0v2" /></>,
  share: <><path d="M12 15V3m0 0L8 7m4-4 4 4" /><path d="M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7" /></>,
  settings: <><circle cx="12" cy="12" r="3" /><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.9 2.9l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.9-2.9l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.9-2.9l.1.1a1.7 1.7 0 0 0 1.8.3h.1a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.9 2.9l-.1.1a1.7 1.7 0 0 0-.3 1.8v.1a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1Z" /></>,
  privacy: <><path d="M12 3 5 6v5c0 4.5 2.9 8.3 7 10 4.1-1.7 7-5.5 7-10V6Z" /><path d="M12 10v4m0-7v.5" /></>,
  cookies: <><circle cx="12" cy="12" r="9" /><path d="M9 9h.01M15 11h.01M10 15h.01M14.5 15.5h.01" /></>,
  sources: <><path d="M6 3h9l4 4v14H6Z" /><path d="M9 11h7M9 15h7M9 7h3" /></>,
} as const;

/** One row of a card on the phone's More and Settings screens, like the app's list tile. */
export function MoreRow({
  href,
  icon,
  title,
  subtitle,
  trailing,
  testId,
}: {
  href: string;
  icon: keyof typeof ICONS | ReactNode;
  title: string;
  subtitle?: string;
  trailing?: ReactNode;
  testId?: string;
}) {
  const { locale } = useI18n();
  return (
    <IntentPrefetchLink href={localizedPath(locale, href)} className="more-row" data-testid={testId}>
      <span className="more-row-icon" aria-hidden="true">
        {typeof icon === "string" && icon in ICONS ? (
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
            {ICONS[icon as keyof typeof ICONS]}
          </svg>
        ) : icon}
      </span>
      <span className="more-row-copy">
        <strong>{title}</strong>
        {subtitle && <small>{subtitle}</small>}
      </span>
      {trailing}
      <span className="more-row-chevron" aria-hidden="true">›</span>
    </IntentPrefetchLink>
  );
}
