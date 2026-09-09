"use client";

import { ChangeEvent } from "react";
import { useRouter } from "next/navigation";
import { useI18n } from "../lib/i18n-context";
import { Locale, SUPPORTED_LOCALES } from "../lib/i18n";
import { localizedPath } from "../lib/routing";

export function LanguageSwitcher({ variant = "header" }: { variant?: "header" | "menu" }) {
  const router = useRouter();
  const { locale, setLocale, t } = useI18n();

  const handleChange = (event: ChangeEvent<HTMLSelectElement>) => {
    const nextLocale = event.target.value as Locale;
    setLocale(nextLocale);
    router.push(localizedPath(
      nextLocale,
      `${window.location.pathname}${window.location.search}${window.location.hash}`,
    ));
  };

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
        value={locale}
        onChange={handleChange}
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
