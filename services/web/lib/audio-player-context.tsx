"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useReducer,
  useRef,
  useState,
} from "react";
import type { CSSProperties, ReactNode } from "react";
import {
  SegmentedAudioPlayer,
} from "../components/SegmentedAudioPlayer";
import type {
  AudioPlaybackRequest,
  MobilePlayerParts,
  MobilePlayerProps,
  ReciterControls,
} from "../components/SegmentedAudioPlayer";
import { PlayerBackdrop, PlayerBackgroundPicker } from "../components/PlayerBackground";
import { PlayerEqualizer } from "../components/PlayerEqualizer";
import { api } from "./api";
import { pauseAllAudioPlayers } from "./audio-focus";
import { useI18n } from "./i18n-context";
import { MOBILE_PLAYER_MEDIA_QUERY, adjacentSurah, miniPlayerReducer } from "./mini-player";
import {
  loadPlayerBackgroundId,
  playerBackgroundOptions,
  rememberPlayerBackgroundId,
  resolvePlayerBackground,
} from "./player-backgrounds";
import type { PlayerBackground } from "./player-backgrounds";
import { useHydrated } from "./use-hydrated";
import { useMediaQuery } from "./use-media-query";
import { useReducedMotion } from "./use-reduced-motion";
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

export type AudioPlayerReciterControls = ReciterControls;

