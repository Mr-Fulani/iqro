"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useState,
} from "react";
import type { ReactNode } from "react";
import {
  SegmentedAudioPlayer,
} from "../components/SegmentedAudioPlayer";
import type { AudioPlaybackRequest } from "../components/SegmentedAudioPlayer";
import { useI18n } from "./i18n-context";

type AudioPlayerContextValue = {
  request: AudioPlaybackRequest | null;
  isPlaying: boolean;
  startPlayback: (request: AudioPlaybackRequest) => void;
  clearPlayback: () => void;
};

const AudioPlayerContext = createContext<AudioPlayerContextValue | null>(null);

export function AudioPlayerProvider({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const { t } = useI18n();
  const [request, setRequest] = useState<AudioPlaybackRequest | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [expanded, setExpanded] = useState(false);

  const startPlayback = useCallback((nextRequest: AudioPlaybackRequest) => {
    setRequest(nextRequest);
  }, []);

  const clearPlayback = useCallback(() => {
    setRequest(null);
    setIsPlaying(false);
  }, []);

  const value = useMemo<AudioPlayerContextValue>(() => ({
    request,
    isPlaying,
    startPlayback,
    clearPlayback,
  }), [clearPlayback, isPlaying, request, startPlayback]);

  const isAudioPage = pathname === "/audio";
  const compact = !expanded;
  const showPlayer = isAudioPage || request !== null;
  const modeActionLabel = expanded
    ? t("player.collapseWidget")
    : t("player.expandWidget");

  return (
    <AudioPlayerContext.Provider value={value}>
      {children}
      {showPlayer && (
        <>
          <div
            className={`global-audio-player-spacer ${compact ? "is-compact" : "is-expanded"}`}
            aria-hidden="true"
          />
          <aside
            className={`global-audio-player-dock ${compact ? "is-compact" : "is-expanded"}`}
            aria-label={t("player.dockAria")}
            data-testid="global-audio-player"
          >
            <div className="global-audio-player-head">
              <div>
                <p className="eyebrow">{t("player.dockEyebrow")}</p>
                <strong>{t("audio.playerTitle")}</strong>
              </div>
              {expanded && (
                <button
                  className="btn btn-secondary btn-sm global-audio-player-size-toggle"
                  type="button"
                  aria-expanded="true"
                  aria-label={modeActionLabel}
                  title={modeActionLabel}
                  onClick={() => setExpanded(false)}
                >
                  <span aria-hidden="true">▾</span>
                  <span className="global-audio-player-size-toggle-label">{modeActionLabel}</span>
                </button>
              )}
            </div>
            <SegmentedAudioPlayer
              request={request}
              className="audio-player-bar global-audio-player-bar"
              onPlayingChange={setIsPlaying}
              pauseOnNavigationKey={pathname}
              compact={compact}
            />
            {compact && (
              <div className="global-audio-player-actions">
                <button
                  className="btn btn-secondary btn-sm global-audio-player-size-toggle"
                  type="button"
                  aria-expanded="false"
                  aria-label={modeActionLabel}
                  title={modeActionLabel}
                  onClick={() => setExpanded(true)}
                >
                  <span aria-hidden="true">⤢</span>
                  <span className="global-audio-player-size-toggle-label">{modeActionLabel}</span>
                </button>
                {!isAudioPage && (
                  <Link
                    href="/audio"
                    className="btn btn-secondary btn-sm global-audio-player-link"
                    aria-label={t("player.openAudio")}
                    title={t("player.openAudio")}
                  >
                    <span aria-hidden="true">🎵</span>
                    <span className="global-audio-player-link-label">{t("player.openAudio")}</span>
                  </Link>
                )}
              </div>
            )}
          </aside>
        </>
      )}
    </AudioPlayerContext.Provider>
  );
}

export function useAudioPlayer(): AudioPlayerContextValue {
  const context = useContext(AudioPlayerContext);
  if (!context) {
    throw new Error("useAudioPlayer must be used within AudioPlayerProvider");
  }
  return context;
}
