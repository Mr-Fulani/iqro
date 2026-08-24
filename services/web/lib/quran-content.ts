import type { QuranEdition, Surah } from "./api";
import type { Locale } from "./i18n";

export function editionName(edition: QuranEdition, locale: Locale): string {
  if (locale === "ar") return edition.name_ar;
  if (locale === "ru") return edition.name_ru;
  return edition.name_en;
}

export function surahName(surah: Surah, locale: Locale): string {
  if (locale === "ar") return surah.name_ar;
  if (locale === "ru") return surah.name_ru;
  return surah.name_en;
}

export function quranSurahPath(edition: string, surah: number): string {
  return `${quranEditionPath(edition)}/surah/${surah}`;
}

export function quranEditionPath(edition: string): string {
  return `/quran/${encodeURIComponent(edition)}`;
}

export function quranAyahPath(edition: string, surah: number, ayah: number): string {
  return `${quranSurahPath(edition, surah)}/ayah/${ayah}`;
}
