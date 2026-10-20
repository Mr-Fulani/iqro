"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import type { ReactNode } from "react";
import {
  SegmentedAudioPlayer,
} from "../components/SegmentedAudioPlayer";
import type { AudioPlaybackRequest } from "../components/SegmentedAudioPlayer";
import { PlayerBackdrop, PlayerBackgroundPicker } from "../components/PlayerBackground";
import { PlayerEqualizer } from "../components/PlayerEqualizer";
import { pauseAllAudioPlayers } from "./audio-focus";
import { useI18n } from "./i18n-context";
import {
  loadPlayerBackgroundId,
  playerBackgroundOptions,
  rememberPlayerBackgroundId,
  resolvePlayerBackground,
} from "./player-backgrounds";
import type { PlayerBackground } from "./player-backgrounds";
import { useHydrated } from "./use-hydrated";
import { localizedPath, stripLocalePrefix } from "./routing";

function sensitiveAudioSection(pathname: string): "quran" | "dua" | null {
  const route = stripLocalePrefix(pathname);
  if (route === "/quran" || route.startsWith("/quran/")) return "quran";
  if (route === "/dua" || route.startsWith("/dua/")) return "dua";
  return null;
}

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
const NO_REMOTE_BACKGROUNDS: PlayerBackground[] = [];

export function AudioPlayerProvider({
  children,
  playerBackgrounds = NO_REMOTE_BACKGROUNDS,
}: {
  children: ReactNode;
  playerBackgrounds?: PlayerBackground[];
}) {
  const pathname = usePathname();
  const previousAudioSection = useRef(sensitiveAudioSection(pathname));
  const { locale, t } = useI18n();
  const [request, setRequest] = useState<AudioPlaybackRequest | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [isBuffering, setIsBuffering] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const [reciterControls, setRegisteredReciterControls] =
    useState<AudioPlayerReciterControls | null>(null);
  const hydrated = useHydrated();
  const storedBackgroundId = useMemo(() => (hydrated ? loadPlayerBackgroundId() : null), [hydrated]);
  const [chosenBackgroundId, setChosenBackgroundId] = useState<string | null>(null);
  const backgroundOptions = useMemo(
    () => playerBackgroundOptions(playerBackgrounds),
    [playerBackgrounds],
  );
  const background = resolvePlayerBackground(
    chosenBackgroundId ?? storedBackgroundId,
    backgroundOptions,
  );

  const chooseBackground = useCallback((id: string) => {
    setChosenBackgroundId(id);
    rememberPlayerBackgroundId(id);
  }, []);

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

  useEffect(() => {
    const nextSection = sensitiveAudioSection(pathname);
    if (nextSection && nextSection !== previousAudioSection.current) {
      pauseAllAudioPlayers("navigation");
    }
    previousAudioSection.current = nextSection;
  }, [pathname]);

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
  const showBackground = expanded && background.image !== null;
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
            className={`global-audio-player-dock ${compact ? "is-compact" : "is-expanded"}${showReciterControls ? " has-reciter-controls" : ""}${showBackground ? " has-player-background" : ""}`}
            aria-label={t("player.dockAria")}
            data-testid="global-audio-player"
            data-player-background={expanded ? background.id : undefined}
          >
            {showBackground && <PlayerBackdrop background={background} />}
            <div className="global-audio-player-body">
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
                  {expanded && background.showEqualizer && (
                    <PlayerEqualizer playing={isPlaying && !isBuffering} />
                  )}
                  {expanded && (
                    <PlayerBackgroundPicker
                      options={backgroundOptions}
                      value={background.id}
                      onChange={chooseBackground}
                    />
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
                onBufferingChange={setIsBuffering}
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
            </div>
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
