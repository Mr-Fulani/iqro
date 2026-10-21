"use client";

import { useEffect, useState } from "react";

import type { DuaEntry } from "../lib/api";
import { duaAnchor, duaEntryKey, duaPreview } from "../lib/dua-presentation";
import { useI18n } from "../lib/i18n-context";
import { DuaEmpty } from "./DuaChrome";
import { DuaEntryCard } from "./DuaEntryCard";
import { DuaSourceDialog } from "./DuaSourceDialog";
import { useDuaAudio, useDuaFavorites, useDuaShare } from "./useDuaActions";

const SIDE_LIST_QUERY = "(min-width: 1024px)";

/**
 * The desktop's list beside the feed: every du'a of the list with its
 * number and opening words; the one being read is highlighted.
 */
function DuaSideList({ entries }: { entries: DuaEntry[] }) {
  const { locale, t } = useI18n();
  const [current, setCurrent] = useState(duaAnchor(entries[0]));

  useEffect(() => {
    if (!window.matchMedia(SIDE_LIST_QUERY).matches || !("IntersectionObserver" in window)) return;
    const observer = new IntersectionObserver(
      (records) => {
        const visible = records.find((record) => record.isIntersecting);
        if (visible) setCurrent(visible.target.id);
      },
      // The card crossing the upper third of the screen is the one being read.
      { rootMargin: "-30% 0px -65% 0px" },
    );
    for (const entry of entries) {
      const card = document.getElementById(duaAnchor(entry));
      if (card) observer.observe(card);
    }
    return () => observer.disconnect();
  }, [entries]);

  return (
    <nav className="dua-side-list" aria-label={t("dua.contents")}>
      <ol>
        {entries.map((entry, index) => {
          const anchor = duaAnchor(entry);
          const preview = duaPreview(entry, locale);
          return (
            <li key={entry.id}>
              <a href={`#${anchor}`} aria-current={current === anchor ? "location" : undefined}>
                <span className="dua-side-position">{index + 1}</span>
                <span className="dua-side-preview" dir={preview.arabic ? "rtl" : undefined}>
                  {preview.text}
                </span>
              </a>
            </li>
          );
        })}
      </ol>
    </nav>
  );
}

/**
 * _DuaFeed of the app: a chapter, a topic or the favourites read as one
 * column of du'a cards. On a wide screen the list of its du'a stands beside
 * it.
 */
export function DuaFeed({
  entries,
  showPositions = false,
  sideList = false,
  onFavoriteChange,
}: {
  entries: DuaEntry[];
  /** «2/23» on each card, as in a chapter or topic. */
  showPositions?: boolean;
  sideList?: boolean;
  onFavoriteChange?: (entry: DuaEntry, isFavorite: boolean) => void;
}) {
  const { t } = useI18n();
  const favorites = useDuaFavorites();
  const audio = useDuaAudio();
  const [message, setMessage] = useState("");
  const share = useDuaShare(setMessage);
  const [sourceEntry, setSourceEntry] = useState<DuaEntry | null>(null);

  useEffect(() => {
    if (!message) return;
    const timer = window.setTimeout(() => setMessage(""), 3_000);
    return () => window.clearTimeout(timer);
  }, [message]);

  if (entries.length === 0) return <DuaEmpty message={t("dua.notFound")} />;

  const toggleFavorite = async (entry: DuaEntry) => {
    const saved = await favorites.toggle(entry);
    if (saved === null) return;
    setMessage(saved ? t("dua.favoriteAdded") : t("dua.favoriteRemoved"));
    onFavoriteChange?.(entry, saved);
  };
  const withSideList = sideList && entries.length > 1;

  return (
    <div className={`dua-feed${withSideList ? " has-side-list" : ""}`}>
      {withSideList ? <DuaSideList entries={entries} /> : null}
      <div className="dua-feed-cards">
        {entries.map((entry, index) => (
          <DuaEntryCard
            key={duaEntryKey(entry)}
            entry={entry}
            position={showPositions ? index + 1 : undefined}
            count={showPositions ? entries.length : undefined}
            audio={audio}
            favorite={favorites.isFavorite(entry)}
            favoriteBusy={favorites.isBusy(entry)}
            favoriteError={favorites.errorOf(entry)}
            onToggleFavorite={() => void toggleFavorite(entry)}
            onShare={() => share.open(entry)}
            onShowSource={() => setSourceEntry(entry)}
          />
        ))}
      </div>
      {audio.activeKey ? <audio key={audio.elementKey} className="dua-audio" {...audio.elementProps} /> : null}
      {share.dialog}
      {sourceEntry ? <DuaSourceDialog entry={sourceEntry} onClose={() => setSourceEntry(null)} /> : null}
      <p className="dua-snackbar" role="status">{message}</p>
    </div>
  );
}
