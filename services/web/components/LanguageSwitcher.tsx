"use client";

import { ChangeEvent } from "react";
import { useI18n } from "../lib/i18n-context";
import { Locale, SUPPORTED_LOCALES } from "../lib/i18n";

export function LanguageSwitcher() {
  const { locale, setLocale, t } = useI18n();

  const handleChange = (event: ChangeEvent<HTMLSelectElement>) => {
    setLocale(event.target.value as Locale);
  };

  return (
    <label className="language-switcher" title={t("language.label")}>
      <span aria-hidden="true">🌐</span>
      <span className="sr-only">{t("language.label")}</span>
      <select
        aria-label={t("language.label")}
        value={locale}
        onChange={handleChange}
        data-testid="language-switcher"
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
