import { quranAyahPath, quranEditionPath, quranSurahPath } from "./quran-content";
import { localizedSitemapEntry } from "./sitemap-xml";

export const QURAN_SITEMAP_INDEX_PATH = "/sitemaps/quran/sitemap.xml";

export function quranVersionSitemapPath(edition: string, version: string): string {
  return `/sitemaps/quran/${encodeURIComponent(edition)}/${encodeURIComponent(version)}/sitemap.xml`;
}

export function quranSurahSitemapEntries(
  edition: string,
  surahs: Array<{ number: number; ayah_count: number }>,
  lastModified: string,
): string {
  const editionEntry = localizedSitemapEntry(quranEditionPath(edition), lastModified);
  const contentEntries = surahs.map((surah) => {
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
  return `${editionEntry}${contentEntries}`;
}
