"use client";

import type { ButtonHTMLAttributes, ReactNode } from "react";
import { Icon } from "./icons";
import { l, ui } from "./i18n";
import { reciters } from "./data";
import { usePrototype } from "./store";
import type { Route } from "./types";

export function BrandMark() {
  return (
    <span className="brand-mark" aria-label="IQRO">
      <span className="brand-glyph" aria-hidden="true">اق</span>
      <span>IQRO</span>
    </span>
  );
}

export function IconButton({ label, children, className = "", ...props }: ButtonHTMLAttributes<HTMLButtonElement> & { label: string; children: ReactNode }) {
  return <button className={`icon-button ${className}`} aria-label={label} title={label} {...props}>{children}</button>;
}

export function TopBar({ title, subtitle, back, action }: { title: string; subtitle?: string; back?: boolean; action?: ReactNode }) {
  const { goBack } = usePrototype();
  return (
    <header className="top-bar">
      <div className="top-bar-side">
        {back ? <IconButton label="Back" onClick={goBack}><Icon name="arrow" /></IconButton> : <BrandMark />}
      </div>
      <div className="top-bar-title">
        <strong>{title}</strong>
        {subtitle ? <span>{subtitle}</span> : null}
      </div>
      <div className="top-bar-side is-end">{action}</div>
    </header>
  );
}

export function ProgressBar({ value, max = 100, label }: { value: number; max?: number; label?: string }) {
  const percent = Math.min(100, Math.max(0, (value / Math.max(max, 1)) * 100));
  return (
    <div className="progress-wrap" aria-label={label} role="progressbar" aria-valuemin={0} aria-valuemax={max} aria-valuenow={value}>
      <span className="progress-track"><span className="progress-fill" style={{ width: `${percent}%` }} /></span>
    </div>
  );
}

export function Toggle({ checked, onChange, label, disabled = false }: { checked: boolean; onChange: () => void; label: string; disabled?: boolean }) {
  return (
    <button type="button" className={`toggle ${checked ? "is-on" : ""}`} role="switch" aria-checked={checked} aria-label={label} onClick={onChange} disabled={disabled}>
      <span />
    </button>
  );
}

const navItems: Array<{ route: Route; icon: "home" | "book" | "target" | "headphones" | "grid"; key: keyof typeof ui.nav }> = [
  { route: "home", icon: "home", key: "home" },
  { route: "quran", icon: "book", key: "quran" },
  { route: "plan", icon: "target", key: "plan" },
  { route: "audio", icon: "headphones", key: "audio" },
  { route: "more", icon: "grid", key: "more" },
];

export function BottomNav() {
  const { state, navigate } = usePrototype();
  const activeRoot = state.route === "reader" || state.route === "mushaf" ? "quran" : state.route === "prayer-reading" ? "plan" : state.route;
  return (
    <nav className="bottom-nav" aria-label="Primary navigation">
      {navItems.map((item) => (
        <button key={item.route} className={activeRoot === item.route ? "is-active" : ""} onClick={() => navigate(item.route)}>
          <Icon name={item.icon} filled={activeRoot === item.route} />
          <span>{l(state.locale, ui.nav[item.key])}</span>
        </button>
      ))}
    </nav>
  );
}

export function MiniPlayer() {
  const { state, setState, navigate } = usePrototype();
  if (!state.player.active || state.route === "player") return null;
  const reciter = reciters.find((item) => item.id === state.player.reciterId) || reciters[0];
  return (
    <section className="mini-player" aria-label="Now playing" onClick={() => navigate("player")}>
      <button className="mini-cover" aria-label="Open full player"><span>{reciter.initials}</span></button>
      <button className="mini-copy" aria-label="Open full player">
        <strong>{state.locale === "ar" ? "الفاتحة" : state.locale === "ru" ? "Аль-Фатиха" : "Al-Faatiha"} · {state.player.ayah}</strong>
        <span>{reciter[state.locale]}</span>
      </button>
      <IconButton label={state.player.playing ? "Pause" : "Play"} onClick={(event) => {
        event.stopPropagation();
        setState((current) => ({ ...current, player: { ...current.player, playing: !current.player.playing } }));
      }}>
        <Icon name={state.player.playing ? "pause" : "play"} filled />
      </IconButton>
    </section>
  );
}

export function StatusLayer() {
  const { state, setState } = usePrototype();
  if (state.systemState === "online") return null;
  const content = {
    loading: ["Обновляем данные", "Сохранённый контент остаётся доступен."],
    offline: ["Вы не в сети", "Изменения сохранятся на устройстве и отправятся в аккаунт позже."],
    "api-error": ["Не удалось обновить данные", "Показываем последнюю сохранённую версию."],
    "sync-conflict": ["Есть более свежие изменения", "Мы сохранили обе версии. Выберите актуальную в аккаунте."],
    "notifications-denied": ["Уведомления выключены", "Разрешите их в настройках устройства, когда будете готовы."],
    "geolocation-denied": ["Геолокация недоступна", "Выберите город вручную — координаты не сохраняются в профиле."],
    "no-audio": ["Аудио недоступно", "Попробуйте другого чтеца или повторите позже."],
    "offline-unavailable": ["Нет офлайн-копии", "Этот материал доступен только при подключении к сети."],
    "session-expired": ["Сессия завершилась", "Войдите снова; данные на устройстве не потеряны."],
  }[state.systemState];
  return (
    <div className="system-banner" role="status">
      <Icon name={state.systemState === "offline" ? "wifiOff" : "info"} />
      <span><strong>{content[0]}</strong><small>{content[1]}</small></span>
      <IconButton label="Close" onClick={() => setState((current) => ({ ...current, systemState: "online" }))}><Icon name="close" size={18} /></IconButton>
    </div>
  );
}

export function Toast() {
  const { state } = usePrototype();
  return state.toast ? <div className="toast" role="status"><Icon name="check" size={18} />{state.toast}</div> : null;
}

export function Screen({ children, className = "", nav = true }: { children: ReactNode; className?: string; nav?: boolean }) {
  return (
    <div className={`screen ${nav ? "has-nav" : ""} ${className}`}>
      <StatusLayer />
      <main className="screen-content">{children}</main>
      {nav ? <><MiniPlayer /><BottomNav /></> : null}
      <Toast />
    </div>
  );
}
