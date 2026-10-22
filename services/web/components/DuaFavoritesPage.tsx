"use client";

import { useEffect, useState } from "react";

import { api, type DuaEntry } from "../lib/api";
import { useAuth } from "../lib/auth-context";
import { duaEntryKey } from "../lib/dua-presentation";
import { useI18n } from "../lib/i18n-context";
import { DuaError, DuaLoading, DuaTopBar } from "./DuaChrome";
import { DuaFeed } from "./DuaFeed";

/** The app's favourite du'a, opened from their card in the catalog. */
export function DuaFavoritesPage() {
  const { locale, t } = useI18n();
  const { isLoading: authLoading, session } = useAuth();
  const [entries, setEntries] = useState<DuaEntry[] | null>(null);
  const [failed, setFailed] = useState(false);
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    if (authLoading) return;
    if (!session) {
      setEntries([]);
      return;
    }
    let active = true;
    setFailed(false);
    api.getDuaFavorites(locale, true)
      .then((snapshot) => {
        if (!active) return;
        setEntries(snapshot.results.flatMap((favorite) =>
          favorite.is_favorite && favorite.entry ? [favorite.entry] : []));
      })
      .catch(() => {
        if (active) setFailed(true);
      });
    return () => {
      active = false;
    };
  }, [attempt, authLoading, locale, session]);

  // A du'a taken out of the favourites leaves the list, as in the app.
  const onFavoriteChange = (entry: DuaEntry, isFavorite: boolean) => {
    if (isFavorite) return;
    setEntries((current) => current?.filter((item) => duaEntryKey(item) !== duaEntryKey(entry)) ?? current);
  };

  return (
    <div className="dua-page">
      <DuaTopBar locale={locale} t={t} title={t("dua.favorites")} subtitle={t("dua.favoritesSubtitle")} backHref="/dua" />
      {entries ? (
        <DuaFeed entries={entries} showPositions sideList onFavoriteChange={onFavoriteChange} />
      ) : failed ? (
        <DuaError t={t} onRetry={() => setAttempt((value) => value + 1)} />
      ) : (
        <DuaLoading t={t} />
      )}
    </div>
  );
}
