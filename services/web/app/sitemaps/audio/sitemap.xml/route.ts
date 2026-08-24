import { audioVersionSitemapPath } from "@/lib/audio-sitemap";
import { getPublishedRecitations } from "@/lib/public-content";
import { absoluteSiteUrl } from "@/lib/seo";
import { xmlEscape, xmlResponse } from "@/lib/sitemap-xml";

export const revalidate = 3_600;

export async function GET() {
  try {
    const recitations = await getPublishedRecitations();
    const entries = recitations.map((recitation) =>
      `<sitemap><loc>${xmlEscape(
        absoluteSiteUrl(audioVersionSitemapPath(recitation.id, recitation.version)),
      )}</loc><lastmod>${xmlEscape(recitation.published_at)}</lastmod></sitemap>`,
    ).join("");
    return xmlResponse(
      `<?xml version="1.0" encoding="UTF-8"?><sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">${entries}</sitemapindex>`,
    );
  } catch {
    return xmlResponse(
      `<?xml version="1.0" encoding="UTF-8"?><error>Audio sitemap is temporarily unavailable</error>`,
      503,
    );
  }
}
