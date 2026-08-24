import {
  getPublishedEdition,
  getPublishedSurahs,
  isEditionCode,
  PublicContentNotFoundError,
} from "@/lib/public-content";
import { quranSurahSitemapEntries } from "@/lib/quran-sitemap";
import { xmlResponse } from "@/lib/sitemap-xml";

export const revalidate = 3_600;

export function generateStaticParams() {
  return [];
}

const VERSION_PATTERN = /^[A-Za-z0-9]+(?:[._-][A-Za-z0-9]+)*$/;

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ edition: string; version: string }> },
) {
  const { edition, version } = await params;
  if (
    !isEditionCode(edition) ||
    version.length > 64 ||
    !VERSION_PATTERN.test(version)
  ) {
    return xmlResponse("<error>Not found</error>", 404);
  }

  try {
    const [publishedEdition, surahs] = await Promise.all([
      getPublishedEdition(edition),
      getPublishedSurahs(edition),
    ]);
    const activeVersion = publishedEdition.active_version;
    if (!activeVersion || activeVersion.version !== version) {
      return xmlResponse("<error>Not found</error>", 404);
    }

    const urlCount = surahs.reduce(
      (total, surah) => total + (surah.ayah_count + 1) * 4,
      4,
    );
    if (urlCount > 50_000) {
      throw new Error("Quran content sitemap exceeds the 50,000 URL limit");
    }

    const entries = quranSurahSitemapEntries(
      edition,
      surahs,
      activeVersion.published_at,
    );
    return xmlResponse(
      `<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">${entries}</urlset>`,
    );
  } catch (error) {
    if (error instanceof PublicContentNotFoundError) {
      return xmlResponse("<error>Not found</error>", 404);
    }
    return xmlResponse("<error>Quran sitemap is temporarily unavailable</error>", 503);
  }
}
