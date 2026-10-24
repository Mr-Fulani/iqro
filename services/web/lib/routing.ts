import {
  DEFAULT_LOCALE,
  isLocale,
  type Locale,
  SUPPORTED_LOCALES,
} from "./i18n";

const INTERNAL_ORIGIN = "http://quran.local";

export function localeFromPathname(pathname: string): Locale | null {
  const firstSegment = pathname.split("/")[1];
  return isLocale(firstSegment) ? firstSegment : null;
}

export function stripLocalePrefix(pathname: string): string {
  const locale = localeFromPathname(pathname);
  if (!locale) return pathname || "/";

  const stripped = pathname.slice(locale.length + 1);
  return stripped || "/";
}

export function localizedPath(locale: Locale, href: string): string {
  if (href.startsWith("#")) return href;

  const url = new URL(href, INTERNAL_ORIGIN);
  if (url.origin !== INTERNAL_ORIGIN) return href;

  const pathname = stripLocalePrefix(url.pathname);
  const localizedPathname = pathname === "/" ? `/${locale}` : `/${locale}${pathname}`;
  return `${localizedPathname}${url.search}${url.hash}`;
}

/** Alternates of a page; content published in fewer languages passes them as `locales`. */
export function localizedAlternates(
  pathname: string,
  locales: readonly Locale[] = SUPPORTED_LOCALES,
): Record<string, string> {
  const fallback = locales.includes(DEFAULT_LOCALE) ? DEFAULT_LOCALE : locales[0] ?? DEFAULT_LOCALE;
  return {
    ...Object.fromEntries(
      locales.map((locale) => [locale, localizedPath(locale, pathname)]),
    ),
    "x-default": localizedPath(fallback, pathname),
  };
}
