"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { ComponentType, ReactNode } from "react";
import { createPortal } from "react-dom";
import { AudioTrack, AyahAudioSegment } from "../lib/api";
import { claimAudioFocus, registerAudioPlayer } from "../lib/audio-focus";
import { useI18n } from "../lib/i18n-context";
import { MessageKey, TranslationVariables } from "../lib/i18n";
import { formatClock } from "../lib/audio-content";
import type { ListeningQueue } from "../lib/listening-queue";
import { seekPositionMs } from "../lib/mini-player";
import type { PlayerBackground } from "../lib/player-backgrounds";
import type { ListeningQueueControls } from "../lib/use-listening-queue";

export type AudioPlaybackRequest = {
  requestId: number;
  track: AudioTrack;
  segments: AyahAudioSegment[];
  kind: "surah" | "ayah" | "range";
  startAyah?: number;
  endAyah?: number;
  title: string;
  artist: string;
  album?: string;
  autoPlay?: boolean;
  /** The reciter's portrait, shown by the phone player. */
  artworkUrl?: string | null;
  /** Where a surah resumes, as the saved place left it. */
  startPositionMs?: number;
  /** The Audio tab's recordings the global player moves through. */
  queue?: ListeningQueue;
};

export type RepeatMode = "off" | "ayah" | "selection";
export type AudioPlaybackSettings = {
  repeatMode: RepeatMode;
  playbackRate: number;
};
export type AudioPlayerControlRequest = {
  requestId: number;
  action: "toggle-playback" | "toggle-ayah-repeat" | "cycle-speed";
};
type SleepMode = "off" | "ayah" | "5" | "15" | "30" | "60";

export type ReciterControls = {
  value: string;
  options: Array<{ value: string; label: string }>;
  disabled?: boolean;
  onChange: (value: string) => void;
};

export type MobilePlayerSetting = {
  key: "speed" | "sleep" | "repeat" | "pause";
  label: string;
  control: ReactNode;
  note?: string | null;
};

/** What the phone parts read from the player; every handler is the desktop one. */
export type MobilePlayerEngine = {
  presentation: "mini" | "full";
  request: AudioPlaybackRequest | null;
  plan: { startMs: number; endMs: number } | null;
  activeAyah: AyahAudioSegment | null;
  isPlaying: boolean;
  statusLabel: string;
  error: string | null;
  title: string;
  /** The mounted <audio> element. */
  audio: HTMLAudioElement | null;
  togglePlayback: () => void;
  seekBy: (seconds: number) => void;
  seekToMs: (milliseconds: number) => void;
  settings: MobilePlayerSetting[];
  range: { start: ReactNode; end: ReactNode; play: () => void; disabled: boolean; label: string | null };
};

export type MobilePlayerSurahControls = {
  change: (direction: -1 | 1) => void;
  busy: boolean;
  error: string | null;
  /** Where the previous and next buttons go; null disables them. */
  previous: number | null;
  next: number | null;
};

export type MobilePlayerProps = {
  // Loaded on phone widths only (components/MobileAudioPlayer.tsx).
  parts: MobilePlayerParts | null;
  artworkUrl: string | null;
  buffering: boolean;
  /** The full player's controls are hidden by a tap on its body; the parts go inert. */
  controlsHidden: boolean;
  onOpen: () => void;
  onCollapse: () => void;
  surah: MobilePlayerSurahControls;
  /** The Audio tab's queue, when the request carries one. */
  queue: ListeningQueueControls | null;
  reciterControls: ReciterControls | null;
  equalizer: { enabled: boolean; playing: boolean };
  background: { options: readonly PlayerBackground[]; value: PlayerBackground; onChange: (id: string) => void };
};

export type MobilePlayerPartProps = { engine: MobilePlayerEngine; mobile: MobilePlayerProps };
export type MobilePlayerHeaderProps = {
  subtitle: string | null;
  hidden: boolean;
  onClose: () => void;
  onDragOffset: (offsetPx: number) => void;
  onDismiss: () => void;
};
export type MobilePlayerParts = {
  Summary: ComponentType<MobilePlayerPartProps>;
  Transport: ComponentType<MobilePlayerPartProps>;
  Options: ComponentType<MobilePlayerPartProps>;
  FullHeader: ComponentType<MobilePlayerHeaderProps>;
  CollapsedButton: ComponentType<{ playing: boolean; onExpand: () => void }>;
};

type RuntimePlan = {
  kind: AudioPlaybackRequest["kind"];
  startIndex: number;
  endIndex: number;
  currentIndex: number;
  startMs: number;
  endMs: number;
};

type StatusMessage = {
  key: MessageKey;
  variables?: TranslationVariables;
};

type SegmentedAudioPlayerProps = {
  request: AudioPlaybackRequest | null;
  className?: string;
  onActiveAyahChange?: (ayahKey: string | null) => void;
  onPlayingChange?: (isPlaying: boolean) => void;
  // True while playback waits for data, until the sound resumes or pauses.
  onBufferingChange?: (isBuffering: boolean) => void;
  onSettingsChange?: (settings: AudioPlaybackSettings) => void;
  /** The plan ended by itself; true when a following request takes over. */
  onPlanEnd?: () => boolean;
  /** The lock screen's previous/next track; without it they move by ayah. */
  onTrackSkip?: (direction: -1 | 1) => void;
  /** The playing position, a few times a second. */
  onPositionChange?: (positionMs: number) => void;
  /** A surah's title in place of the request's, such as "2 · Al-Baqara" once the names arrive. */
  displayTitle?: string | null;
  controlRequest?: AudioPlayerControlRequest | null;
  pauseOnNavigationKey?: string;
  compact?: boolean;
  /** The phone bar or full player instead of the desktop markup. */
  presentation?: "desktop" | "mini" | "full";
  mobile?: MobilePlayerProps;
  readerControls?: {
    container: HTMLElement | null;
    ayahKey: string | null;
    artist: string;
    loading: boolean;
    available: boolean;
    error: string | null;
    onPlayAyah: () => void;
  };
};

