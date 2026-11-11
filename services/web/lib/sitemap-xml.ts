import { SUPPORTED_LOCALES, type Locale } from "./i18n";
import { localizedPath } from "./routing";
import { absoluteSiteUrl } from "./seo";

export function xmlEscape(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&apos;");
}

export function localizedSitemapEntry(
  path: string,
  lastModified?: string,
  locales: readonly Locale[] = SUPPORTED_LOCALES,
): string {
  const alternates = locales.map((locale) =>
    `<xhtml:link rel="alternate" hreflang="${locale}" href="${xmlEscape(
      absoluteSiteUrl(localizedPath(locale, path)),
    )}"/>`,
  ).join("");
  const xDefault = `<xhtml:link rel="alternate" hreflang="x-default" href="${xmlEscape(
    absoluteSiteUrl(localizedPath(locales.includes("ru") ? "ru" : locales[0], path)),
  )}"/>`;
  const lastmod = lastModified ? `<lastmod>${xmlEscape(lastModified)}</lastmod>` : "";

  return locales.map((locale) =>
    `<url><loc>${xmlEscape(absoluteSiteUrl(localizedPath(locale, path)))}</loc>${alternates}${xDefault}${lastmod}</url>`,
  ).join("");
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
