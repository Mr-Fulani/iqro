import type { AyahAnnotation } from "./api";

/** Same palette and fallback as the app (ayah_annotations.dart), so both clients agree. */
export const AYAH_HIGHLIGHT_COLOR_KEYS = ["yellow", "lime", "blue", "pink", "lavender"] as const;
export type AyahHighlightColorKey = (typeof AYAH_HIGHLIGHT_COLOR_KEYS)[number];

export function normalizeAyahHighlightColor(colorKey: string | null | undefined): AyahHighlightColorKey {
  return (AYAH_HIGHLIGHT_COLOR_KEYS as readonly string[]).includes(colorKey || "")
    ? (colorKey as AyahHighlightColorKey)
    : "lime";
}

const updatedAt = (annotation: AyahAnnotation) =>
  Date.parse(annotation.updated_at || annotation.client_updated_at) || 0;

/** Newest first; the app sorts its notes list the same way. */
export function sortAyahAnnotations(annotations: AyahAnnotation[]): AyahAnnotation[] {
  return [...annotations].sort((left, right) => updatedAt(right) - updatedAt(left));
}

/**
 * Maps `surah:ayah` to the live annotation of one edition. The server does not
 * forbid two annotations on one ayah, so the newest one wins, as in the app.
 */
export function indexAyahAnnotations(
  annotations: AyahAnnotation[],
  editionCode: string,
): Record<string, AyahAnnotation> {
  const index: Record<string, AyahAnnotation> = {};
  for (const annotation of sortAyahAnnotations(annotations)) {
    if (annotation.deleted_at || annotation.edition_code !== editionCode || !annotation.ayah) continue;
    const key = `${annotation.ayah.surah_number}:${annotation.ayah.ayah_number}`;
    index[key] ??= annotation;
  }
  return index;
}

/** Live annotations that carry a note, newest first: the notes list. */
export function ayahNotes(annotations: AyahAnnotation[]): AyahAnnotation[] {
  return sortAyahAnnotations(annotations).filter(
    (annotation) => !annotation.deleted_at && annotation.ayah && annotation.note.trim() !== "",
  );
}
