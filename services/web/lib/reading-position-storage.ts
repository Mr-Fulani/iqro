const READING_POSITION_STORAGE_KEY_PREFIX = "iqro_quran_reading_position_v1";

export type LocalReadingPosition = {
  pageNumber: number;
  surahNumber?: number;
  ayahNumber?: number;
  updatedAt: string;
};

export function readingPositionStorageKey(editionCode: string): string {
  return `${READING_POSITION_STORAGE_KEY_PREFIX}:${editionCode}`;
}

export function readLocalReadingPosition(
  editionCode: string,
  storage: Pick<Storage, "getItem"> | null = typeof window !== "undefined" ? window.localStorage : null,
): LocalReadingPosition | null {
  if (!storage) return null;
  try {
    const raw = storage.getItem(readingPositionStorageKey(editionCode));
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<LocalReadingPosition>;
    if (
      typeof parsed.pageNumber !== "number"
      || !Number.isSafeInteger(parsed.pageNumber)
      || parsed.pageNumber < 1
      || parsed.pageNumber > 604
    ) {
      return null;
    }
    return {
      pageNumber: parsed.pageNumber,
      surahNumber:
        typeof parsed.surahNumber === "number"
        && Number.isSafeInteger(parsed.surahNumber)
        && parsed.surahNumber >= 1
        && parsed.surahNumber <= 114
          ? parsed.surahNumber
          : undefined,
      ayahNumber:
        typeof parsed.ayahNumber === "number"
        && Number.isSafeInteger(parsed.ayahNumber)
        && parsed.ayahNumber >= 1
          ? parsed.ayahNumber
          : undefined,
      updatedAt: typeof parsed.updatedAt === "string" ? parsed.updatedAt : new Date().toISOString(),
    };
  } catch {
    return null;
  }
}

export function writeLocalReadingPosition(
  editionCode: string,
  position: { pageNumber: number; surahNumber?: number; ayahNumber?: number },
  storage: Pick<Storage, "setItem"> | null = typeof window !== "undefined" ? window.localStorage : null,
): void {
  if (!storage) return;
  try {
    storage.setItem(
      readingPositionStorageKey(editionCode),
      JSON.stringify({
        ...position,
        updatedAt: new Date().toISOString(),
      }),
    );
  } catch {
    // Local persistence remains best-effort when storage is blocked.
  }
}
