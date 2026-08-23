"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useAuth } from "../lib/auth-context";

export function Header() {
  const pathname = usePathname();
  const { session, logout, isLoading } = useAuth();
  const isActiveAccount = session?.user.status === "active";

  const navItems = [
    { href: "/", label: "Главная", icon: "🏠" },
    { href: "/quran", label: "Коран", icon: "📖" },
    { href: "/audio", label: "Аудио", icon: "🎵" },
    { href: "/prayer", label: "Намаз", icon: "🕌" },
    { href: "/profile", label: "Кабинет", icon: "👤" },
  ];

  return (
    <header className="app-header">
      <div className="brand-block">
        <Link href="/" className="brand-link">
          <span className="brand-mark">Q</span>
          <div>
            <p className="eyebrow">Quran Platform</p>
            <h1 className="brand-title">Исламская платформа</h1>
          </div>
        </Link>
      </div>

      <nav className="app-menu" aria-label="Навигация по приложению">
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
        <div className={`status-chip ${isActiveAccount ? "ok" : "muted"}`}>
          <span className="status-dot"></span>
          {isActiveAccount ? "Аккаунт" : "Гостевой режим"}
        </div>

        {isActiveAccount ? (
          <button
            onClick={() => void logout()}
            className="btn btn-secondary btn-sm"
            disabled={isLoading}
            title="Выйти из аккаунта"
          >
            Выйти
          </button>
        ) : (
          <Link
            href="/login"
            className="btn btn-primary btn-sm"
            aria-disabled={isLoading}
            title="Войти по одноразовому коду из email"
          >
            Войти по email
          </Link>
        )}
      </div>
    </header>
  );
}
