import { SUPPORTED_LOCALES } from "./i18n";
import { quranAyahPath, quranSurahPath } from "./quran-content";
import { localizedPath } from "./routing";
import { absoluteSiteUrl } from "./seo";

export const QURAN_SITEMAP_INDEX_PATH = "/sitemaps/quran/sitemap.xml";

export function quranVersionSitemapPath(edition: string, version: string): string {
  return `/sitemaps/quran/${encodeURIComponent(edition)}/${encodeURIComponent(version)}/sitemap.xml`;
}

export function xmlEscape(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

export function localizedSitemapEntry(path: string, lastModified: string): string {
  const alternates = SUPPORTED_LOCALES.map((locale) =>
    `<xhtml:link rel="alternate" hreflang="${locale}" href="${xmlEscape(
      absoluteSiteUrl(localizedPath(locale, path)),
    )}"/>`,
  ).join("");
  const xDefault = `<xhtml:link rel="alternate" hreflang="x-default" href="${xmlEscape(
    absoluteSiteUrl(localizedPath("ru", path)),
  )}"/>`;

  return SUPPORTED_LOCALES.map((locale) =>
    `<url><loc>${xmlEscape(absoluteSiteUrl(localizedPath(locale, path)))}</loc>${alternates}${xDefault}<lastmod>${xmlEscape(lastModified)}</lastmod></url>`,
  ).join("");
}

export function quranSurahSitemapEntries(
  edition: string,
  surahs: Array<{ number: number; ayah_count: number }>,
  lastModified: string,
): string {
  return surahs.map((surah) => {
    const surahEntry = localizedSitemapEntry(
      quranSurahPath(edition, surah.number),
      lastModified,
    );
    const ayahEntries = Array.from({ length: surah.ayah_count }, (_, index) =>
      localizedSitemapEntry(
        quranAyahPath(edition, surah.number, index + 1),
        lastModified,
      ),
    ).join("");
    return `${surahEntry}${ayahEntries}`;
  }).join("");
}

export function xmlResponse(body: string, status = 200): Response {
  return new Response(body, {
    status,
    headers: {
      "Content-Type": "application/xml; charset=utf-8",
      "Cache-Control": status === 200
        ? "public, s-maxage=3600, stale-while-revalidate=86400"
        : "no-store",
    },
  });
}
