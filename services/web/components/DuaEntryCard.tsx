"use client";

import Link from "next/link";
import { useState } from "react";

import type { DuaEntry } from "../lib/api";
import { splitDuaArabic } from "../lib/dua-arabic";
import { advanceRepetitionCount, duaRepetitionTotal } from "../lib/dua-practice";
import { duaAnchor, duaEntryKey, duaEntryPath } from "../lib/dua-presentation";
import { useI18n } from "../lib/i18n-context";
import { localizedPath } from "../lib/routing";
import { DuaCheckIcon, DuaPlayIcon, DuaRefreshIcon, DuaRepeatIcon } from "./DuaIcons";
import { FavoriteBookmarkIcon } from "./FavoriteBookmarkIcon";
import { ShareIcon } from "./ShareIcon";
import type { DuaAudio } from "./useDuaActions";

/** IqroRepetitionCounter: tap after each repetition; the ring fills up. */
function DuaCounter({ total }: { total: number }) {
  const { t } = useI18n();
  const [completed, setCompleted] = useState(0);
  const remaining = Math.max(total - completed, 0);
  const done = remaining === 0;
  const tap = () => {
    const next = advanceRepetitionCount(completed, total);
    // A light tap per repetition, a longer one at the end, as the app.
    if (next > 0) navigator.vibrate?.(next === total ? 120 : 12);
    setCompleted(next);
  };
  return (
    <button
      type="button"
      className={`dua-counter${done ? " is-done" : ""}`}
      onClick={tap}
      aria-label={done ? t("dua.counterDone") : t("dua.counterRemaining", { count: remaining })}
    >
      <svg className="dua-counter-ring" viewBox="0 0 100 100" aria-hidden="true">
        <circle cx="50" cy="50" r="47" pathLength="100" strokeDasharray={`${(completed / total) * 100} 100`} />
      </svg>
      {done ? <DuaCheckIcon /> : <span className="dua-counter-value" aria-hidden="true">{remaining}</span>}
    </button>
  );
}

/**
 * DuaEntryCard of the app: the opening formulas on their own lines, the
 * Arabic, a repetition counter when it is said several times, the
 * transliteration and meaning, the source, and the actions — listen, repeat,
 * speed, favourite, share — with the du'a's place in its list.
 */
export function DuaEntryCard({
  entry,
  position,
  count,
  audio,
  favorite,
  favoriteBusy,
  favoriteError,
  onToggleFavorite,
  onShare,
  onShowSource,
}: {
  entry: DuaEntry;
  position?: number;
  count?: number;
  audio: DuaAudio;
  favorite: boolean;
  favoriteBusy: boolean;
  favoriteError: string;
  onToggleFavorite: () => void;
  onShare: () => void;
  onShowSource: () => void;
}) {
  const { locale, t } = useI18n();
  const total = duaRepetitionTotal(entry.repetition_label, entry.repetitions);
  const transliteration = entry.translation?.transliteration.trim() ?? "";
  // Arabic shows no meaning: there it repeats the du'a itself.
  const meaning = locale === "ar" ? "" : entry.translation?.meaning_text.trim() ?? "";
  const sourceLabel = entry.source?.title.trim() || entry.source?.provider.trim() || "";
  const reference = entry.evidence.map((item) => item.source_reference.trim()).find(Boolean)
    || `${sourceLabel} · #${entry.source_number}`;
  const hasAudio = Boolean(entry.audio?.[0]?.url);
  const owned = audio.activeKey === duaEntryKey(entry);
  const playing = owned && audio.playing;

  return (
    <article className="dua-card" id={duaAnchor(entry)} aria-label={`#${entry.source_number}`}>
      <div className="dua-arabic" lang="ar" dir="rtl">
        {splitDuaArabic(entry.arabic_text).map((part, index) => (
          <p key={index} className={part.opening ? "dua-arabic-opening" : "dua-arabic-line"}>
            {part.text}
          </p>
        ))}
      </div>
      {total > 1 ? <DuaCounter total={total} /> : null}
      {transliteration ? <p className="dua-transliteration">{transliteration}</p> : null}
      {meaning ? <p className="dua-meaning">{meaning}</p> : null}
      {/* The source sits under the text it backs; the full record opens from it. */}
      <button type="button" className="dua-source-link" aria-haspopup="dialog" onClick={onShowSource}>
        [<bdi>{reference}</bdi>]
      </button>
      {favoriteError ? <p className="dua-action-error" role="alert">{favoriteError}</p> : null}
      <div className="dua-action-bar">
        {hasAudio ? (
          <>
            <button
              type="button"
              className={`dua-action dua-action-play${owned && audio.failed ? " is-error" : ""}`}
              onClick={() => audio.toggle(entry)}
              aria-label={owned && audio.failed ? t("dua.retry") : playing ? t("dua.pauseAudio") : t("dua.playAudio")}
              aria-busy={owned && audio.loading}
            >
              {owned && audio.failed
                ? <DuaRefreshIcon />
                : owned && audio.loading
                  ? <span className="dua-spinner" aria-hidden="true" />
                  : <DuaPlayIcon playing={playing} />}
            </button>
            <button
              type="button"
              className="dua-action"
              onClick={audio.toggleRepeat}
              disabled={!owned}
              aria-label={t("dua.repeat")}
              aria-pressed={owned && audio.repeat}
            >
              <DuaRepeatIcon one={owned && audio.repeat} />
            </button>
            <button
              type="button"
              className="dua-action dua-action-speed"
              onClick={audio.cycleSpeed}
              disabled={!owned}
              aria-label={t("dua.speed")}
            >
              <span dir="ltr">{owned ? audio.speed : 1}×</span>
            </button>
          </>
        ) : null}
        <button
          type="button"
          className="dua-action"
          onClick={onToggleFavorite}
          disabled={favoriteBusy}
          aria-label={favorite ? t("dua.removeFavorite") : t("dua.addFavorite")}
          aria-pressed={favorite}
        >
          <FavoriteBookmarkIcon active={favorite} />
        </button>
        <button
          type="button"
          className="dua-action"
          onClick={onShare}
          aria-haspopup="dialog"
          aria-label={t("duaShare.action")}
        >
          <ShareIcon />
        </button>
        {position && count ? (
          // The place in the list also links to the du'a's own page: chapters
          // are reached only through these links, not through a sitemap.
          <Link
            className="dua-position"
            href={localizedPath(locale, duaEntryPath(entry))}
            aria-label={t("dua.openEntry", { number: entry.source_number })}
          >
            {position}/{count}
          </Link>
        ) : null}
      </div>
    </article>
  );
}
