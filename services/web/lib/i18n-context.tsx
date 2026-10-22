"use client";

import dynamic from "next/dynamic";
import { ComponentType, createContext, ReactNode, startTransition, useCallback, useContext, useEffect, useMemo, useState } from "react";
import { api } from "./api";
import {
  directionFor,
  formatMessage,
  LOCALE_COOKIE_NAME,
  localeTag,
  Locale,
  Messages,
  Translate,
} from "./i18n";

type I18nContextValue = {
  locale: Locale;
  direction: "ltr" | "rtl";
  setLocale: (locale: Locale) => void;
  t: Translate;
  formatDate: (value: string | number | Date, options?: Intl.DateTimeFormatOptions) => string;
  formatNumber: (value: number, options?: Intl.NumberFormatOptions) => string;
};

const I18nContext = createContext<I18nContextValue | undefined>(undefined);

type LocaleMessagesProps = { children: (messages: Messages) => ReactNode };

function provideMessages({ default: messages }: { default: Messages }): ComponentType<LocaleMessagesProps> {
  return function LocaleMessages({ children }: LocaleMessagesProps) {
    return children(messages);
  };
}

// One chunk per locale: a page downloads the strings of its own language only.
// next/dynamic preloads that chunk from the server-rendered <head>, so hydration
// does not wait for a request that would start only after the page's scripts ran.
const LOCALE_MESSAGES: Record<Locale, ComponentType<LocaleMessagesProps>> = {
  ru: dynamic(() => import("./messages/ru").then(provideMessages)),
  en: dynamic(() => import("./messages/en").then(provideMessages)),
  ar: dynamic(() => import("./messages/ar").then(provideMessages)),
  tr: dynamic(() => import("./messages/tr").then(provideMessages)),
};

export function I18nProvider({ initialLocale, children }: { initialLocale: Locale; children: ReactNode }) {
  const [locale, setLocaleState] = useState<Locale>(initialLocale);

  const setLocale = useCallback((nextLocale: Locale) => {
    // A transition keeps the current language on screen while the next one downloads.
    startTransition(() => setLocaleState(nextLocale));
    document.cookie = `${LOCALE_COOKIE_NAME}=${nextLocale}; Path=/; Max-Age=31536000; SameSite=Lax`;
    api.setLocale(nextLocale);
    void api.updateSessionLocale(nextLocale).catch(() => {
      // Browser preference remains authoritative when the visitor has no active session.
    });
  }, []);

  const LocaleMessages = LOCALE_MESSAGES[locale];
  return (
    <LocaleMessages>
      {(messages) => (
        <I18nScope locale={locale} messages={messages} setLocale={setLocale}>
          {children}
        </I18nScope>
      )}
    </LocaleMessages>
  );
}

function I18nScope({
  locale,
  messages,
  setLocale,
  children,
}: {
  locale: Locale;
  messages: Messages;
  setLocale: (locale: Locale) => void;
  children: ReactNode;
}) {
  const direction = directionFor(locale);

  useEffect(() => {
    api.setLocale(locale);
    api.setMessages(messages);
    document.documentElement.lang = locale;
    document.documentElement.dir = direction;
  }, [direction, locale, messages]);

  const value = useMemo<I18nContextValue>(() => ({
    locale,
    direction,
    setLocale,
    t: (key, variables) => formatMessage(messages[key], variables),
    formatDate: (input, options) => new Intl.DateTimeFormat(localeTag(locale), options).format(new Date(input)),
    formatNumber: (input, options) => new Intl.NumberFormat(localeTag(locale), options).format(input),
  }), [direction, locale, messages, setLocale]);

  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>;
}

export function useI18n(): I18nContextValue {
  const context = useContext(I18nContext);
  if (!context) throw new Error("useI18n must be used within I18nProvider");
  return context;
}
