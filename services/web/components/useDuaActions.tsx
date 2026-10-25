"use client";

import { lazy, useEffect, useRef, useState } from "react";

import { api, type DuaEntry } from "../lib/api";
import { claimAudioFocus, registerAudioPlayer } from "../lib/audio-focus";
import { useAuth } from "../lib/auth-context";
import { contentShareText, shareTextOnly, type ContentShareText } from "../lib/content-share";
import { nextPlaybackSpeed } from "../lib/dua-practice";
import { duaEntryKey, duaEntryPath } from "../lib/dua-presentation";
import { trackEvent } from "../lib/analytics";
import { duaShareText, duaShareTitle } from "../lib/dua-share";
import { useI18n } from "../lib/i18n-context";
import { localizedPath } from "../lib/routing";
import { ShareDialogBoundary } from "./ShareDialogBoundary";

/** The account's favourite du'a; a guest account is created on the first save. */
export function useDuaFavorites() {
  const { isLoading: authLoading, loginGuest, session } = useAuth();
  const { t } = useI18n();
  const [favoriteKeys, setFavoriteKeys] = useState<Set<string>>(new Set());
  const [busyKeys, setBusyKeys] = useState<Set<string>>(new Set());
  const [errors, setErrors] = useState<Record<string, string>>({});

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

  const setKey = (key: string, active: boolean) =>
    setFavoriteKeys((current) => {
      const next = new Set(current);
      if (active) next.add(key);
      else next.delete(key);
      return next;
    });

  /** Saves the opposite state; resolves to the saved state, or null on failure. */
  const toggle = async (entry: DuaEntry): Promise<boolean | null> => {
    const key = duaEntryKey(entry);
    if (busyKeys.has(key)) return null;
    setBusyKeys((current) => new Set(current).add(key));
    setErrors((current) => ({ ...current, [key]: "" }));
    const wasFavorite = favoriteKeys.has(key);
    try {
      if (!api.getSession() && !(await loginGuest())) {
        throw new Error(t("dua.favoriteError"));
      }
      setKey(key, !wasFavorite);
      const saved = await api.setDuaFavorite(entry.collection, entry.source_number, !wasFavorite);
      setKey(key, saved.is_favorite);
      return saved.is_favorite;
    } catch (error) {
      setKey(key, wasFavorite);
      setErrors((current) => ({
        ...current,
        [key]: api.normalizeError(error) || t("dua.favoriteError"),
      }));
      return null;
    } finally {
      setBusyKeys((current) => {
        const next = new Set(current);
        next.delete(key);
        return next;
      });
    }
  };

  return {
    authLoading,
    isFavorite: (entry: DuaEntry) => favoriteKeys.has(duaEntryKey(entry)),
    isBusy: (entry: DuaEntry) => busyKeys.has(duaEntryKey(entry)) || authLoading,
    errorOf: (entry: DuaEntry) => errors[duaEntryKey(entry)] || "",
    toggle,
  };
}

export type DuaAudio = ReturnType<typeof useDuaAudio>;

/**
 * One audio element per list of du'a, as the app's standalone player: play
 * and pause, repeat one and speed for the du'a that is playing. It yields to
 * the global recitation player and back through the audio focus.
 */
