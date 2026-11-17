"use client";

import { IntentPrefetchLink } from "./IntentPrefetchLink";
import { usePathname } from "next/navigation";
import type { ReactNode } from "react";
import { useI18n } from "../lib/i18n-context";
import { localizedPath, stripLocalePrefix } from "../lib/routing";
import { forAudience, isFinished } from "../lib/announcements";
import { useAuth } from "../lib/auth-context";
import { useActiveAnnouncements, useAnnouncementState } from "./announcements/announcement-store";

type IconName = "home" | "quran" | "plan" | "audio" | "more";

function NavigationIcon({ name }: { name: IconName }) {
  const paths: Record<IconName, ReactNode> = {
    home: <><path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1Z" /></>,
    quran: <><path d="M12 5c-3-2-6-2-10-1v15c4-1 7-1 10 1 3-2 6-2 10-1V4c-4-1-7-1-10 1Zm0 0v15" /></>,
    plan: <><circle cx="12" cy="12" r="9" /><circle cx="12" cy="12" r="5" /><circle cx="12" cy="12" r="1" /></>,
    audio: <><path d="M3 14v-2a9 9 0 0 1 18 0v2M3 13h3v8H4a1 1 0 0 1-1-1Zm18 0h-3v8h2a1 1 0 0 0 1-1Z" /></>,
    more: <><rect x="3" y="3" width="7" height="7" rx="1" /><rect x="14" y="3" width="7" height="7" rx="1" /><rect x="3" y="14" width="7" height="7" rx="1" /><rect x="14" y="14" width="7" height="7" rx="1" /></>,
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
  // Everything reached from the More screen keeps its tab lit.
  const moreRoutes = ["/more", "/settings", "/news", "/prayer", "/courses", "/salah", "/tajweed", "/calendar", "/dua", "/names", "/memorization", "/notes", "/profile"];
  const active = (href: string) => route === href || (href !== "/" && route.startsWith(`${href}/`));
  const moreActive = moreRoutes.some(active);

  return (
    <nav className="mobile-navigation" aria-label={t("nav.aria")}>
      {tabs.map((tab) => (
        <IntentPrefetchLink key={tab.href} href={localizedPath(locale, tab.href)} className="mobile-tab" aria-current={active(tab.href) ? "page" : undefined}>
          <span className="mobile-tab-icon"><NavigationIcon name={tab.icon} /></span>
          <span>{tab.label}</span>
        </IntentPrefetchLink>
      ))}
      {/* More is a screen of its own (/more), as in the app. */}
      <IntentPrefetchLink
        href={localizedPath(locale, "/more")}
        className="mobile-tab"
        aria-current={moreActive ? "page" : undefined}
        // The screen is not indexed; this also keeps the tab's short name out of link audits.
        rel="nofollow"
        data-testid="mobile-more-tab"
      >
        <span className="mobile-tab-icon">
          <NavigationIcon name="more" />
          {unreadNews ? <span className="mobile-tab-dot" aria-hidden="true" /> : null}
        </span>
        <span>{t("nav.more")}</span>
      </IntentPrefetchLink>
    </nav>
  );
}
