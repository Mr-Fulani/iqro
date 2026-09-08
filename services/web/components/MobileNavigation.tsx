"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import type { ReactNode } from "react";
import { useI18n } from "../lib/i18n-context";
import { localizedPath, stripLocalePrefix } from "../lib/routing";

type IconName = "home" | "quran" | "plan" | "audio" | "more" | "prayer" | "dua" | "calendar" | "profile";

function NavigationIcon({ name }: { name: IconName }) {
  const paths: Record<IconName, ReactNode> = {
    home: <><path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1Z" /></>,
    quran: <><path d="M12 5c-3-2-6-2-10-1v15c4-1 7-1 10 1 3-2 6-2 10-1V4c-4-1-7-1-10 1Zm0 0v15" /></>,
    plan: <><circle cx="12" cy="12" r="9" /><circle cx="12" cy="12" r="5" /><circle cx="12" cy="12" r="1" /></>,
    audio: <><path d="M3 14v-2a9 9 0 0 1 18 0v2M3 13h3v8H4a1 1 0 0 1-1-1Zm18 0h-3v8h2a1 1 0 0 0 1-1Z" /></>,
    more: <><rect x="3" y="3" width="7" height="7" rx="1" /><rect x="14" y="3" width="7" height="7" rx="1" /><rect x="3" y="14" width="7" height="7" rx="1" /><rect x="14" y="14" width="7" height="7" rx="1" /></>,
    prayer: <><path d="M20 15.2A9 9 0 0 1 8.8 4 9 9 0 1 0 20 15.2Z" /><path d="M17 3v4m-2-2h4" /></>,
    dua: <><path d="m12 3 2.5 6.5L21 12l-6.5 2.5L12 21l-2.5-6.5L3 12l6.5-2.5Z" /></>,
    calendar: <><rect x="3" y="5" width="18" height="16" rx="3" /><path d="M7 3v4m10-4v4M3 11h18m-14 5h3m4 0h3" /></>,
    profile: <><circle cx="12" cy="8" r="4" /><path d="M4 21v-2a8 8 0 0 1 16 0v2" /></>,
  };
  return <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{paths[name]}</svg>;
}

/** Mobile presentation of existing destinations; no application state lives here. */
export function MobileNavigation() {
  const pathname = usePathname();
  const route = stripLocalePrefix(pathname);
  const { locale, t } = useI18n();
  const tabs = [
    { href: "/", label: t("nav.home"), icon: "home" },
    { href: "/quran", label: t("nav.quran"), icon: "quran" },
    { href: "/planner", label: t("nav.planner"), icon: "plan" },
    { href: "/audio", label: t("nav.audio"), icon: "audio" },
  ] as const;
  const more = [
    { href: "/prayer", label: t("nav.prayer"), icon: "prayer" },
    { href: "/calendar", label: t("calendar.title"), icon: "calendar" },
    { href: "/dua", label: t("nav.dua"), icon: "dua" },
    { href: "/memorization", label: t("nav.memorization"), icon: "plan" },
    { href: "/profile", label: t("nav.profile"), icon: "profile" },
  ] as const;
  const active = (href: string) => route === href || (href !== "/" && route.startsWith(`${href}/`));

  return (
    <nav className="mobile-navigation" aria-label={t("nav.aria")}>
      {tabs.map((tab) => (
        <Link key={tab.href} href={localizedPath(locale, tab.href)} className="mobile-tab" aria-current={active(tab.href) ? "page" : undefined}>
          <span className="mobile-tab-icon"><NavigationIcon name={tab.icon} /></span>
          <span>{tab.label}</span>
        </Link>
      ))}
      <details key={pathname} className="mobile-more" onKeyDown={(event) => {
        if (event.key === "Escape") {
          event.currentTarget.open = false;
          event.currentTarget.querySelector("summary")?.focus();
        }
      }}>
        <summary className={`mobile-tab${more.some((item) => active(item.href)) ? " is-active" : ""}`}>
          <span className="mobile-tab-icon"><NavigationIcon name="more" /></span>
          <span>{t("nav.more")}</span>
        </summary>
        <div className="mobile-more-panel">
          <span className="mobile-more-handle" aria-hidden="true" />
          <h2>{t("nav.more")}</h2>
          <div className="mobile-more-links">
            {more.map((item) => (
              <Link key={item.href} href={localizedPath(locale, item.href)} aria-current={active(item.href) ? "page" : undefined}>
                <span className="mobile-more-icon"><NavigationIcon name={item.icon} /></span>
                <span>{item.label}</span>
                <span className="mobile-more-chevron" aria-hidden="true">›</span>
              </Link>
            ))}
          </div>
        </div>
      </details>
    </nav>
  );
}
