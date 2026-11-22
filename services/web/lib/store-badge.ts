import type { Locale } from "./i18n";

// Google's own badge files (play.google.com/intl/en_us/badges), one per site
// language, with the transparent margin trimmed; the clear space the brand
// rules ask for (a quarter of the badge height) is added in CSS.
const BADGE_SIZES: Record<Locale, { width: number; height: number }> = {
  ru: { width: 646, height: 192 },
  en: { width: 564, height: 168 },
  ar: { width: 564, height: 168 },
  tr: { width: 646, height: 192 },
};

export type GooglePlayBadge = { href: string; src: string; width: number; height: number };

/** The badge to show, or null while the store page is not public (no URL set). */
export function googlePlayBadge(locale: Locale, storeUrl: string | undefined): GooglePlayBadge | null {
  const href = storeUrl?.trim();
  if (!href) return null;
  return { href, src: `/images/store/google-play-${locale}.webp`, ...BADGE_SIZES[locale] };
}
