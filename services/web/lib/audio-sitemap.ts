import { recitationPath, reciterPath } from "./audio-content";
import type { Recitation } from "./api";
import { localizedSitemapEntry } from "./sitemap-xml";

export const AUDIO_SITEMAP_INDEX_PATH = "/sitemaps/audio/sitemap.xml";

export function audioVersionSitemapPath(recitation: string, version: string): string {
  return `/sitemaps/audio/${encodeURIComponent(recitation)}/${encodeURIComponent(version)}/sitemap.xml`;
}

export function audioSitemapEntries(recitation: Recitation): string {
  return [
    localizedSitemapEntry("/audio/reciters", recitation.published_at),
    localizedSitemapEntry(reciterPath(recitation.reciter.id), recitation.published_at),
    localizedSitemapEntry(recitationPath(recitation.id), recitation.published_at),
  ].join("");
}
