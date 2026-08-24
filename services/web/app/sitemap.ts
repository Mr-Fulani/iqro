import type { MetadataRoute } from "next";
import { SUPPORTED_LOCALES } from "../lib/i18n";
import { localizedAlternates, localizedPath } from "../lib/routing";
import { absoluteSiteUrl, PUBLIC_INDEXABLE_PATHS } from "../lib/seo";

export const dynamic = "force-dynamic";

const PRIORITY: Record<(typeof PUBLIC_INDEXABLE_PATHS)[number], number> = {
  "/": 1,
  "/quran": 0.9,
  "/audio": 0.8,
  "/prayer": 0.7,
};

export default function sitemap(): MetadataRoute.Sitemap {
  return PUBLIC_INDEXABLE_PATHS.flatMap((path) =>
    SUPPORTED_LOCALES.map((locale) => ({
      url: absoluteSiteUrl(localizedPath(locale, path)),
      changeFrequency: path === "/" ? "weekly" as const : "daily" as const,
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