const AudioPlayerContext = createContext<AudioPlayerContextValue | null>(null);
const NO_REMOTE_BACKGROUNDS: PlayerBackground[] = [];
// Pages number their own requests from zero; a surah change from the player stays apart.
const SURAH_REQUEST_ID_BASE = 1_000_000;
// The full player sinks out of view for this long before it unmounts (app/mobile.css).
const SHEET_CLOSE_MS = 260;

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

  // The phone player (as in the app) on the widths that show the bottom
  // navigation. Its parts are a separate chunk that desktop pages never load;
  // until it arrives, or if it fails, the desktop dock stays.
  const reduceMotion = useReducedMotion();
  const mobileWidth = useMediaQuery(MOBILE_PLAYER_MEDIA_QUERY);
  const [mobileParts, setMobileParts] = useState<MobilePlayerParts | null>(null);
  const [mobilePartsFailed, setMobilePartsFailed] = useState(false);
  const mobile = mobileWidth && mobileParts !== null;
  const [view, dispatchView] = useReducer(miniPlayerReducer, "bar");
  const [closing, setClosing] = useState(false);
  const [dragOffset, setDragOffset] = useState(0);
  const [surahChange, setSurahChange] = useState<{ busy: boolean; error: string | null }>({
    busy: false,
    error: null,
  });
  const surahAttemptRef = useRef(0);
  const surahRequestIdRef = useRef(SURAH_REQUEST_ID_BASE);
  const requestRef = useRef<AudioPlaybackRequest | null>(null);
  const isPlayingRef = useRef(false);
  const dockRef = useRef<HTMLDivElement>(null);
  const closeTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    requestRef.current = request;
  }, [request]);

  useEffect(() => {
    isPlayingRef.current = isPlaying;
  }, [isPlaying]);

  useEffect(() => {
    if (!mobileWidth || mobileParts || mobilePartsFailed) return;
    let cancelled = false;
    import("../components/MobileAudioPlayer")
      .then((module) => {
        if (!cancelled) setMobileParts(module.mobilePlayerParts);
      })
      .catch(() => {
        if (!cancelled) setMobilePartsFailed(true);
      });
    return () => {
      cancelled = true;
    };
  }, [mobileParts, mobilePartsFailed, mobileWidth]);

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

  // The app's full player is a pushed route: leaving the screen closes it.
  useEffect(() => {
    dispatchView({ type: "route-change" });
  }, [pathname]);

  useEffect(() => {
    dispatchView({ type: "request-change", hasRequest: request !== null });
    setSurahChange({ busy: false, error: null });
  }, [request]);

  const fullOpen = mobile && view === "full";
  const collapsed = mobile && view === "collapsed";

  const closeFull = useCallback(() => {
    if (closeTimerRef.current !== null) return;
    setDragOffset(0);
    if (reduceMotion) {
      dispatchView({ type: "close-full" });
      return;
    }
    setClosing(true);
    closeTimerRef.current = setTimeout(() => {
      closeTimerRef.current = null;
      setClosing(false);
      dispatchView({ type: "close-full" });
    }, SHEET_CLOSE_MS);
  }, [reduceMotion]);

  useEffect(() => () => {
    if (closeTimerRef.current !== null) clearTimeout(closeTimerRef.current);
  }, []);

  useEffect(() => {
    if (!fullOpen) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== "Escape" || event.defaultPrevented) return;
      event.preventDefault();
      closeFull();
    };
    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, [closeFull, fullOpen]);

  // Like the pushed route in the app: the page under the player is out of
  // reach and does not scroll; closing returns focus to the bar.
  useEffect(() => {
    if (!fullOpen) return;
    const container = document.querySelector<HTMLElement>(".app-container");
    container?.setAttribute("inert", "");
    document.documentElement.classList.add("is-mobile-player-open");
    const dock = dockRef.current;
    return () => {
      container?.removeAttribute("inert");
      document.documentElement.classList.remove("is-mobile-player-open");
      dock?.querySelector<HTMLElement>(".mobile-player-open")?.focus({ preventScroll: true });
    };
  }, [fullOpen]);

  // The previous or next surah of the same recording, as the app's mini player.
  const changeSurah = useCallback((direction: -1 | 1) => {
    const current = requestRef.current;
    const target = adjacentSurah(current?.track.surah_number, direction);
    if (!current || target === null) return;
    const attempt = ++surahAttemptRef.current;
    setSurahChange({ busy: true, error: null });
    api.getSurahPlayback(current.track.recitation_id, target)
      .then((playback) => {
        if (attempt !== surahAttemptRef.current || requestRef.current !== current) return;
        surahRequestIdRef.current += 1;
        setRequest({
          ...current,
          requestId: surahRequestIdRef.current,
          track: playback.track,
          segments: playback.segments || [],
          kind: "surah",
          startAyah: undefined,
          endAyah: undefined,
          title: t("common.surah", { surah: target }),
          autoPlay: isPlayingRef.current,
        });
      })
      .catch(() => {
        if (attempt !== surahAttemptRef.current) return;
        setSurahChange({ busy: false, error: t("player.surahUnavailable") });
      });
  }, [t]);

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
  const pictureShown = mobile ? fullOpen : expanded;
  const showBackground = pictureShown && background.image !== null;
  const modeActionLabel = expanded
    ? t("player.collapseWidget")
    : t("player.expandWidget");

  const mobileProps: MobilePlayerProps | undefined = mobile
    ? {
        parts: mobileParts,
        artworkUrl: request?.artworkUrl ?? null,
        buffering: isBuffering,
        onOpen: () => dispatchView({ type: "open-full" }),
        onCollapse: () => dispatchView({ type: "collapse" }),
        surah: { change: changeSurah, busy: surahChange.busy, error: surahChange.error },
        reciterControls: showReciterControls ? reciterControls : null,
        equalizer: { enabled: background.showEqualizer, playing: isPlaying && !isBuffering },
        background: { options: backgroundOptions, value: background, onChange: chooseBackground },
      }
    : undefined;
  const dockClassName = mobile
    ? `mobile-audio-player is-${view}${closing ? " is-closing" : ""}${showBackground ? " has-player-background" : ""}`
    : `global-audio-player-dock ${compact ? "is-compact" : "is-expanded"}${showReciterControls ? " has-reciter-controls" : ""}${showBackground ? " has-player-background" : ""}${mobilePartsFailed ? " is-fallback" : ""}`;
  const spacerClassName = mobile
    ? "global-audio-player-spacer is-mobile"
    : `global-audio-player-spacer ${compact ? "is-compact" : "is-expanded"}${showReciterControls ? " has-reciter-controls" : ""}`;
  const dragStyle: CSSProperties | undefined = dragOffset > 0
    ? { transform: `translateY(${dragOffset}px)`, transition: "none" }
    : undefined;

  // The dock, its body and the player keep their places in every presentation,
  // so switching between the desktop dock, the phone bar and the full player
  // never remounts the <audio> element.
  return (
    <AudioPlayerContext.Provider value={value}>
      {children}
      {showPlayer && (
        <>
          <div className={spacerClassName} aria-hidden="true" />
          <div
            ref={dockRef}
            className={dockClassName}
            style={dragStyle}
            role={fullOpen ? "dialog" : "region"}
            aria-modal={fullOpen ? true : undefined}
            aria-label={fullOpen ? t("player.nowPlaying") : t("player.dockAria")}
            data-testid={mobile ? "mobile-audio-player" : "global-audio-player"}
            data-player-background={pictureShown ? background.id : undefined}
          >
            {showBackground && <PlayerBackdrop background={background} />}
            <div className={mobile ? "mobile-player-sheet-body" : "global-audio-player-body"} inert={collapsed || undefined}>
              {mobile ? (
                fullOpen && mobileParts && (
                  <mobileParts.FullHeader
                    subtitle={request?.album ?? null}
                    onClose={closeFull}
                    onDragOffset={setDragOffset}
                    onDismiss={closeFull}
                  />
                )
              ) : (
                (showReciterControls || expanded) && (
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
                )
              )}
              <SegmentedAudioPlayer
                request={request}
                className={mobile ? "mobile-player-engine" : "audio-player-bar global-audio-player-bar"}
                onPlayingChange={setIsPlaying}
                onBufferingChange={setIsBuffering}
                compact={compact}
                presentation={mobile ? (fullOpen ? "full" : "mini") : "desktop"}
                mobile={mobileProps}
              />
              {!mobile && compact && (
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
            {collapsed && mobileParts && (
              <mobileParts.CollapsedButton playing={isPlaying} onExpand={() => dispatchView({ type: "expand" })} />
            )}
          </div>
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
