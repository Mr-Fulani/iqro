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
import { localizedPath, stripLocalePrefix } from "./routing";

type AudioPlayerContextValue = {
  request: AudioPlaybackRequest | null;
  isPlaying: boolean;
  startPlayback: (request: AudioPlaybackRequest) => void;
  clearPlayback: () => void;
  setReciterControls: (controls: AudioPlayerReciterControls | null) => void;
};

export type AudioPlayerReciterControls = {
  value: string;
  options: Array<{ value: string; label: string }>;
  disabled?: boolean;
  onChange: (value: string) => void;
};

const AudioPlayerContext = createContext<AudioPlayerContextValue | null>(null);

export function AudioPlayerProvider({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const { locale, t } = useI18n();
  const [request, setRequest] = useState<AudioPlaybackRequest | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const [reciterControls, setRegisteredReciterControls] =
    useState<AudioPlayerReciterControls | null>(null);

  const startPlayback = useCallback((nextRequest: AudioPlaybackRequest) => {
    setRequest(nextRequest);
  }, []);

  const clearPlayback = useCallback(() => {
    setRequest(null);
    setIsPlaying(false);
  }, []);

  const setReciterControls = useCallback((controls: AudioPlayerReciterControls | null) => {
    setRegisteredReciterControls(controls);
  }, []);

  const value = useMemo<AudioPlayerContextValue>(() => ({
    request,
    isPlaying,
    startPlayback,
    clearPlayback,
    setReciterControls,
  }), [clearPlayback, isPlaying, request, setReciterControls, startPlayback]);

  const isAudioPage = stripLocalePrefix(pathname) === "/audio";
  const compact = !expanded;
  const showPlayer = isAudioPage || request !== null;
  const showReciterControls = Boolean(reciterControls?.options.length);
  const modeActionLabel = expanded
    ? t("player.collapseWidget")
    : t("player.expandWidget");

  return (
    <AudioPlayerContext.Provider value={value}>
      {children}
      {showPlayer && (
        <>
          <div
            className={`global-audio-player-spacer ${compact ? "is-compact" : "is-expanded"}${showReciterControls ? " has-reciter-controls" : ""}`}
            aria-hidden="true"
          />
          <aside
            className={`global-audio-player-dock ${compact ? "is-compact" : "is-expanded"}${showReciterControls ? " has-reciter-controls" : ""}`}
            aria-label={t("player.dockAria")}
            data-testid="global-audio-player"
          >
            {(showReciterControls || expanded) && (
              <div className="global-audio-player-head">
                {showReciterControls && reciterControls && (
                  <select
                    className="global-audio-player-reciter-select"
                    value={reciterControls.value}
                    onChange={(event) => reciterControls.onChange(event.target.value)}
                    disabled={reciterControls.disabled}
                    aria-label={t("player.reciterSwitch")}
                  >
                    {reciterControls.options.map((option) => (
                      <option key={option.value} value={option.value}>{option.label}</option>
                    ))}
                  </select>
                )}
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
            )}
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
                    href={localizedPath(locale, "/audio")}
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