export function useDuaAudio() {
  const [playerId] = useState(() => Symbol("dua-audio-player"));
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const [active, setActive] = useState<{ key: string; url: string; attempt: number } | null>(null);
  const [playing, setPlaying] = useState(false);
  const [loading, setLoading] = useState(false);
  const [failed, setFailed] = useState(false);
  const [repeat, setRepeat] = useState(false);
  const [speed, setSpeed] = useState(1);

  useEffect(() => {
    const audio = audioRef.current;
    if (!audio || active === null) return;
    return registerAudioPlayer(playerId, () => {
      audio.pause();
      setPlaying(false);
    });
  }, [active, playerId]);

  useEffect(() => {
    if (audioRef.current) audioRef.current.playbackRate = speed;
  }, [active, speed]);

  const load = (entry: DuaEntry) => {
    const url = entry.audio?.[0]?.url;
    if (!url) return;
    claimAudioFocus(playerId);
    setFailed(false);
    setPlaying(false);
    setLoading(true);
    setRepeat(false);
    setSpeed(1);
    setActive((current) => ({ key: duaEntryKey(entry), url, attempt: (current?.attempt ?? 0) + 1 }));
  };

  const toggle = (entry: DuaEntry) => {
    const audio = audioRef.current;
    if (active?.key !== duaEntryKey(entry) || failed || !audio) {
      load(entry);
      return;
    }
    if (audio.paused) {
      claimAudioFocus(playerId);
      setLoading(true);
      void audio.play().catch(() => {
        setLoading(false);
        setFailed(true);
      });
    } else {
      audio.pause();
    }
  };

  const fail = () => {
    setPlaying(false);
    setLoading(false);
    setFailed(true);
  };

  return {
    activeKey: active?.key ?? null,
    playing,
    loading,
    failed,
    repeat,
    speed,
    toggle,
    toggleRepeat: () => setRepeat((current) => !current),
    cycleSpeed: () => setSpeed((current) => nextPlaybackSpeed(current)),
    /** The element's key: a retry mounts a fresh element for the same file. */
    elementKey: active ? `${active.key}:${active.attempt}` : "idle",
    elementProps: {
      ref: audioRef,
      src: active?.url,
      autoPlay: true,
      preload: "none" as const,
      loop: repeat,
      onPlay: () => {
        claimAudioFocus(playerId);
        setPlaying(true);
      },
      onPlaying: () => setLoading(false),
      onWaiting: () => setLoading(true),
      onPause: () => {
        setPlaying(false);
        setLoading(false);
      },
      onEnded: () => {
        setPlaying(false);
        setLoading(false);
      },
      onError: fail,
    },
  };
}

// Loaded on the first press of "Share", and again after a failed load.
const loadShareDialog = () => lazy(() => import("./ContentShareDialog"));
let ContentShareDialog = loadShareDialog();
function reloadShareDialog() {
  ContentShareDialog = loadShareDialog();
}

/** A du'a as the app shares it, prepared when "Share" is pressed. */
type DuaShare = {
  entry: DuaEntry;
  title: string;
  url: string;
  load: () => ContentShareText;
};

/** "Share" draws the app's picture; without the dialog's code the text goes. */
export function useDuaShare(onStatus: (message: string) => void) {
  const { locale, t } = useI18n();
  const [share, setShare] = useState<DuaShare | null>(null);

  const open = (entry: DuaEntry) => {
    const content = duaShareText(entry, locale, t("duaShare.repetitions"));
    setShare({
      entry,
      title: duaShareTitle(entry, locale),
      url: new URL(localizedPath(locale, duaEntryPath(entry)), window.location.origin).href,
      load: () => content,
    });
  };

  const shareWithoutPicture = async ({ title, url, load }: DuaShare) => {
    reloadShareDialog();
    setShare(null);
    const result = await shareTextOnly(
      title,
      contentShareText(title, load(), t("contentShare.readInIqro"), url),
    );
    if (result === "shared" || result === "copied") {
      trackEvent("share", { content_type: "dua", method: result === "shared" ? "native" : "copy_text" });
    }
    if (result === "copied") onStatus(t("contentShare.textCopied"));
    if (result === "failed") onStatus(t("contentShare.shareError"));
  };

  const dialog = share ? (
    <ShareDialogBoundary key={duaEntryKey(share.entry)} onFailure={() => void shareWithoutPicture(share)}>
      <ContentShareDialog
        heading={t("duaShare.action")}
        title={share.title}
        url={share.url}
        fileName={`iqro-${share.entry.collection}-${share.entry.source_number}.png`}
        contentType="dua"
        previewAlt={t("duaShare.previewAlt", { number: share.entry.source_number })}
        load={share.load}
        onClose={() => setShare(null)}
      />
    </ShareDialogBoundary>
  ) : null;

  return { open, dialog };
}
