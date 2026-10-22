"use client";

import { IntentPrefetchLink } from "./IntentPrefetchLink";
import Image from "next/image";
import { usePathname } from "next/navigation";
import { useAuth } from "../lib/auth-context";
import { useI18n } from "../lib/i18n-context";
import { LanguageSwitcher } from "./LanguageSwitcher";
import { localizedPath, stripLocalePrefix } from "../lib/routing";
import { forAudience, isFinished } from "../lib/announcements";
import { AnnouncementBubble } from "./announcements/AnnouncementBubble";
import { AnnouncementIcon } from "./announcements/AnnouncementParts";
import { useActiveAnnouncements, useAnnouncementState } from "./announcements/announcement-store";

export function Header() {
  const pathname = usePathname();
  const { session, logout, isLoading } = useAuth();
  const { locale, t } = useI18n();
  const routePathname = stripLocalePrefix(pathname);
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

  const navItems = [
    { href: "/quran", label: t("nav.quran"), icon: "📖" },
    { href: "/memorization", label: t("nav.memorization"), icon: "🧠" },
    { href: "/planner", label: t("nav.planner"), icon: "🗓️" },
    { href: "/dua", label: t("nav.dua"), icon: "🤲" },
    { href: "/audio", label: t("nav.audio"), icon: "🎵" },
    { href: "/prayer", label: t("nav.prayer"), icon: "🕌" },
    { href: "/salah", label: t("nav.salah"), icon: "🧎" },
    { href: "/tajweed", label: t("nav.tajweed"), icon: "🎙️" },
    { href: "/calendar", label: t("calendar.title"), icon: "☾" },
    { href: "/profile", label: t("nav.profile"), icon: "👤" },
  ];

  return (
    <header className="app-header">
      <div className="brand-block">
        <IntentPrefetchLink href={localizedPath(locale, "/")} className="brand-link">
          <Image src="/iqro-wax-seal-128.webp" alt="" width={56} height={56} className="brand-logo" preload unoptimized />
          <div>
            <p className="eyebrow">IQRO</p>
            <p className="brand-title">{t("brand.subtitle")}</p>
          </div>
        </IntentPrefetchLink>
      </div>

      <nav className="app-menu" aria-label={t("nav.aria")}>
        {navItems.map((item) => {
          const isActive = routePathname === item.href
            || (item.href !== "/" && routePathname.startsWith(item.href));
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
        {/* Announced section without a page yet: shown, but not a link. A full
            label does not fit the one-row menu, so the name is in the tooltip. */}
        <span
          className="menu-link menu-link-soon"
          aria-disabled="true"
          title={`${t("nav.namesOfAllah")} — ${t("common.soon")}`}
          data-testid="menu-names-of-allah"
        >
          <span className="menu-icon" aria-hidden="true">۞</span>
          <span className="sr-only">{`${t("nav.namesOfAllah")} — ${t("common.soon")}`}</span>
        </span>
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

        {routePathname === "/" ? <AnnouncementBubble /> : null}

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
    </header>
  );
}
