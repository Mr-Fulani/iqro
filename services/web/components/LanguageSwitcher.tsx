"use client";

import { useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import { useI18n } from "../lib/i18n-context";
import { Locale, SUPPORTED_LOCALES } from "../lib/i18n";
import { localizedPath } from "../lib/routing";

export function LanguageSwitcher({ variant = "header" }: { variant?: "header" | "menu" }) {
  const router = useRouter();
  const { locale, setLocale, t } = useI18n();

  const select = useRef<HTMLSelectElement>(null);
  const asked = useRef(locale);

  const change = (nextLocale: Locale) => {
    if (nextLocale === asked.current) return;
    asked.current = nextLocale;
    setLocale(nextLocale);
    router.push(localizedPath(
      nextLocale,
      `${window.location.pathname}${window.location.search}${window.location.hash}`,
    ));
  };

  useEffect(() => {
    asked.current = locale;
  }, [locale]);

  // A language picked before the page came alive was not heard: the list holds it.
  useEffect(() => {
    const picked = select.current?.value as Locale | undefined;
    if (picked) change(picked);
    // Only what the list held when the page came alive.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <label className={`language-switcher${variant === "menu" ? " language-switcher-menu" : ""}`} title={t("language.label")}>
      <span className={variant === "menu" ? "mobile-more-icon" : undefined} aria-hidden="true">
        {variant === "menu" ? (
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
            <circle cx="12" cy="12" r="9" />
            <ellipse cx="12" cy="12" rx="4" ry="9" />
            <path d="M3 12h18" />
          </svg>
        ) : "🌐"}
      </span>
      <span className={variant === "menu" ? "language-switcher-label" : "sr-only"}>{t("language.label")}</span>
      <select
        aria-label={t("language.label")}
        // The list is the visitor's: with `value` every drawing of the page would put the
        // page's language back, also between a pick and its `change` event, and the pick
        // made while the page is still coming alive would be lost.
        key={locale}
        ref={select}
        defaultValue={locale}
        onChange={(event) => change(event.target.value as Locale)}
        // The browser does not put back an earlier pick on reload: only the visitor's own counts.
        autoComplete="off"
        data-testid={variant === "menu" ? "mobile-language-switcher" : "language-switcher"}
      >
        {SUPPORTED_LOCALES.map((item) => (
          <option key={item} value={item} lang={item} dir={item === "ar" ? "rtl" : "ltr"}>
            {item === "ru"
              ? "Русский"
              : item === "en"
                ? "English"
                : item === "ar"
                  ? "العربية"
                  : "Türkçe"}
          </option>
        ))}
      </select>
    </label>
  );
}
