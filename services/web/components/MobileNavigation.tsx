"use client";

import { IntentPrefetchLink } from "./IntentPrefetchLink";
import { usePathname } from "next/navigation";
import type { ReactNode } from "react";
import { useI18n } from "../lib/i18n-context";
import { localizedPath, stripLocalePrefix } from "../lib/routing";
import { LanguageSwitcher } from "./LanguageSwitcher";
import { forAudience, isFinished } from "../lib/announcements";
import { useAuth } from "../lib/auth-context";
import { useActiveAnnouncements, useAnnouncementState } from "./announcements/announcement-store";

type IconName = "home" | "quran" | "plan" | "audio" | "more" | "prayer" | "courses" | "dua" | "calendar" | "notes" | "profile" | "names" | "news";

function NavigationIcon({ name }: { name: IconName }) {
  const paths: Record<IconName, ReactNode> = {
    home: <><path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1Z" /></>,
    quran: <><path d="M12 5c-3-2-6-2-10-1v15c4-1 7-1 10 1 3-2 6-2 10-1V4c-4-1-7-1-10 1Zm0 0v15" /></>,
    plan: <><circle cx="12" cy="12" r="9" /><circle cx="12" cy="12" r="5" /><circle cx="12" cy="12" r="1" /></>,
    audio: <><path d="M3 14v-2a9 9 0 0 1 18 0v2M3 13h3v8H4a1 1 0 0 1-1-1Zm18 0h-3v8h2a1 1 0 0 0 1-1Z" /></>,
    more: <><rect x="3" y="3" width="7" height="7" rx="1" /><rect x="14" y="3" width="7" height="7" rx="1" /><rect x="3" y="14" width="7" height="7" rx="1" /><rect x="14" y="14" width="7" height="7" rx="1" /></>,
    prayer: <><path d="M20 15.2A9 9 0 0 1 8.8 4 9 9 0 1 0 20 15.2Z" /><path d="M17 3v4m-2-2h4" /></>,
    courses: <><path d="M5 4h11a3 3 0 0 1 3 3v14H8a3 3 0 0 1-3-3Z" /><path d="M5 18a3 3 0 0 1 3-3h11" /><path d="m10 7.5 4 2.5-4 2.5Z" /></>,
    dua: <><path d="m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5Z" /></>,
    calendar: <><rect x="3" y="5" width="18" height="16" rx="3" /><path d="M7 3v4m10-4v4M3 11h18m-14 5h3m4 0h3" /></>,
    notes: <><path d="M5 3h10l4 4v14H5Z" /><path d="M9 11h6M9 15h6" /></>,
    profile: <><circle cx="12" cy="8" r="4" /><path d="M4 21v-2a8 8 0 0 1 16 0v2" /></>,
    news: <><path d="M12 3l1.8 4.6L18 9.5l-4.2 1.9L12 16l-1.8-4.6L6 9.5l4.2-1.9z" /><path d="M19 15l.8 2 2 .8-2 .8-.8 2-.8-2-2-.8 2-.8z" /></>,
    names: <><rect x="5" y="5" width="14" height="14" rx="1" /><rect x="5" y="5" width="14" height="14" rx="1" transform="rotate(45 12 12)" /></>,
  };
  return <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{paths[name]}</svg>;
}

/** Mobile presentation of existing destinations; no application state lives here. */
export function MobileNavigation() {
  const pathname = usePathname();
  const route = stripLocalePrefix(pathname);
  const { locale, t } = useI18n();
  const { session } = useAuth();
  const announcementState = useAnnouncementState();
  const unreadNews = forAudience(useActiveAnnouncements(locale), session?.user.status === "active").some(
    (item) => !isFinished(item, announcementState),
  );
  const tabs = [
    { href: "/", label: t("nav.home"), icon: "home" },
    { href: "/quran", label: t("nav.quran"), icon: "quran" },
    { href: "/planner", label: t("nav.planner"), icon: "plan" },
    { href: "/audio", label: t("nav.audio"), icon: "audio" },
  ] as const;
  const more = [
    { href: "/news", label: t("news.title"), icon: "news" },
    { href: "/prayer", label: t("nav.prayer"), icon: "prayer" },
    // The prayer and tajweed courses open from the course catalog.
    { href: "/courses", label: t("nav.courses"), icon: "courses", also: ["/salah", "/tajweed"] },
    { href: "/calendar", label: t("calendar.title"), icon: "calendar" },
    { href: "/dua", label: t("nav.dua"), icon: "dua" },
    { href: "/memorization", label: t("nav.memorization"), icon: "plan" },
    { href: "/notes", label: t("notes.title"), icon: "notes" },
    { href: "/profile", label: t("nav.profile"), icon: "profile" },
  ] as const;
  const active = (href: string, also: readonly string[] = []) => [href, ...also].some((item) =>
    route === item || (item !== "/" && route.startsWith(`${item}/`)));

  return (
    <nav className="mobile-navigation" aria-label={t("nav.aria")}>
      {tabs.map((tab) => (
        <IntentPrefetchLink key={tab.href} href={localizedPath(locale, tab.href)} className="mobile-tab" aria-current={active(tab.href) ? "page" : undefined}>
          <span className="mobile-tab-icon"><NavigationIcon name={tab.icon} /></span>
          <span>{tab.label}</span>
        </IntentPrefetchLink>
      ))}
      <details key={pathname} className="mobile-more" onKeyDown={(event) => {
        if (event.key === "Escape") {
          event.currentTarget.open = false;
          event.currentTarget.querySelector("summary")?.focus();
        }
      }}>
        <summary className={`mobile-tab${more.some((item) => active(item.href, "also" in item ? item.also : [])) ? " is-active" : ""}`}>
          <span className="mobile-tab-icon">
            <NavigationIcon name="more" />
            {unreadNews ? <span className="mobile-tab-dot" aria-hidden="true" /> : null}
          </span>
          <span>{t("nav.more")}</span>
        </summary>
        <div className="mobile-more-panel">
          <span className="mobile-more-handle" aria-hidden="true" />
          <h2>{t("nav.more")}</h2>
          <div className="mobile-more-links">
            {more.map((item) => (
              <IntentPrefetchLink key={item.href} href={localizedPath(locale, item.href)} aria-current={active(item.href, "also" in item ? item.also : []) ? "page" : undefined}>
                <span className="mobile-more-icon"><NavigationIcon name={item.icon} /></span>
                <span>{item.label}</span>
                {item.href === "/news" && unreadNews ? (
                  <span className="mobile-more-new" role="img" aria-label={t("news.unread")} />
                ) : null}
                <span className="mobile-more-chevron" aria-hidden="true">›</span>
              </IntentPrefetchLink>
            ))}
            {/* Announced section without a page yet: shown, but not a link. */}
            <div className="mobile-more-soon" aria-disabled="true" data-testid="more-names-of-allah">
              <span className="mobile-more-icon"><NavigationIcon name="names" /></span>
              <span>{t("nav.namesOfAllah")}</span>
              <span className="status-chip mobile-more-soon-badge">{t("common.soon")}</span>
            </div>
          </div>
          <LanguageSwitcher variant="menu" />
        </div>
      </details>
    </nav>
  );
}
