import type { MetadataRoute } from "next";
import { SUPPORTED_LOCALES } from "../lib/i18n";
import { localizedAlternates, localizedPath } from "../lib/routing";
import { absoluteSiteUrl, PUBLIC_INDEXABLE_PATHS } from "../lib/seo";

export const dynamic = "force-dynamic";

const PRIORITY: Record<(typeof PUBLIC_INDEXABLE_PATHS)[number], number> = {
  "/": 1,
  "/quran": 0.9,
  "/dua": 0.8,
  "/audio": 0.8,
  "/prayer": 0.7,
  "/legal": 0.4,
  "/privacy": 0.3,
  "/terms": 0.3,
  "/cookies": 0.3,
  "/data-rights": 0.4,
  "/providers": 0.3,
  "/security": 0.3,
  "/contacts": 0.4,
  "/sources": 0.6,
};

export default function sitemap(): MetadataRoute.Sitemap {
  return PUBLIC_INDEXABLE_PATHS.flatMap((path) =>
    SUPPORTED_LOCALES.map((locale) => ({
      url: absoluteSiteUrl(localizedPath(locale, path)),
      changeFrequency: path === "/" ? "weekly" as const : path === "/quran" || path === "/audio" ? "daily" as const : "monthly" as const,
      priority: PRIORITY[path],
      alternates: {
        languages: Object.fromEntries(
          Object.entries(localizedAlternates(path)).map(([language, href]) => [
            language,
            absoluteSiteUrl(href),
          ]),
        ),
      },
    })),
  );
}
