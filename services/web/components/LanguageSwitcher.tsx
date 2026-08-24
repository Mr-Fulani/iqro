"use client";

import { ChangeEvent } from "react";
import { useRouter } from "next/navigation";
import { useI18n } from "../lib/i18n-context";
import { Locale, SUPPORTED_LOCALES } from "../lib/i18n";
import { localizedPath } from "../lib/routing";

export function LanguageSwitcher() {
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
