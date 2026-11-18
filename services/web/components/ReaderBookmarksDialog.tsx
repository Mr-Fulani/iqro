"use client";

import { useCallback, useEffect, useId, useRef, useState } from "react";
import { api, Bookmark } from "../lib/api";
import { useI18n } from "../lib/i18n-context";

/**
 * The bookmarks of the phone's Mushaf reader, as the app's sheet
 * (mushaf_bookmarks_sheet.dart): a tap opens the bookmarked ayah.
 */
export function ReaderBookmarksDialog({ onOpen, onClose }: {
  onOpen: (bookmark: Bookmark) => void;
  onClose: () => void;
}) {
  const { t, formatNumber } = useI18n();
  const dialog = useRef<HTMLDialogElement>(null);
  const titleId = useId();
  const [bookmarks, setBookmarks] = useState<Bookmark[] | null>(null);
  const [failed, setFailed] = useState(false);

  const load = useCallback(() => {
    setFailed(false);
    setBookmarks(null);
    // A visitor without a session has saved nothing yet.
    if (!api.getSession()) {
      setBookmarks([]);
      return;
    }
    api.getAllBookmarks().then(setBookmarks).catch(() => setFailed(true));
  }, []);

  useEffect(() => {
    const element = dialog.current;
    if (element && !element.open) element.showModal();
    load();
  }, [load]);

  const withAyah = bookmarks?.filter((bookmark) => bookmark.ayah) ?? [];

  return (
    <dialog ref={dialog} className="ayah-annotation-dialog reader-bookmarks" aria-labelledby={titleId} onClose={onClose} data-testid="reader-bookmarks">
      <div className="ayah-annotation-dialog-head">
        <h2 id={titleId}>{t("quran.readerBookmarks")}</h2>
        <button type="button" className="btn btn-secondary btn-sm" onClick={() => dialog.current?.close()} aria-label={t("common.close")}>×</button>
      </div>
      {failed ? (
        <div className="reader-bookmarks-state">
          <p>{t("quran.readerBookmarksError")}</p>
          <button type="button" className="btn btn-secondary btn-sm" onClick={load}>{t("common.refresh")}</button>
        </div>
      ) : bookmarks === null ? (
        <p className="reader-bookmarks-state" aria-live="polite">{t("common.loading")}</p>
      ) : withAyah.length === 0 ? (
        <p className="reader-bookmarks-state">{t("quran.readerBookmarksEmpty")}</p>
      ) : (
        <ul className="reader-bookmarks-list">
          {withAyah.map((bookmark) => (
            <li key={bookmark.id}>
              <button
                type="button"
                onClick={() => {
                  onOpen(bookmark);
                  dialog.current?.close();
                }}
              >
                <strong>{t("common.surah", { surah: formatNumber(bookmark.ayah!.surah_number) })}</strong>
                <small>{t("common.ayah", { ayah: `${bookmark.ayah!.surah_number}:${bookmark.ayah!.ayah_number}` })}</small>
              </button>
            </li>
          ))}
        </ul>
      )}
    </dialog>
  );
}
