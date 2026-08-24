"use client";

import { createContext, ReactNode, useCallback, useContext, useEffect, useMemo, useState } from "react";
import { api } from "./api";
import {
  directionFor,
  LOCALE_COOKIE_NAME,
  localeTag,
  Locale,
  MessageKey,
  translate,
  TranslationVariables,
} from "./i18n";

type I18nContextValue = {
  locale: Locale;
  direction: "ltr" | "rtl";
  setLocale: (locale: Locale) => void;
  t: (key: MessageKey, variables?: TranslationVariables) => string;
  formatDate: (value: string | number | Date, options?: Intl.DateTimeFormatOptions) => string;
  formatNumber: (value: number, options?: Intl.NumberFormatOptions) => string;
};

const I18nContext = createContext<I18nContextValue | undefined>(undefined);

export function I18nProvider({ initialLocale, children }: { initialLocale: Locale; children: ReactNode }) {
  const [locale, setLocaleState] = useState<Locale>(initialLocale);
  const direction = directionFor(locale);

  useEffect(() => {
    api.setLocale(locale);
    document.documentElement.lang = locale;
    document.documentElement.dir = direction;
  }, [direction, locale]);

  const setLocale = useCallback((nextLocale: Locale) => {
    setLocaleState(nextLocale);
    document.cookie = `${LOCALE_COOKIE_NAME}=${nextLocale}; Path=/; Max-Age=31536000; SameSite=Lax`;
    api.setLocale(nextLocale);
    void api.updateSessionLocale(nextLocale).catch(() => {
      // Browser preference remains authoritative when the visitor has no active session.
    });
  }, []);

  const value = useMemo<I18nContextValue>(() => ({
    locale,
    direction,
    setLocale,
    t: (key, variables) => translate(locale, key, variables),
    formatDate: (input, options) => new Intl.DateTimeFormat(localeTag(locale), options).format(new Date(input)),
    formatNumber: (input, options) => new Intl.NumberFormat(localeTag(locale), options).format(input),
  }), [direction, locale, setLocale]);

  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>;
}

export function useI18n(): I18nContextValue {
  const context = useContext(I18nContext);
  if (!context) throw new Error("useI18n must be used within I18nProvider");
  return context;
}
