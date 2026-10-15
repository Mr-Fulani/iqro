import type { Bookmark } from "./api";

/** Maps `surah:ayah` to the live bookmark so the reader can tell saved ayahs apart. */
export function indexAyahBookmarks(bookmarks: Bookmark[]): Record<string, Bookmark> {
  return Object.fromEntries(
    bookmarks.flatMap((bookmark) =>
      bookmark.ayah && !bookmark.deleted_at
        ? [[`${bookmark.ayah.surah_number}:${bookmark.ayah.ayah_number}`, bookmark]]
        : [],
    ),
  );
}
