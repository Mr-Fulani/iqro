"use client";

import Link from "next/link";
import { useState } from "react";

import type { DuaEntry } from "../lib/api";
import { duaEntryKey, duaEntryPath } from "../lib/dua-presentation";
import { duaDisplayTitle } from "../lib/dua-share";
import { useI18n } from "../lib/i18n-context";
import { localizedPath } from "../lib/routing";
import { FavoriteBookmarkIcon } from "./FavoriteBookmarkIcon";
import { useDuaAudio, useDuaFavorites, useDuaShare } from "./useDuaActions";

function AudioIcon({ playing }: { playing: boolean }) {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      {playing ? (
        <>
          <path d="M7 5h3v14H7z" fill="currentColor" />
          <path d="M14 5h3v14h-3z" fill="currentColor" />
        </>
      ) : (
        <path d="m8 5 11 7-11 7Z" fill="currentColor" />
      )}
    </svg>
  );
}

/** The profile's favourite du'a: a compact row each, with its actions. */
export function DuaEntryList({
  entries,
  onFavoriteChange,
}: {
  entries: DuaEntry[];
  onFavoriteChange?: (entry: DuaEntry, isFavorite: boolean) => void;
}) {
  const { formatNumber, locale, t } = useI18n();
  const favorites = useDuaFavorites();
  const audio = useDuaAudio();
  const [shareStatus, setShareStatus] = useState("");
  const share = useDuaShare(setShareStatus);

  const toggleFavorite = async (entry: DuaEntry) => {
    const saved = await favorites.toggle(entry);
    if (saved !== null) onFavoriteChange?.(entry, saved);
  };

  return (
    <div className="dua-entry-list is-compact">
      {shareStatus ? <p role="status">{shareStatus}</p> : null}
      {entries.map((entry) => {
        const key = duaEntryKey(entry);
        const asset = entry.audio?.[0];
        const favorite = favorites.isFavorite(entry);
        const audioActive = audio.activeKey === key;
        const playing = audioActive && audio.playing;
        const readerName =
          locale === "ar" && asset?.reader_name_ar ? asset.reader_name_ar : asset?.reader_name;
        return (
          <article className="dua-entry-card is-compact" key={entry.id}>
            <header className="dua-entry-head">
              <div>
                <span className="dua-entry-number">#{formatNumber(entry.source_number)}</span>
                <h3>
                  <Link className="dua-entry-title-link" href={localizedPath(locale, duaEntryPath(entry))}>
                    {duaDisplayTitle(entry.category.title, locale)}
                  </Link>
                </h3>
              </div>
              <div className="dua-entry-actions">
                <button
                  type="button"
                  className="btn btn-sm btn-secondary"
                  aria-haspopup="dialog"
                  onClick={() => share.open(entry)}
                >
                  {t("dua.share")}
                </button>
                {asset ? (
                  <button
                    type="button"
                    className={`dua-icon-action ${audioActive ? "is-active" : ""}`}
                    onClick={() => audio.toggle(entry)}
                    aria-label={playing ? t("dua.pauseAudio") : t("dua.playAudio")}
                    title={playing ? t("dua.pauseAudio") : t("dua.playAudio")}
                    aria-pressed={playing}
                  >
                    <AudioIcon playing={playing} />
                  </button>
                ) : null}
                <button
                  type="button"
                  className={`dua-icon-action dua-favorite-action ${favorite ? "is-active" : ""}`}
                  onClick={() => void toggleFavorite(entry)}
                  aria-label={favorite ? t("dua.removeFavorite") : t("dua.addFavorite")}
                  title={favorite ? t("dua.removeFavorite") : t("dua.addFavorite")}
                  aria-pressed={favorite}
                  aria-busy={favorites.isBusy(entry)}
                  disabled={favorites.isBusy(entry)}
                >
                  <FavoriteBookmarkIcon active={favorite} />
                </button>
              </div>
            </header>

            {favorites.errorOf(entry) ? (
              <p className="dua-action-error" role="alert">
                {favorites.errorOf(entry)}
              </p>
            ) : null}

            {audioActive && asset ? (
              <div className="dua-audio-panel">
                <audio
                  key={audio.elementKey}
                  {...audio.elementProps}
                  controls
                  controlsList="nodownload"
                >
                  {t("dua.audioUnsupported")}
                </audio>
                <p>
                  {t("dua.audioReader", { reader: readerName || "—" })}{" "}
                  <a href={asset.source_url} target="_blank" rel="noreferrer">
                    {t("dua.audioSource")} ↗
                  </a>
                </p>
                {audio.failed ? <span role="alert">{t("dua.audioError")}</span> : null}
              </div>
            ) : null}
          </article>
        );
      })}
      {share.dialog}
    </div>
  );
}
