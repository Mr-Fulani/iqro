"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useAuth } from "../lib/auth-context";
import { useI18n } from "../lib/i18n-context";
import { LanguageSwitcher } from "./LanguageSwitcher";

export function Header() {
  const pathname = usePathname();
  const { session, logout, isLoading } = useAuth();
  const { t } = useI18n();
  const isActiveAccount = session?.user.status === "active";
  const isPendingDeletion = session?.user.status === "pending_deletion";

  const navItems = [
    { href: "/", label: t("nav.home"), icon: "🏠" },
    { href: "/quran", label: t("nav.quran"), icon: "📖" },
    { href: "/audio", label: t("nav.audio"), icon: "🎵" },
    { href: "/prayer", label: t("nav.prayer"), icon: "🕌" },
    { href: "/profile", label: t("nav.profile"), icon: "👤" },
  ];

  return (
    <header className="app-header">
      <div className="brand-block">
        <Link href="/" className="brand-link">
          <span className="brand-mark">Q</span>
          <div>
            <p className="eyebrow">Quran Platform</p>
            <h1 className="brand-title">{t("brand.subtitle")}</h1>
          </div>
        </Link>
      </div>

      <nav className="app-menu" aria-label={t("nav.aria")}>
        {navItems.map((item) => {
          const isActive = pathname === item.href || (item.href !== "/" && pathname.startsWith(item.href));
          return (
            <Link
              key={item.href}
              href={item.href}
              className={`menu-link ${isActive ? "menu-link-active" : ""}`}
            >
              <span className="menu-icon">{item.icon}</span>
              <span>{item.label}</span>
            </Link>
          );
        })}
      </nav>

      <div className="header-actions">
        <LanguageSwitcher />
        <div className={`status-chip ${isActiveAccount ? "ok" : "muted"}`}>
          <span className="status-dot"></span>
          {isPendingDeletion
            ? t("auth.deletionScheduled")
            : isActiveAccount
              ? t("auth.account")
              : t("auth.guest")}
        </div>

        {isActiveAccount || isPendingDeletion ? (
          <button
            onClick={() => void logout()}
            className="btn btn-secondary btn-sm"
            disabled={isLoading}
            title={t("auth.logoutTitle")}
          >
            {t("auth.logout")}
          </button>
        ) : (
          <Link
            href="/login"
            className="btn btn-primary btn-sm"
            aria-disabled={isLoading}
            title={t("auth.emailLoginTitle")}
          >
            {t("auth.emailLogin")}
          </Link>
        )}
      </div>
    </header>
  );
}