const SPEED_OPTIONS = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];
const PAUSE_OPTIONS = [0, 500, 1000, 2000, 3000, 5000];

function sortedSegments(segments: AyahAudioSegment[]): AyahAudioSegment[] {
  return [...segments].sort((left, right) => {
    if (left.start_ms !== right.start_ms) return left.start_ms - right.start_ms;
    return left.ayah_number - right.ayah_number;
  });
}

function buildPlan(
  request: AudioPlaybackRequest,
  segments: AyahAudioSegment[],
  startAyah = request.startAyah,
  endAyah = request.endAyah,
  kind = request.kind,
): RuntimePlan {
  if (segments.length === 0) {
    return {
      kind,
      startIndex: -1,
      endIndex: -1,
      currentIndex: -1,
      startMs: 0,
      endMs: request.track.duration_ms,
    };
  }

  const fallbackStart = segments[0].ayah_number;
  const fallbackEnd = segments[segments.length - 1].ayah_number;
  const normalizedStart = Math.min(startAyah ?? fallbackStart, endAyah ?? fallbackEnd);
  const normalizedEnd = Math.max(startAyah ?? fallbackStart, endAyah ?? fallbackEnd);
  const startIndex = Math.max(
    0,
    segments.findIndex((segment) => segment.ayah_number >= normalizedStart),
  );
  const lastMatchingIndex = segments.findLastIndex(
    (segment) => segment.ayah_number <= normalizedEnd,
  );
  const endIndex = Math.max(startIndex, lastMatchingIndex);

  return {
    kind,
    startIndex,
    endIndex,
    currentIndex: startIndex,
    startMs: segments[startIndex].start_ms,
    endMs: segments[endIndex].end_ms,
  };
}

function formatRemaining(milliseconds: number): string {
  // Rounded up: the last second of a timer reads 0:01, not 0:00.
  return formatClock(Math.ceil(milliseconds / 1000) * 1000);
}

