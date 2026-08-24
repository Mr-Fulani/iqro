import { audioSitemapEntries } from "@/lib/audio-sitemap";
import {
  getPublishedRecitation,
  getPublishedSurahTracks,
  isUuid,
  PublicContentNotFoundError,
} from "@/lib/public-content";
import { xmlResponse } from "@/lib/sitemap-xml";

export const revalidate = 3_600;

export function generateStaticParams() {
  return [];
}

const VERSION_PATTERN = /^[A-Za-z0-9]+(?:[._-][A-Za-z0-9]+)*$/;

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ recitation: string; version: string }> },
) {
  const { recitation, version } = await params;
  if (!isUuid(recitation) || version.length > 64 || !VERSION_PATTERN.test(version)) {
    return xmlResponse("<error>Not found</error>", 404);
  }
  try {
    const [publishedRecitation, tracks] = await Promise.all([
      getPublishedRecitation(recitation),
      getPublishedSurahTracks(recitation),
    ]);
    if (
      publishedRecitation.version !== version ||
      !publishedRecitation.rights.stream ||
      tracks.length !== publishedRecitation.coverage.surah_count
    ) {
      return xmlResponse("<error>Not found</error>", 404);
    }
    return xmlResponse(
      `<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">${audioSitemapEntries(publishedRecitation)}</urlset>`,
    );
  } catch (error) {
    if (error instanceof PublicContentNotFoundError) {
      return xmlResponse("<error>Not found</error>", 404);
    }
    return xmlResponse("<error>Audio sitemap is temporarily unavailable</error>", 503);
  }
}
