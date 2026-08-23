"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useAuth } from "../lib/auth-context";

export function Header() {
  const pathname = usePathname();
  const { isLoggedIn, loginGuest, logout, isLoading } = useAuth();

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
        <div className={`status-chip ${isLoggedIn ? "ok" : "muted"}`}>
          <span className="status-dot"></span>
          {isLoggedIn ? "Авторизован" : "Гость"}
        </div>

        {isLoggedIn ? (
          <button
            onClick={() => void logout()}
            className="btn btn-secondary btn-sm"
            disabled={isLoading}
            title="Выйти из аккаунта"
          >
            Выйти
          </button>
        ) : (
          <button
            onClick={() => void loginGuest()}
            className="btn btn-primary btn-sm"
            disabled={isLoading}
            title="Быстрый вход как гость"
          >
            {isLoading ? "Вход..." : "Войти как гость"}
          </button>
        )}
      </div>
    </header>
  );
}
