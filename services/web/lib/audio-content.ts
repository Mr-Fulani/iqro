import type { Recitation, Reciter } from "./api";
import type { Locale } from "./i18n";

export function reciterName(reciter: Reciter, locale: Locale): string {
  if (locale === "ar") return reciter.name_ar;
  if (locale === "ru") return reciter.name_ru;
  return reciter.name_en;
}

export function reciterBiography(reciter: Reciter, locale: Locale): string {
  if (locale === "ar") return reciter.biography_ar || "";
  if (locale === "ru") return reciter.biography_ru || "";
  return reciter.biography_en || "";
}

export function reciterPath(reciter: string): string {
  return `/audio/reciters/${encodeURIComponent(reciter)}`;
}

export function recitationPath(recitation: string): string {
  return `/audio/recitations/${encodeURIComponent(recitation)}`;
}

export function recitationLabel(recitation: Recitation): string {
  return `${recitation.style.toUpperCase()} · ${recitation.quran_edition.riwayah}`;
}

export function formatTrackDuration(durationMs: number, locale: Locale): string {
  const totalSeconds = Math.max(0, Math.floor(durationMs / 1_000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return new Intl.NumberFormat(locale).format(minutes) + `:${String(seconds).padStart(2, "0")}`;
}
