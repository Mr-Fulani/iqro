"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";

import { api, type DuaEntry } from "../lib/api";
import { useAuth } from "../lib/auth-context";
import { useI18n } from "../lib/i18n-context";
import { localizedPath } from "../lib/routing";
import { FavoriteHeartIcon } from "./FavoriteHeartIcon";

function entryKey(entry: DuaEntry): string {
  return `${entry.collection}:${entry.source_number}`;
}

function entryAnchor(entry: DuaEntry): string {
  return `dua-${entry.collection}-${entry.source_number}`;
}

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

export function DuaEntryList({
  entries,
  headingLevel = 2,
  onFavoriteChange,
  compact = false,
}: {
  entries: DuaEntry[];
  headingLevel?: 2 | 3;
  onFavoriteChange?: (entry: DuaEntry, isFavorite: boolean) => void;
  compact?: boolean;
}) {
  const { isLoading: authLoading, loginGuest, session } = useAuth();
  const { formatNumber, locale, t } = useI18n();
  const EntryHeading = headingLevel === 3 ? "h3" : "h2";
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const [favoriteKeys, setFavoriteKeys] = useState<Set<string>>(new Set());
  const [favoriteBusyKeys, setFavoriteBusyKeys] = useState<Set<string>>(new Set());
  const [favoriteErrors, setFavoriteErrors] = useState<Record<string, string>>({});
  const [activeAudioKey, setActiveAudioKey] = useState<string | null>(null);
  const [audioPlaying, setAudioPlaying] = useState(false);
  const [audioError, setAudioError] = useState<string | null>(null);

  useEffect(() => {
    if (authLoading) return;
    if (!session) {
      setFavoriteKeys(new Set());
      return;
    }
    let mounted = true;
    void api
      .getDuaFavorites()
      .then((snapshot) => {
        if (!mounted) return;
        setFavoriteKeys(
          new Set(
            snapshot.results
              .filter((favorite) => favorite.is_favorite)
              .map((favorite) => `${favorite.collection}:${favorite.source_number}`),
          ),
        );
      })
      .catch(() => {
        // Keep the public catalog usable if personal state is temporarily unavailable.
      });
    return () => {
      mounted = false;
    };
  }, [authLoading, session]);

  const toggleFavorite = async (entry: DuaEntry) => {
    const key = entryKey(entry);
    if (favoriteBusyKeys.has(key)) return;
    setFavoriteBusyKeys((current) => new Set(current).add(key));
    setFavoriteErrors((current) => ({ ...current, [key]: "" }));
    const wasFavorite = favoriteKeys.has(key);
    const nextFavorite = !wasFavorite;
    try {
      if (!api.getSession() && !(await loginGuest())) {
        throw new Error(t("dua.favoriteError"));
      }
      setFavoriteKeys((current) => {
        const next = new Set(current);
        if (nextFavorite) next.add(key);
        else next.delete(key);
        return next;
      });
      const saved = await api.setDuaFavorite(
        entry.collection,
        entry.source_number,
        nextFavorite,
      );
      setFavoriteKeys((current) => {
        const next = new Set(current);
        if (saved.is_favorite) next.add(key);
        else next.delete(key);
        return next;
      });
      onFavoriteChange?.(entry, saved.is_favorite);
    } catch (error) {
      setFavoriteKeys((current) => {
        const next = new Set(current);
        if (wasFavorite) next.add(key);
        else next.delete(key);
        return next;
      });
      setFavoriteErrors((current) => ({
        ...current,
        [key]: api.normalizeError(error) || t("dua.favoriteError"),
      }));
    } finally {
      setFavoriteBusyKeys((current) => {
        const next = new Set(current);
        next.delete(key);
        return next;
      });
    }
  };

  const toggleAudio = (entry: DuaEntry) => {
    const key = entryKey(entry);
    if (activeAudioKey !== key) {
      setAudioError(null);
      setAudioPlaying(false);
      setActiveAudioKey(key);
      return;
    }
    if (!audioRef.current) return;
    if (audioRef.current.paused) {
      void audioRef.current.play().catch(() => setAudioError(t("dua.audioError")));
    } else {
      audioRef.current.pause();
    }
  };

  if (entries.length === 0) {
    return (
      <div className="dua-empty">
        <span aria-hidden="true">🤲</span>
        <p>{t("dua.empty")}</p>
      </div>
    );
  }

  return (
    <div className={`dua-entry-list${compact ? " is-compact" : ""}`}>
      {entries.map((entry) => {
        const key = entryKey(entry);
        const audio = entry.audio?.[0];
        const favorite = favoriteKeys.has(key);
        const favoriteBusy = favoriteBusyKeys.has(key);
        const audioActive = activeAudioKey === key;
        const readerName =
          locale === "ar" && audio?.reader_name_ar ? audio.reader_name_ar : audio?.reader_name;
        return (
          <article
            className={`dua-entry-card${compact ? " is-compact" : ""}`}
            id={entryAnchor(entry)}
            key={entry.id}
          >
            <header className="dua-entry-head">
              <div>
                <span className="dua-entry-number">#{formatNumber(entry.source_number)}</span>
                <EntryHeading>
                  <Link
                    className="dua-entry-title-link"
                    href={localizedPath(
                      locale,
                      `/dua/${entry.category.slug}#${entryAnchor(entry)}`,
                    )}
                  >
                    {entry.category.title}
                  </Link>
                </EntryHeading>
              </div>
              <div className="dua-entry-tools">
                <div className="dua-entry-actions">
                  {audio ? (
                    <button
                      type="button"
                      className={`dua-icon-action ${audioActive ? "is-active" : ""}`}
                      onClick={() => toggleAudio(entry)}
                      aria-label={
                        audioActive && audioPlaying ? t("dua.pauseAudio") : t("dua.playAudio")
                      }
                      title={
                        audioActive && audioPlaying ? t("dua.pauseAudio") : t("dua.playAudio")
                      }
                      aria-pressed={audioActive && audioPlaying}
                    >
                      <AudioIcon playing={audioActive && audioPlaying} />
                    </button>
                  ) : null}
                  <button
                    type="button"
                    className={`dua-icon-action dua-favorite-action ${favorite ? "is-active" : ""}`}
                    onClick={() => void toggleFavorite(entry)}
                    aria-label={favorite ? t("dua.removeFavorite") : t("dua.addFavorite")}
                    title={favorite ? t("dua.removeFavorite") : t("dua.addFavorite")}
                    aria-pressed={favorite}
                    aria-busy={favoriteBusy}
                    disabled={favoriteBusy || authLoading}
                  >
                    <FavoriteHeartIcon active={favorite} />
                  </button>
                </div>
                {!compact ? (
                  <span className="status-chip">
                    {entry.repetition_label
                      ? t("dua.repeatSequence", {
                          count: entry.repetition_label
                            .split(" · ")
                            .map((value) => formatNumber(Number(value)))
                            .join(" · "),
                        })
                      : entry.repetitions === 1
                        ? t("dua.repeatOnce")
                        : t("dua.repeatCount", { count: formatNumber(entry.repetitions) })}
                  </span>
                ) : null}
              </div>
            </header>

            {favoriteErrors[key] ? (
              <p className="dua-action-error" role="alert">
                {favoriteErrors[key]}
              </p>
            ) : null}

            {audioActive && audio ? (
              <div className="dua-audio-panel">
                <audio
                  ref={audioRef}
                  src={audio.url}
                  controls
                  autoPlay
                  preload="none"
                  controlsList="nodownload"
                  onPlay={() => setAudioPlaying(true)}
                  onPause={() => setAudioPlaying(false)}
                  onEnded={() => setAudioPlaying(false)}
                  onError={() => {
                    setAudioPlaying(false);
                    setAudioError(t("dua.audioError"));
                  }}
                >
                  {t("dua.audioUnsupported")}
                </audio>
                <p>
                  {t("dua.audioReader", { reader: readerName || "—" })}{" "}
                  <a href={audio.source_url} target="_blank" rel="noreferrer">
                    {t("dua.audioSource")} ↗
                  </a>
                </p>
                {audioError ? <span role="alert">{audioError}</span> : null}
              </div>
            ) : null}

            {!compact ? (
              <>
                <p className="dua-arabic" lang="ar" dir="rtl">
                  {entry.arabic_text}
                </p>

                {entry.translation?.transliteration ? (
                  <div className="dua-translation-block">
                    <span>{t("dua.transliteration")}</span>
                    <p>{entry.translation.transliteration}</p>
                  </div>
                ) : null}

                {locale !== "ar" && entry.translation ? (
                  <div className="dua-translation-block dua-meaning">
                    <span>{t("dua.meaning")}</span>
                    <p>{entry.translation.meaning_text}</p>
                  </div>
                ) : null}

                <details className="dua-provenance">
                  <summary>{t("dua.sourceAndEvidence")}</summary>
                  <div className="dua-provenance-body">
                    {entry.evidence.map((evidence, index) => (
                      <div key={`${evidence.source_reference}-${index}`}>
                        <strong>{evidence.source_reference}</strong>
                        <span>
                          {evidence.verification_status === "editorially_verified"
                            ? t("dua.editoriallyVerified")
                            : t("dua.sourceOnly")}
                        </span>
                      </div>
                    ))}
                    {entry.source ? (
                      <p>
                        {t("dua.sourceEdition")}: {entry.source.title}.{" "}
                        <a href={entry.source.source_url} target="_blank" rel="noreferrer">
                          {t("dua.openSource")} ↗
                        </a>
                      </p>
                    ) : null}
                  </div>
                </details>
              </>
            ) : null}
          </article>
        );
      })}
    </div>
  );
}
