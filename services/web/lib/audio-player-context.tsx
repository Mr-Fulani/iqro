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

  const showPlayer = pathname === "/audio" || request !== null;

  return (
    <AudioPlayerContext.Provider value={value}>
      {children}
      {showPlayer && (
        <>
          <div className="global-audio-player-spacer" aria-hidden="true" />
          <aside
            className="global-audio-player-dock"
            aria-label={t("player.dockAria")}
            data-testid="global-audio-player"
          >
            <div className="global-audio-player-head">
              <div>
                <p className="eyebrow">{t("player.dockEyebrow")}</p>
                <strong>{t("audio.playerTitle")}</strong>
              </div>
            </div>
            <SegmentedAudioPlayer
              request={request}
              className="audio-player-bar global-audio-player-bar"
              onPlayingChange={setIsPlaying}
              pauseOnNavigationKey={pathname}
              compact
            />
            {pathname !== "/audio" && (
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
