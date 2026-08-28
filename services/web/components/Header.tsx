"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useAuth } from "../lib/auth-context";
import { useI18n } from "../lib/i18n-context";
import { LanguageSwitcher } from "./LanguageSwitcher";
import { localizedPath, stripLocalePrefix } from "../lib/routing";

export function Header() {
  const pathname = usePathname();
  const { session, logout, isLoading } = useAuth();
  const { locale, t } = useI18n();
  const routePathname = stripLocalePrefix(pathname);
  const isActiveAccount = session?.user.status === "active";
  const isPendingDeletion = session?.user.status === "pending_deletion";
  const statusClassName = isPendingDeletion
    ? "muted"
    : isActiveAccount
      ? "ok"
      : "guest-online";

  const navItems = [
    { href: "/quran", label: t("nav.quran"), icon: "📖" },
    { href: "/planner", label: t("nav.planner"), icon: "🗓️" },
    { href: "/dua", label: t("nav.dua"), icon: "🤲" },
    { href: "/audio", label: t("nav.audio"), icon: "🎵" },
    { href: "/prayer", label: t("nav.prayer"), icon: "🕌" },
    { href: "/profile", label: t("nav.profile"), icon: "👤" },
  ];

  return (
    <header className="app-header">
      <div className="brand-block">
        <Link href={localizedPath(locale, "/")} className="brand-link">
          <span className="brand-mark">Q</span>
          <div>
            <p className="eyebrow">IQRO</p>
            <p className="brand-title">{t("brand.subtitle")}</p>
          </div>
        </Link>
      </div>

      <nav className="app-menu" aria-label={t("nav.aria")}>
        {navItems.map((item) => {
          const isActive = routePathname === item.href
            || (item.href !== "/" && routePathname.startsWith(item.href));
          return (
            <Link
              key={item.href}
              href={localizedPath(locale, item.href)}
              className={`menu-link ${isActive ? "menu-link-active" : ""}`}
              aria-label={item.label}
              title={item.label}
            >
              <span className="menu-icon">{item.icon}</span>
              <span className="menu-label">{item.label}</span>
            </Link>
          );
        })}
      </nav>

      <div className="header-actions">
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
    </header>
  );
}
