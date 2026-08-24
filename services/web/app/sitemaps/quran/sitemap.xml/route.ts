import { getPublishedEditions } from "@/lib/public-content";
import {
  quranVersionSitemapPath,
} from "@/lib/quran-sitemap";
import { absoluteSiteUrl } from "@/lib/seo";
import { xmlEscape, xmlResponse } from "@/lib/sitemap-xml";

export const revalidate = 3_600;

export async function GET() {
  try {
    const editions = await getPublishedEditions();
    const entries = editions.flatMap((edition) => {
      const version = edition.active_version;
      if (!version) return [];
      return [
        `<sitemap><loc>${xmlEscape(
          absoluteSiteUrl(quranVersionSitemapPath(edition.code, version.version)),
        )}</loc><lastmod>${xmlEscape(version.published_at)}</lastmod></sitemap>`,
      ];
    }).join("");

    return xmlResponse(
      `<?xml version="1.0" encoding="UTF-8"?><sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">${entries}</sitemapindex>`,
    );
  } catch {
    return xmlResponse(
      `<?xml version="1.0" encoding="UTF-8"?><error>Quran sitemap is temporarily unavailable</error>`,
      503,
    );
  }
}
