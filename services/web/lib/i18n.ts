import type ru from "./messages/ru";

export const SUPPORTED_LOCALES = ["ru", "en", "ar", "tr"] as const;
export type Locale = (typeof SUPPORTED_LOCALES)[number];
export type Direction = "ltr" | "rtl";
export type TranslationVariables = Record<string, string | number>;

export const LOCALE_COOKIE_NAME = "quran_locale_v1";
export const DEFAULT_LOCALE: Locale = "ru";

// The strings live in lib/messages, one module per locale: client components get
// the page's locale through useI18n(), server code gets all four from lib/translate.
export type MessageKey = keyof typeof ru;
export type Messages = Record<MessageKey, string>;
export type Translate = (key: MessageKey, variables?: TranslationVariables) => string;

export function isLocale(value: string | undefined | null): value is Locale {
  return SUPPORTED_LOCALES.includes(value as Locale);
}

export function directionFor(locale: Locale): Direction {
  return locale === "ar" ? "rtl" : "ltr";
}

export function localeTag(locale: Locale): string {
  return { ru: "ru-RU", en: "en-US", ar: "ar", tr: "tr-TR" }[locale];
}

export function formatMessage(template: string, variables: TranslationVariables = {}): string {
  return template.replace(/\{([A-Za-z0-9_]+)\}/g, (placeholder, variable: string) => {
    const value = variables[variable];
    return value === undefined ? placeholder : String(value);
  });
}

export function localeFromAcceptLanguage(value: string | null): Locale {
  if (!value) return DEFAULT_LOCALE;
  for (const item of value.split(",")) {
    const language = item.trim().split(";")[0]?.toLowerCase().split("-")[0];
    if (isLocale(language)) return language;
  }
  return DEFAULT_LOCALE;
}
