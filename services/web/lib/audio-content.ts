import type { Recitation, Reciter } from "./api";
import type { Locale } from "./i18n";

export function reciterName(reciter: Reciter, locale: Locale): string {
  if (locale === "ar") return reciter.name_ar;
  if (locale === "ru") return reciter.name_ru;
  if (locale === "tr") return reciter.name_tr || reciter.name_en;
  return reciter.name_en;
}

export function reciterBiography(reciter: Reciter, locale: Locale): string {
  if (locale === "ar") return reciter.biography_ar || "";
  if (locale === "ru") return reciter.biography_ru || "";
  if (locale === "tr") return reciter.biography_tr || reciter.biography_en || "";
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

/**
 * «9:44», or «1:57:34» for a recording of an hour or more, as the app shows
 * it; minutes alone read «117:34». `head` formats the leading number.
 */
export function formatClock(durationMs: number, head: (value: number) => string = String): string {
  const totalSeconds = Math.max(0, Math.floor(durationMs / 1_000));
  const hours = Math.floor(totalSeconds / 3_600);
  const minutes = Math.floor(totalSeconds / 60) % 60;
  const seconds = String(totalSeconds % 60).padStart(2, "0");
  return hours > 0
    ? `${head(hours)}:${String(minutes).padStart(2, "0")}:${seconds}`
    : `${head(minutes)}:${seconds}`;
}

export function formatTrackDuration(durationMs: number, locale: Locale): string {
  return formatClock(durationMs, (value) => new Intl.NumberFormat(locale).format(value));
}