export function SegmentedAudioPlayer({
  request,
  className = "",
  onActiveAyahChange,
  onPlayingChange,
  onBufferingChange,
  onSettingsChange,
  onPlanEnd,
  onTrackSkip,
  onPositionChange,
  displayTitle,
  controlRequest,
  pauseOnNavigationKey,
  compact = false,
  presentation = "desktop",
  mobile,
  readerControls,
}: SegmentedAudioPlayerProps) {
  const { t, formatNumber } = useI18n();
  const [audioPlayerId] = useState(() => Symbol("segmented-audio-player"));
  const readerControlsRef = useRef(readerControls);
  useEffect(() => { readerControlsRef.current = readerControls; }, [readerControls]);
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const requestRef = useRef<AudioPlaybackRequest | null>(null);
  const segmentsRef = useRef<AyahAudioSegment[]>([]);
  const planRef = useRef<RuntimePlan | null>(null);
  const playWhenReadyRef = useRef(false);
  const mediaReadyRef = useRef(false);
  const playAttemptRef = useRef(0);
  const hasStartedRef = useRef(false);
  const boundaryTransitionRef = useRef(false);
  const transitionTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const repeatModeRef = useRef<RepeatMode>("off");
  const playbackRateRef = useRef(1);
  const pauseMsRef = useRef(0);
  const sleepModeRef = useRef<SleepMode>("off");
  const pendingPauseStatusRef = useRef<StatusMessage | null>(null);
  const onActiveAyahChangeRef = useRef(onActiveAyahChange);
  const onPlayingChangeRef = useRef(onPlayingChange);
  const onBufferingChangeRef = useRef(onBufferingChange);
  const onPlanEndRef = useRef(onPlanEnd);
  const onTrackSkipRef = useRef(onTrackSkip);
  const onPositionChangeRef = useRef(onPositionChange);
  const navigationKeyRef = useRef(pauseOnNavigationKey);
  const handledControlRequestRef = useRef<number | null>(null);

  const [activeRequest, setActiveRequest] = useState<AudioPlaybackRequest | null>(null);
  const [activePlan, setActivePlan] = useState<RuntimePlan | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [status, setStatus] = useState<StatusMessage>({ key: "player.status.idle" });
  const [error, setError] = useState<string | null>(null);
  const [repeatMode, setRepeatMode] = useState<RepeatMode>("off");
  const [playbackRate, setPlaybackRate] = useState(1);
  const [pauseMs, setPauseMs] = useState(0);
  const [sleepMode, setSleepMode] = useState<SleepMode>("off");
  const [sleepDeadline, setSleepDeadline] = useState<number | null>(null);
  const [sleepRemainingMs, setSleepRemainingMs] = useState<number | null>(null);
  const [rangeStartAyah, setRangeStartAyah] = useState<number | null>(null);
  const [rangeEndAyah, setRangeEndAyah] = useState<number | null>(null);
  const [activeAyah, setActiveAyah] = useState<AyahAudioSegment | null>(null);
  const [settingsOpen, setSettingsOpen] = useState(!compact);
  // The element as state too: the phone seek bar listens to it from an effect.
  const [audioElement, setAudioElement] = useState<HTMLAudioElement | null>(null);
  const attachAudio = useCallback((node: HTMLAudioElement | null) => {
    audioRef.current = node;
    setAudioElement(node);
  }, []);

  useEffect(() => {
    onActiveAyahChangeRef.current = onActiveAyahChange;
  }, [onActiveAyahChange]);

  useEffect(() => {
    onPlayingChangeRef.current = onPlayingChange;
  }, [onPlayingChange]);

  useEffect(() => {
    onBufferingChangeRef.current = onBufferingChange;
  }, [onBufferingChange]);

  useEffect(() => {
    onPlanEndRef.current = onPlanEnd;
    onTrackSkipRef.current = onTrackSkip;
    onPositionChangeRef.current = onPositionChange;
  }, [onPlanEnd, onPositionChange, onTrackSkip]);

  useEffect(() => {
    if (compact) {
      setSettingsOpen(false);
      return;
    }
    const mediaQuery = window.matchMedia("(max-width: 640px)");
    const syncForViewport = () => setSettingsOpen(!mediaQuery.matches);
    syncForViewport();
    mediaQuery.addEventListener("change", syncForViewport);
    return () => mediaQuery.removeEventListener("change", syncForViewport);
  }, [compact]);

  const updateActiveSegment = useCallback((
    segment: AyahAudioSegment | null,
    notifyParent = true,
  ) => {
    setActiveAyah(segment);
    if (notifyParent) {
      onActiveAyahChangeRef.current?.(
        segment ? `${segment.surah_number}:${segment.ayah_number}` : null,
      );
    }
  }, []);

  const clearTransition = useCallback(() => {
    if (transitionTimerRef.current !== null) {
      clearTimeout(transitionTimerRef.current);
      transitionTimerRef.current = null;
    }
    boundaryTransitionRef.current = false;
  }, []);

  const updateMediaPosition = useCallback(() => {
    const audio = audioRef.current;
    if (!audio || !("mediaSession" in navigator)) return;
    const duration = Number.isFinite(audio.duration) && audio.duration > 0
      ? audio.duration
      : (requestRef.current?.track.duration_ms || 0) / 1000;
    if (duration <= 0) return;
    const position = Math.min(Math.max(audio.currentTime, 0), duration);
    try {
      navigator.mediaSession.setPositionState({
        duration,
        playbackRate: audio.playbackRate,
        position,
      });
    } catch {
      // Some browsers expose Media Session but reject incomplete position data.
    }
  }, []);

  const attemptPlay = useCallback(() => {
    const audio = audioRef.current;
    if (!audio) return;
    claimAudioFocus(audioPlayerId);
    const attempt = ++playAttemptRef.current;
    void audio.play().catch((reason: unknown) => {
      // A newer selection, pause or load cancels the old promise normally.
      if (attempt !== playAttemptRef.current || (reason instanceof DOMException && reason.name === "AbortError")) return;
      setIsPlaying(false);
      onPlayingChangeRef.current?.(false);
      setStatus({ key: "player.status.resumePrompt" });
      setError(t(reason instanceof DOMException && reason.name === "NotAllowedError"
        ? "player.autoplayBlocked" : "player.playbackFailed"));
    });
  }, [audioPlayerId, t]);

  const setPlanPosition = useCallback((
    plan: RuntimePlan,
    index: number,
    notifyParent = true,
  ) => {
    const audio = audioRef.current;
    if (!audio) return;
    const segment = index >= 0 ? segmentsRef.current[index] : null;
    const positionMs = segment?.start_ms ?? plan.startMs;
    plan.currentIndex = index;
    planRef.current = { ...plan };
    setActivePlan({ ...plan });
    audio.currentTime = positionMs / 1000;
    updateActiveSegment(segment, notifyParent);
    updateMediaPosition();
  }, [updateActiveSegment, updateMediaPosition]);

  // A saved place resumes inside the surah; the plan's ayah follows on play.
  const applyStartPosition = useCallback(() => {
    const audio = audioRef.current;
    const plan = planRef.current;
    const startMs = requestRef.current?.startPositionMs;
    if (!audio || !plan || !startMs || plan.kind !== "surah") return;
    if (startMs <= plan.startMs || startMs >= plan.endMs - 500) return;
    audio.currentTime = startMs / 1000;
    const index = segmentsRef.current.findIndex((segment) => startMs >= segment.start_ms && startMs < segment.end_ms);
    if (index >= plan.startIndex && index <= plan.endIndex) {
      plan.currentIndex = index;
      planRef.current = { ...plan };
      setActivePlan({ ...plan });
      updateActiveSegment(segmentsRef.current[index], false);
    }
    updateMediaPosition();
  }, [updateActiveSegment, updateMediaPosition]);

  const stopAtCurrentPosition = useCallback((nextStatus: StatusMessage) => {
    playAttemptRef.current += 1;
    clearTransition();
    playWhenReadyRef.current = false;
    const audio = audioRef.current;
    pendingPauseStatusRef.current = nextStatus;
    if (audio) audio.pause();
    setIsPlaying(false);
    onPlayingChangeRef.current?.(false);
    setStatus(nextStatus);
    if ("mediaSession" in navigator) navigator.mediaSession.playbackState = "paused";
    updateMediaPosition();
  }, [clearTransition, updateMediaPosition]);

  useEffect(
    () => registerAudioPlayer(audioPlayerId, (reason) => {
      if (!requestRef.current) return;
      stopAtCurrentPosition({
        key: reason === "navigation"
          ? "player.status.pausedNavigation"
          : "player.status.paused",
      });
      onActiveAyahChangeRef.current?.(null);
    }),
    [audioPlayerId, stopAtCurrentPosition],
  );

  useEffect(() => {
    if (navigationKeyRef.current === pauseOnNavigationKey) return;
    navigationKeyRef.current = pauseOnNavigationKey;
    if (requestRef.current) {
      stopAtCurrentPosition({ key: "player.status.pausedNavigation" });
      onActiveAyahChangeRef.current?.(null);
    }
  }, [pauseOnNavigationKey, stopAtCurrentPosition]);

  const finishPlayback = useCallback((nextStatus: StatusMessage) => {
    playAttemptRef.current += 1;
    playWhenReadyRef.current = false;
    clearTransition();
    const audio = audioRef.current;
    const plan = planRef.current;
    if (audio) {
      pendingPauseStatusRef.current = nextStatus;
      audio.pause();
      if (plan) audio.currentTime = plan.endMs / 1000;
    }
    setIsPlaying(false);
    onPlayingChangeRef.current?.(false);
    setStatus(nextStatus);
    updateActiveSegment(null);
    if ("mediaSession" in navigator) navigator.mediaSession.playbackState = "none";
    updateMediaPosition();
  }, [clearTransition, updateActiveSegment, updateMediaPosition]);

  const startPlan = useCallback((nextPlan: RuntimePlan, autoPlay: boolean) => {
    clearTransition();
    planRef.current = { ...nextPlan };
    setActivePlan({ ...nextPlan });
    setError(null);
    setPlanPosition(nextPlan, nextPlan.currentIndex, autoPlay);
    if (autoPlay) {
      setStatus({ key: "player.status.starting" });
      attemptPlay();
    } else {
      setStatus({ key: "player.status.ready" });
      onActiveAyahChangeRef.current?.(null);
    }
  }, [attemptPlay, clearTransition, setPlanPosition]);

  useEffect(() => {
    clearTransition();
    const audio = audioRef.current;
    playAttemptRef.current += 1;
    playWhenReadyRef.current = false;
    audio?.pause();
    if (!request) {
      requestRef.current = null;
      segmentsRef.current = [];
      planRef.current = null;
      setActiveRequest(null);
      setActivePlan(null);
      hasStartedRef.current = false;
      setRangeStartAyah(null);
      setRangeEndAyah(null);
      setStatus({ key: "player.status.idle" });
      updateActiveSegment(null);
      if (audio) {
        mediaReadyRef.current = false;
        audio.removeAttribute("src");
        audio.load();
      }
      return;
    }

    const nextSegments = sortedSegments(request.segments);
    const nextPlan = buildPlan(request, nextSegments);
    requestRef.current = request;
    segmentsRef.current = nextSegments;
    planRef.current = nextPlan;
    setActiveRequest(request);
    setActivePlan(nextPlan);
    hasStartedRef.current = false;
    setRangeStartAyah(request.startAyah ?? nextSegments[0]?.ayah_number ?? null);
    setRangeEndAyah(request.endAyah ?? nextSegments[nextSegments.length - 1]?.ayah_number ?? null);
    setError(null);
    playWhenReadyRef.current = request.autoPlay !== false;

    if (!audio) return;
    audio.playbackRate = playbackRateRef.current;
    const sourceChanged = audio.getAttribute("src") !== request.track.asset.url;
    if (sourceChanged) {
      mediaReadyRef.current = false;
      audio.src = request.track.asset.url;
      audio.load();
      return;
    }
    if (!mediaReadyRef.current) return;
    startPlan(nextPlan, playWhenReadyRef.current);
    applyStartPosition();
    playWhenReadyRef.current = false;
  }, [applyStartPosition, clearTransition, request, startPlan, updateActiveSegment]);

  useEffect(() => {
    playbackRateRef.current = playbackRate;
    const audio = audioRef.current;
    if (audio) audio.playbackRate = playbackRate;
    updateMediaPosition();
  }, [playbackRate, updateMediaPosition]);

  useEffect(() => {
    repeatModeRef.current = repeatMode;
  }, [repeatMode]);

  useEffect(() => {
    onSettingsChange?.({ repeatMode, playbackRate });
  }, [onSettingsChange, playbackRate, repeatMode]);

  useEffect(() => {
    pauseMsRef.current = pauseMs;
  }, [pauseMs]);

  useEffect(() => {
    sleepModeRef.current = sleepMode;
  }, [sleepMode]);

  useEffect(() => {
    if (sleepDeadline === null) {
      setSleepRemainingMs(null);
      return;
    }

    const updateRemaining = () => {
      const remaining = Math.max(0, sleepDeadline - Date.now());
      setSleepRemainingMs(remaining);
      if (remaining === 0) {
        setSleepDeadline(null);
        setSleepMode("off");
        sleepModeRef.current = "off";
        stopAtCurrentPosition({ key: "player.status.sleepPosition" });
      }
    };
    updateRemaining();
    const interval = window.setInterval(updateRemaining, 1000);
    return () => window.clearInterval(interval);
  }, [sleepDeadline, stopAtCurrentPosition]);

  const scheduleBoundaryTransition = useCallback((nextIndex: number) => {
    const plan = planRef.current;
    const audio = audioRef.current;
    if (!plan || !audio || boundaryTransitionRef.current) return;
    boundaryTransitionRef.current = true;
    audio.pause();
    setIsPlaying(false);
    onPlayingChangeRef.current?.(false);

    const delay = pauseMsRef.current;
    setStatus(delay > 0
      ? {
          key: "player.status.pauseBetween",
          variables: {
            pause: t("player.seconds", { value: formatNumber(delay / 1000) }),
          },
        }
      : { key: "player.status.moving" });
    transitionTimerRef.current = setTimeout(() => {
      transitionTimerRef.current = null;
      boundaryTransitionRef.current = false;
      const currentPlan = planRef.current;
      if (!currentPlan) return;
      setPlanPosition(currentPlan, nextIndex);
      attemptPlay();
    }, delay);
  }, [attemptPlay, formatNumber, setPlanPosition, t]);

  const handleBoundary = useCallback(() => {
    const plan = planRef.current;
    if (!plan || boundaryTransitionRef.current) return;

    if (sleepModeRef.current === "ayah") {
      setSleepMode("off");
      sleepModeRef.current = "off";
      stopAtCurrentPosition({ key: "player.status.sleepAyah" });
      updateActiveSegment(null);
      return;
    }

    if (repeatModeRef.current === "ayah" && plan.currentIndex >= 0) {
      scheduleBoundaryTransition(plan.currentIndex);
      return;
    }

    if (plan.currentIndex >= 0 && plan.currentIndex < plan.endIndex) {
      scheduleBoundaryTransition(plan.currentIndex + 1);
      return;
    }

    if (repeatModeRef.current === "selection") {
      scheduleBoundaryTransition(plan.startIndex);
      return;
    }

    if (onPlanEndRef.current?.()) {
      // The queue's next surah replaces this request; until then the sound rests.
      const nextStatus: StatusMessage = { key: "player.status.nextSurah" };
      playAttemptRef.current += 1;
      clearTransition();
      playWhenReadyRef.current = false;
      pendingPauseStatusRef.current = nextStatus;
      audioRef.current?.pause();
      setStatus(nextStatus);
      return;
    }

    finishPlayback({ key: "player.status.finished" });
  }, [clearTransition, finishPlayback, scheduleBoundaryTransition, stopAtCurrentPosition, updateActiveSegment]);

  const handleTimeUpdate = useCallback(() => {
    const audio = audioRef.current;
    const plan = planRef.current;
    if (!audio || !plan || audio.seeking || !hasStartedRef.current || boundaryTransitionRef.current) return;
    const currentMs = Math.round(audio.currentTime * 1000);
    onPositionChangeRef.current?.(currentMs);

    if (plan.currentIndex < 0) {
      if (currentMs >= plan.endMs - 40) handleBoundary();
      updateMediaPosition();
      return;
    }

    const segments = segmentsRef.current;
    const currentSegment = segments[plan.currentIndex];
    const mustHandleEveryBoundary =
      pauseMsRef.current > 0 ||
      repeatModeRef.current === "ayah" ||
      sleepModeRef.current === "ayah";

    if (
      currentSegment &&
      currentMs >= currentSegment.end_ms - 40 &&
      (mustHandleEveryBoundary || plan.currentIndex === plan.endIndex)
    ) {
      handleBoundary();
      return;
    }

    const nextIndex = segments.findIndex((segment, index) => (
      index >= plan.startIndex &&
      index <= plan.endIndex &&
      currentMs >= segment.start_ms &&
      currentMs < segment.end_ms
    ));
    if (nextIndex >= 0 && nextIndex !== plan.currentIndex) {
      plan.currentIndex = nextIndex;
      planRef.current = { ...plan };
      setActivePlan({ ...plan });
      updateActiveSegment(segments[nextIndex]);
    }
    updateMediaPosition();
  }, [handleBoundary, updateActiveSegment, updateMediaPosition]);

  const handleLoadedMetadata = useCallback(() => {
    const audio = audioRef.current;
    const plan = planRef.current;
    if (!audio || !plan) return;
    mediaReadyRef.current = true;
    audio.playbackRate = playbackRateRef.current;
    const shouldPlay = playWhenReadyRef.current;
    playWhenReadyRef.current = false;
    setPlanPosition(plan, plan.currentIndex, shouldPlay);
    applyStartPosition();
    if (shouldPlay) {
      setStatus({ key: "player.status.starting" });
      attemptPlay();
    } else {
      setStatus({ key: "player.status.ready" });
      onActiveAyahChangeRef.current?.(null);
    }
  }, [applyStartPosition, attemptPlay, setPlanPosition]);

  const resumePlayback = useCallback(() => {
    const audio = audioRef.current;
    const plan = planRef.current;
    const reader = readerControlsRef.current;
    const segment = plan ? segmentsRef.current[plan.currentIndex] : undefined;
    if (reader && (!reader.ayahKey || plan?.kind !== "ayah" || plan.startIndex !== plan.endIndex
      || !segment || `${segment.surah_number}:${segment.ayah_number}` !== reader.ayahKey)) {
      if (reader.ayahKey && reader.available && !reader.loading) reader.onPlayAyah();
      return;
    }
    if (!audio || !plan) return;
    clearTransition();
    if (!mediaReadyRef.current) {
      playWhenReadyRef.current = true;
      setError(null);
      attemptPlay();
      return;
    }
    const currentMs = audio.currentTime * 1000;
    if (currentMs >= plan.endMs - 40 || currentMs < plan.startMs - 40) {
      setPlanPosition(plan, plan.startIndex);
    }
    setError(null);
    setStatus({ key: "player.status.resuming" });
    attemptPlay();
  }, [attemptPlay, clearTransition, setPlanPosition]);

  const moveToAdjacentAyah = useCallback((offset: -1 | 1) => {
    if (readerControlsRef.current) {
      resumePlayback();
      return;
    }
    const plan = planRef.current;
    if (!plan || plan.currentIndex < 0) return;
    const nextIndex = Math.min(
      plan.endIndex,
      Math.max(plan.startIndex, plan.currentIndex + offset),
    );
    clearTransition();
    setPlanPosition(plan, nextIndex);
    attemptPlay();
  }, [attemptPlay, clearTransition, resumePlayback, setPlanPosition]);

  const seekBy = useCallback((seconds: number) => {
    const audio = audioRef.current;
    const plan = planRef.current;
    if (!audio || !plan) return;
    const nextMs = Math.min(plan.endMs, Math.max(plan.startMs, audio.currentTime * 1000 + seconds * 1000));
    audio.currentTime = nextMs / 1000;
    handleTimeUpdate();
  }, [handleTimeUpdate]);

  const seekToMs = useCallback((milliseconds: number) => {
    const audio = audioRef.current;
    const plan = planRef.current;
    if (!audio || !plan) return;
    audio.currentTime = seekPositionMs(milliseconds, plan.startMs, plan.endMs) / 1000;
    handleTimeUpdate();
  }, [handleTimeUpdate]);

  const togglePlayback = useCallback(() => {
    if (isPlaying) stopAtCurrentPosition({ key: "player.status.paused" });
    else resumePlayback();
  }, [isPlaying, resumePlayback, stopAtCurrentPosition]);

  useEffect(() => {
    if (
      !controlRequest ||
      handledControlRequestRef.current === controlRequest.requestId
    ) {
      return;
    }
    handledControlRequestRef.current = controlRequest.requestId;

    if (controlRequest.action === "toggle-playback") {
      if (isPlaying) {
        stopAtCurrentPosition({ key: "player.status.paused" });
      } else {
        resumePlayback();
      }
      return;
    }
    if (controlRequest.action === "toggle-ayah-repeat") {
      setRepeatMode((current) => current === "ayah" ? "off" : "ayah");
      return;
    }
    setPlaybackRate((current) => {
      const currentIndex = SPEED_OPTIONS.indexOf(current);
      return SPEED_OPTIONS[(currentIndex + 1) % SPEED_OPTIONS.length];
    });
  }, [controlRequest, isPlaying, resumePlayback, stopAtCurrentPosition]);

  useEffect(() => {
    if (!("mediaSession" in navigator) || !activeRequest) return;
    navigator.mediaSession.metadata = new MediaMetadata({
      title: activeRequest.title,
      artist: activeRequest.artist,
      album: activeRequest.album || "Quran Platform",
    });

    const actions: Array<MediaSessionAction> = [
      "play",
      "pause",
      "stop",
      "seekbackward",
      "seekforward",
      "previoustrack",
      "nexttrack",
    ];
    const handlers: Partial<Record<MediaSessionAction, MediaSessionActionHandler>> = {
      play: resumePlayback,
      pause: () => stopAtCurrentPosition({ key: "player.status.paused" }),
      stop: () => finishPlayback({ key: "player.status.stopped" }),
      seekbackward: (details) => seekBy(-(details.seekOffset || 10)),
      seekforward: (details) => seekBy(details.seekOffset || 10),
      previoustrack: () => onTrackSkipRef.current ? onTrackSkipRef.current(-1) : moveToAdjacentAyah(-1),
      nexttrack: () => onTrackSkipRef.current ? onTrackSkipRef.current(1) : moveToAdjacentAyah(1),
    };

    for (const action of actions) {
      try {
        navigator.mediaSession.setActionHandler(action, handlers[action] || null);
      } catch {
        // Browser implementations expose different subsets of Media Session actions.
      }
    }
    updateMediaPosition();

    return () => {
      for (const action of actions) {
        try {
          navigator.mediaSession.setActionHandler(action, null);
        } catch {
          // Ignore unsupported actions during cleanup as well.
        }
      }
    };
  }, [
    activeRequest,
    finishPlayback,
    moveToAdjacentAyah,
    resumePlayback,
    seekBy,
    stopAtCurrentPosition,
    updateMediaPosition,
  ]);

  // The lock screen names the surah as the player does, once its name is known.
  useEffect(() => {
    if (!("mediaSession" in navigator) || !activeRequest || !displayTitle) return;
    navigator.mediaSession.metadata = new MediaMetadata({
      title: displayTitle,
      artist: activeRequest.artist,
      album: activeRequest.album || "Quran Platform",
    });
  }, [activeRequest, displayTitle]);

  useEffect(() => () => {
    playAttemptRef.current += 1;
    clearTransition();
  }, [clearTransition]);

  const availableAyahs = useMemo(
    () => [...new Set((activeRequest?.segments || []).map((segment) => segment.ayah_number))],
    [activeRequest],
  );
  const planStartMs = activePlan?.startMs ?? null;
  const planEndMs = activePlan?.endMs ?? null;
  const planBounds = useMemo(
    () => (planStartMs === null || planEndMs === null ? null : { startMs: planStartMs, endMs: planEndMs }),
    [planEndMs, planStartMs],
  );

  const startRange = () => {
    if (!activeRequest || rangeStartAyah === null || rangeEndAyah === null) return;
    const nextPlan = buildPlan(
      activeRequest,
      segmentsRef.current,
      rangeStartAyah,
      rangeEndAyah,
      "range",
    );
    startPlan(nextPlan, true);
  };

  const handleSleepModeChange = (nextMode: SleepMode) => {
    setSleepMode(nextMode);
    sleepModeRef.current = nextMode;
    if (["5", "15", "30", "60"].includes(nextMode)) {
      const minutes = Number(nextMode);
      setSleepDeadline(Date.now() + minutes * 60_000);
      return;
    }
    setSleepDeadline(null);
  };

  const currentSelectionLabel = activePlan?.kind === "range"
    ? t("player.rangeLabel", {
        surah: activeRequest?.track.surah_number || "—",
        start: activeRequest?.segments[activePlan.startIndex]?.ayah_number || "—",
        end: activeRequest?.segments[activePlan.endIndex]?.ayah_number || "—",
      })
    : activePlan?.kind === "ayah" && activeAyah
      ? t("common.ayah", { ayah: `${activeAyah.surah_number}:${activeAyah.ayah_number}` })
      : (activeRequest && displayTitle) || activeRequest?.title || t("player.noAudio");
  const statusLabel = t(status.key, status.variables);
  const settingsActionLabel = settingsOpen ? t("player.hideSettings") : t("player.showSettings");
  const readerAyahIsActive = Boolean(readerControls?.ayahKey && activePlan?.kind === "ayah"
    && activePlan.startIndex === activePlan.endIndex && activeAyah
    && `${activeAyah.surah_number}:${activeAyah.ayah_number}` === readerControls.ayahKey);
  const readerIsPlaying = readerAyahIsActive && isPlaying;

  // load() drops the queued pause event and a broken source never plays, so a
  // reset or failed element reports that the sound has stopped.
  const reportStopped = () => {
    setIsPlaying(false);
    onPlayingChangeRef.current?.(false);
    onBufferingChangeRef.current?.(false);
  };

  const mobilePresentation = presentation === "desktop" ? null : presentation;
  const fieldId = (name: string) => `${name}-${activeRequest?.track.id || "empty"}`;

  const repeatSelect = (
    <select
      id={fieldId("repeat-mode")}
      aria-label={t("player.repeatAria")}
      value={repeatMode}
      onChange={(event) => setRepeatMode(event.target.value as RepeatMode)}
      disabled={!activeRequest}
    >
      <option value="off">{t("player.repeatOff")}</option>
      <option value="ayah" disabled={availableAyahs.length === 0}>{t("player.repeatAyah")}</option>
      <option value="selection">{t("player.repeatSelection")}</option>
    </select>
  );
  const speedSelect = (
    <select
      id={fieldId("playback-rate")}
      aria-label={t("player.speedAria")}
      value={playbackRate}
      onChange={(event) => setPlaybackRate(Number(event.target.value))}
      disabled={!activeRequest}
    >
      {SPEED_OPTIONS.map((speed) => (
        <option key={speed} value={speed}>{formatNumber(speed)}×</option>
      ))}
    </select>
  );
  const pauseSelect = (
    <select
      id={fieldId("ayah-pause")}
      aria-label={t("player.pause")}
      value={pauseMs}
      onChange={(event) => setPauseMs(Number(event.target.value))}
      disabled={!activeRequest || availableAyahs.length === 0}
    >
      {PAUSE_OPTIONS.map((milliseconds) => (
        <option key={milliseconds} value={milliseconds}>
          {milliseconds === 0
            ? t("player.noPause")
            : t("player.seconds", { value: formatNumber(milliseconds / 1000) })}
        </option>
      ))}
    </select>
  );
  const sleepSelect = (
    <select
      id={fieldId("sleep-timer")}
      aria-label={t("player.sleep")}
      value={sleepMode}
      onChange={(event) => handleSleepModeChange(event.target.value as SleepMode)}
      disabled={!activeRequest}
    >
      <option value="off">{t("player.off")}</option>
      <option value="ayah" disabled={availableAyahs.length === 0}>{t("player.afterAyah")}</option>
      <option value="5">{t("player.afterMinutes", { count: 5 })}</option>
      <option value="15">{t("player.afterMinutes", { count: 15 })}</option>
      <option value="30">{t("player.afterMinutes", { count: 30 })}</option>
      <option value="60">{t("player.afterMinutes", { count: 60 })}</option>
    </select>
  );
  const sleepRemainingLabel = sleepRemainingMs !== null
    ? t("player.remaining", { time: formatRemaining(sleepRemainingMs) })
    : null;
  const rangeStartField = (
    <div className="form-group">
      <label className="form-label" htmlFor={fieldId("range-start")}>{t("player.fromAyah")}</label>
      <select
        id={fieldId("range-start")}
        aria-label={t("player.rangeStartAria")}
        value={rangeStartAyah ?? ""}
        disabled={availableAyahs.length === 0}
        onChange={(event) => {
          const nextStart = Number(event.target.value);
          setRangeStartAyah(nextStart);
          setRangeEndAyah((current) => current === null || current < nextStart ? nextStart : current);
        }}
      >
        {availableAyahs.length === 0 && <option value="">—</option>}
        {availableAyahs.map((ayah) => <option key={ayah} value={ayah}>{ayah}</option>)}
      </select>
    </div>
  );
  const rangeEndField = (
    <div className="form-group">
      <label className="form-label" htmlFor={fieldId("range-end")}>{t("player.toAyah")}</label>
      <select
        id={fieldId("range-end")}
        aria-label={t("player.rangeEndAria")}
        value={rangeEndAyah ?? ""}
        disabled={availableAyahs.length === 0}
        onChange={(event) => {
          const nextEnd = Number(event.target.value);
          setRangeEndAyah(nextEnd);
          setRangeStartAyah((current) => current === null || current > nextEnd ? nextEnd : current);
        }}
      >
        {availableAyahs.length === 0 && <option value="">—</option>}
        {availableAyahs.map((ayah) => <option key={ayah} value={ayah}>{ayah}</option>)}
      </select>
    </div>
  );

  // The phone parts read the same state and call the same handlers as the
  // desktop markup; nothing about playback changes with the presentation.
  // The object is only handed to them, never read here: it holds callbacks
  // that touch refs, which the compiler lint keeps out of render.
  const mobileActive = mobilePresentation !== null && mobile !== undefined;
  const Parts = mobileActive ? mobile?.parts ?? null : null;
  const engine: MobilePlayerEngine = {
    presentation: mobilePresentation ?? "mini",
    request: activeRequest,
    plan: planBounds,
    activeAyah,
    isPlaying,
    statusLabel,
    error,
    title: currentSelectionLabel,
    audio: audioElement,
    togglePlayback,
    seekBy,
    seekToMs,
    settings: [
      { key: "speed", label: t("player.speed"), control: speedSelect },
      { key: "sleep", label: t("player.sleep"), control: sleepSelect, note: sleepRemainingLabel },
      { key: "repeat", label: t("player.repeat"), control: repeatSelect },
      { key: "pause", label: t("player.pause"), control: pauseSelect },
    ],
    range: {
      start: rangeStartField,
      end: rangeEndField,
      play: startRange,
      disabled: availableAyahs.length === 0,
      label: rangeStartAyah !== null && rangeEndAyah !== null
        ? t("player.rangeValue", { start: rangeStartAyah, end: rangeEndAyah })
        : null,
    },
  };

  // Each child below keeps its slot in every presentation, so the <audio>
  // element is never remounted and playback survives a change of view.
  return (
    <div className={`segmented-audio-player ${className}`.trim()}>
      {readerControls?.container && createPortal(
        <div className="reader-selected-audio">
          <div className="reader-selected-audio-copy" aria-live="polite">
            <strong>{readerControls.ayahKey ? t("common.ayah", { ayah: readerControls.ayahKey }) : t("quran.readerSelectAyah")}</strong>
            <span>{readerControls.loading ? t("common.loading") : readerControls.error || error
              ? t("quran.readerAyahUnavailable") : readerAyahIsActive ? statusLabel : readerControls.artist}</span>
          </div>
          <button type="button" className="reader-ayah-play"
            disabled={!readerControls.ayahKey || !readerControls.available || readerControls.loading}
            aria-label={readerIsPlaying ? t("quran.readerPauseAyah", { ayah: readerControls.ayahKey! })
              : readerControls.ayahKey ? t("quran.readerPlayAyah", { ayah: readerControls.ayahKey }) : t("quran.readerSelectAyah")}
            onClick={() => {
              if (!readerAyahIsActive) readerControls.onPlayAyah();
              else if (isPlaying) stopAtCurrentPosition({ key: "player.status.paused" });
              else resumePlayback();
            }}>
            <svg width="22" height="22" viewBox="0 0 24 24" aria-hidden="true" fill="currentColor">
              {readerIsPlaying ? <path d="M6 4h4v16H6zm8 0h4v16h-4z" /> : <path d="m7 3 15 9-15 9z" />}
            </svg>
          </button>
        </div>, readerControls.container,
      )}
      {mobileActive && mobile ? (
        Parts && <Parts.Summary engine={engine} mobile={mobile} />
      ) : (
        <div className="segmented-audio-summary">
          <div>
            <strong>{currentSelectionLabel}</strong>
            <p className="kpi-desc">
              {activeRequest?.artist || t("player.chooseRecording")}
              {activeAyah ? ` · ${t("player.activeAyah", { surah: activeAyah.surah_number, ayah: activeAyah.ayah_number })}` : ""}
            </p>
          </div>
          <span
            className={`status-chip${isPlaying ? " ok" : ""}`}
            aria-live="polite"
            title={compact ? statusLabel : undefined}
          >
            {statusLabel}
          </span>
        </div>
      )}

      {error && !mobileActive && <div className="alert alert-error">{error}</div>}

      <div className="segmented-audio-native-controls">
        <audio
          ref={attachAudio}
          controls
          preload="metadata"
          onLoadedMetadata={handleLoadedMetadata}
          onPlay={() => {
            claimAudioFocus(audioPlayerId);
            pendingPauseStatusRef.current = null;
            hasStartedRef.current = true;
            setIsPlaying(true);
            onPlayingChangeRef.current?.(true);
            setStatus({ key: "player.status.playing" });
            setError(null);
            updateActiveSegment(segmentsRef.current[planRef.current?.currentIndex ?? -1] ?? null);
            if ("mediaSession" in navigator) navigator.mediaSession.playbackState = "playing";
            handleTimeUpdate();
          }}
          onPlaying={() => {
            setIsPlaying(true);
            onPlayingChangeRef.current?.(true);
            onBufferingChangeRef.current?.(false);
            setStatus({ key: "player.status.playing" });
          }}
          onPause={() => {
            setIsPlaying(false);
            onPlayingChangeRef.current?.(false);
            onBufferingChangeRef.current?.(false);
            const pendingStatus = pendingPauseStatusRef.current;
            pendingPauseStatusRef.current = null;
            if (pendingStatus) {
              setStatus(pendingStatus);
            } else if (!boundaryTransitionRef.current) {
              setStatus({
                key: hasStartedRef.current ? "player.status.paused" : "player.status.ready",
              });
            }
            if ("mediaSession" in navigator) navigator.mediaSession.playbackState = "paused";
            updateMediaPosition();
          }}
          onWaiting={() => {
            setStatus({ key: "player.status.buffering" });
            onBufferingChangeRef.current?.(true);
          }}
          onCanPlay={() => {
            if (!isPlaying) {
              setStatus({
                key: hasStartedRef.current ? "player.status.readyResume" : "player.status.ready",
              });
            }
          }}
          onEnded={handleBoundary}
          onEmptied={reportStopped}
          onError={reportStopped}
          onTimeUpdate={handleTimeUpdate}
        />
      </div>

      {mobileActive && mobile ? (
        Parts && <Parts.Transport engine={engine} mobile={mobile} />
      ) : (
        <button
          className="btn btn-secondary btn-sm segmented-audio-settings-toggle"
          type="button"
          aria-expanded={settingsOpen}
          aria-label={settingsActionLabel}
          title={compact ? settingsActionLabel : undefined}
          onClick={() => setSettingsOpen((current) => !current)}
        >
          {compact && <span aria-hidden="true">⚙</span>}
          <span className="segmented-audio-settings-label">
            {compact ? t("player.settingsShort") : settingsActionLabel}
          </span>
        </button>
      )}

      {mobileActive && mobile ? (
        mobilePresentation === "full" && Parts && <Parts.Options engine={engine} mobile={mobile} />
      ) : settingsOpen && (
        <>
          <div className="segmented-audio-settings">
        <div className="form-group">
          <label className="form-label" htmlFor={fieldId("repeat-mode")}>
            {t("player.repeat")}
          </label>
          {repeatSelect}
        </div>

        <div className="form-group">
          <label className="form-label" htmlFor={fieldId("playback-rate")}>
            {t("player.speed")}
          </label>
          {speedSelect}
        </div>

        <div className="form-group">
          <label className="form-label" htmlFor={fieldId("ayah-pause")}>
            {t("player.pause")}
          </label>
          {pauseSelect}
        </div>

        <div className="form-group">
          <label className="form-label" htmlFor={fieldId("sleep-timer")}>
            {t("player.sleep")}
          </label>
          {sleepSelect}
          {sleepRemainingLabel && (
            <span className="kpi-desc" aria-live="polite">
              {sleepRemainingLabel}
            </span>
          )}
        </div>
          </div>

          <div className="segmented-audio-range" aria-label={t("player.rangeAria")}>
              {rangeStartField}
              {rangeEndField}
              <button
                className="btn btn-primary btn-sm"
                type="button"
                onClick={startRange}
                disabled={availableAyahs.length === 0}
              >
                {t("player.playRange")}
              </button>
          </div>

          <p className="segmented-audio-browser-note">
            {t("player.mediaNote")}
          </p>
        </>
      )}
    </div>
  );
}
