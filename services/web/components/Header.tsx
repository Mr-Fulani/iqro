"use client";

import { IntentPrefetchLink } from "./IntentPrefetchLink";
import Image from "next/image";
import { usePathname, useRouter } from "next/navigation";
import { useAuth } from "../lib/auth-context";
import { useI18n } from "../lib/i18n-context";
import { LanguageSwitcher } from "./LanguageSwitcher";
import { localizedPath, stripLocalePrefix } from "../lib/routing";
import { useHydrated } from "../lib/use-hydrated";
import { homeDateLine } from "../lib/home-date";
import { forAudience, isFinished } from "../lib/announcements";
import { AnnouncementIcon } from "./announcements/AnnouncementParts";
import { useActiveAnnouncements, useAnnouncementState } from "./announcements/announcement-store";

export function Header() {
  const pathname = usePathname();
  const { session, logout, isLoading } = useAuth();
  const { locale, t } = useI18n();
  const routePathname = stripLocalePrefix(pathname);
  const isHome = routePathname === "/";
  // On a phone every screen except the five tabs has a way back, as in the app.
  const router = useRouter();
  const isTab = ["/", "/surahs", "/planner", "/audio", "/more"].includes(routePathname);
  const goBack = () => {
    if (window.history.length > 1) router.back();
    else router.push(localizedPath(locale, "/more"));
  };
  // Today's date in the phone's home top bar, as in the app. It follows the
  // visitor's clock, so it is drawn after hydration.
  const hydrated = useHydrated();
  const homeDate = isHome && hydrated ? homeDateLine(locale, t("home.hijriMonths").split("|"), t("home.hijriSuffix")) : "";
  const isActiveAccount = session?.user.status === "active";
  const isPendingDeletion = session?.user.status === "pending_deletion";
  const announcementState = useAnnouncementState();
  const unread = forAudience(useActiveAnnouncements(locale), isActiveAccount).filter(
    (item) => !isFinished(item, announcementState),
  ).length;
  const statusClassName = isPendingDeletion
    ? "muted"
    : isActiveAccount
      ? "ok"
      : "guest-online";

  const navItems: { href: string; label: string; icon: string; also?: string[] }[] = [
    { href: "/quran", label: t("nav.quran"), icon: "📖" },
    { href: "/memorization", label: t("nav.memorization"), icon: "🧠" },
    { href: "/planner", label: t("nav.planner"), icon: "🗓️" },
    { href: "/dua", label: t("nav.dua"), icon: "🤲" },
    { href: "/audio", label: t("nav.audio"), icon: "🎵" },
    { href: "/prayer", label: t("nav.prayer"), icon: "🕌" },
    // One entry for every course: the prayer and tajweed courses open from its catalog.
    { href: "/courses", label: t("nav.courses"), icon: "📚", also: ["/salah", "/tajweed"] },
    { href: "/calendar", label: t("calendar.title"), icon: "☾" },
    { href: "/names", label: t("nav.namesOfAllah"), icon: "۞" },
    { href: "/profile", label: t("nav.profile"), icon: "👤" },
  ];

  return (
    <header className={isHome ? "app-header is-home" : "app-header"}>
      <div className="brand-block">
        {!isTab && (
          <button type="button" className="header-back" onClick={goBack} aria-label={t("more.back")} data-testid="header-back">
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
              <path d="M19 12H5m6-6-6 6 6 6" />
            </svg>
          </button>
        )}
        <IntentPrefetchLink href={localizedPath(locale, "/")} className="brand-link">
          <Image src="/iqro-wax-seal-128.webp" alt="" width={56} height={56} className="brand-logo" preload unoptimized />
          <div>
            <p className="eyebrow">IQRO</p>
            <p className="brand-title">{t("brand.subtitle")}</p>
            {isHome && <p className="brand-date" data-testid="home-date">{homeDate}</p>}
          </div>
        </IntentPrefetchLink>
      </div>

      <nav className="app-menu" aria-label={t("nav.aria")}>
        {navItems.map((item) => {
          const isActive = [item.href, ...(item.also ?? [])].some((href) =>
            routePathname === href || (href !== "/" && routePathname.startsWith(href)));
          return (
            <IntentPrefetchLink
              key={item.href}
              href={localizedPath(locale, item.href)}
              className={`menu-link ${isActive ? "menu-link-active" : ""}`}
              aria-label={item.label}
              title={item.label}
            >
              <span className="menu-icon">{item.icon}</span>
              <span className="menu-label">{item.label}</span>
            </IntentPrefetchLink>
          );
        })}
      </nav>

      <div className="header-actions">
        <IntentPrefetchLink
          href={localizedPath(locale, "/news")}
          className={`news-link${routePathname === "/news" ? " is-active" : ""}`}
          aria-label={unread ? t("news.unreadLink", { count: unread }) : t("news.title")}
          data-testid="header-news-link"
        >
          <AnnouncementIcon name="sparkle" size={16} />
          <span>{t("news.title")}</span>
          {unread ? <span className="news-link-count" aria-hidden="true">{unread}</span> : null}
        </IntentPrefetchLink>
        <LanguageSwitcher />
        <div className={`status-chip ${statusClassName}`}>
          <span className="status-dot" aria-hidden="true"></span>
          {isPendingDeletion
            ? t("auth.deletionScheduled")
            : isActiveAccount
              ? t("auth.account")
              : t("auth.guest")}
        </div>


        {(isActiveAccount || isPendingDeletion) && (
          <button
            onClick={() => void logout()}
            className="btn btn-secondary btn-sm"
            disabled={isLoading}
            title={t("auth.logoutTitle")}
          >
            {t("auth.logout")}
          </button>
        )}
      </div>

      {isHome && (
        <IntentPrefetchLink
          href={localizedPath(locale, "/settings")}
          className="header-settings"
          aria-label={t("home.settings")}
          data-testid="home-settings"
        >
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <circle cx="12" cy="12" r="3" />
            <path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.9 2.9l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.9-2.9l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.9-2.9l.1.1a1.7 1.7 0 0 0 1.8.3h.1a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.9 2.9l-.1.1a1.7 1.7 0 0 0-.3 1.8v.1a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1Z" />
          </svg>
        </IntentPrefetchLink>
      )}
    </header>
  );
}
