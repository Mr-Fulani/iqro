"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { AudioTrack, AyahAudioSegment } from "../lib/api";

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
};

type RepeatMode = "off" | "ayah" | "selection";
type SleepMode = "off" | "ayah" | "5" | "15" | "30" | "60";

type RuntimePlan = {
  kind: AudioPlaybackRequest["kind"];
  startIndex: number;
  endIndex: number;
  currentIndex: number;
  startMs: number;
  endMs: number;
};

type SegmentedAudioPlayerProps = {
  request: AudioPlaybackRequest | null;
  className?: string;
  onActiveAyahChange?: (ayahKey: string | null) => void;
  onPlayingChange?: (isPlaying: boolean) => void;
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

function formatSeconds(milliseconds: number): string {
  if (milliseconds === 0) return "Без паузы";
  const seconds = milliseconds / 1000;
  return `${seconds.toLocaleString("ru-RU")} с`;
}

function formatRemaining(milliseconds: number): string {
  const totalSeconds = Math.max(0, Math.ceil(milliseconds / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${String(seconds).padStart(2, "0")}`;
}

export function SegmentedAudioPlayer({
  request,
  className = "",
  onActiveAyahChange,
  onPlayingChange,
}: SegmentedAudioPlayerProps) {
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const requestRef = useRef<AudioPlaybackRequest | null>(null);
  const segmentsRef = useRef<AyahAudioSegment[]>([]);
  const planRef = useRef<RuntimePlan | null>(null);
  const playWhenReadyRef = useRef(false);
  const hasStartedRef = useRef(false);
  const boundaryTransitionRef = useRef(false);
  const transitionTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const repeatModeRef = useRef<RepeatMode>("off");
  const playbackRateRef = useRef(1);
  const pauseMsRef = useRef(0);
  const sleepModeRef = useRef<SleepMode>("off");
  const onActiveAyahChangeRef = useRef(onActiveAyahChange);
  const onPlayingChangeRef = useRef(onPlayingChange);

  const [activeRequest, setActiveRequest] = useState<AudioPlaybackRequest | null>(null);
  const [activePlan, setActivePlan] = useState<RuntimePlan | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [hasStarted, setHasStarted] = useState(false);
  const [status, setStatus] = useState("Аудио не запущено");
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
  const [settingsOpen, setSettingsOpen] = useState(true);

  useEffect(() => {
    onActiveAyahChangeRef.current = onActiveAyahChange;
  }, [onActiveAyahChange]);

  useEffect(() => {
    onPlayingChangeRef.current = onPlayingChange;
  }, [onPlayingChange]);

  useEffect(() => {
    const mediaQuery = window.matchMedia("(max-width: 640px)");
    const syncForViewport = () => setSettingsOpen(!mediaQuery.matches);
    syncForViewport();
    mediaQuery.addEventListener("change", syncForViewport);
    return () => mediaQuery.removeEventListener("change", syncForViewport);
  }, []);

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
    void audio.play().catch(() => {
      setIsPlaying(false);
      onPlayingChangeRef.current?.(false);
      setStatus("Позиция сохранена — нажмите «Продолжить»");
      setError("Браузер заблокировал автозапуск аудио.");
    });
  }, []);

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

  const stopAtCurrentPosition = useCallback((nextStatus: string) => {
    clearTransition();
    const audio = audioRef.current;
    if (audio) audio.pause();
    setIsPlaying(false);
    onPlayingChangeRef.current?.(false);
    setStatus(nextStatus);
    if ("mediaSession" in navigator) navigator.mediaSession.playbackState = "paused";
    updateMediaPosition();
  }, [clearTransition, updateMediaPosition]);

  const finishPlayback = useCallback((nextStatus: string) => {
    clearTransition();
    const audio = audioRef.current;
    const plan = planRef.current;
    if (audio) {
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
      setStatus("Запуск воспроизведения…");
      attemptPlay();
    } else {
      setStatus("Готово к воспроизведению");
      onActiveAyahChangeRef.current?.(null);
    }
  }, [attemptPlay, clearTransition, setPlanPosition]);

  useEffect(() => {
    clearTransition();
    const audio = audioRef.current;
    if (!request) {
      requestRef.current = null;
      segmentsRef.current = [];
      planRef.current = null;
      setActiveRequest(null);
      setActivePlan(null);
      setHasStarted(false);
      hasStartedRef.current = false;
      setRangeStartAyah(null);
      setRangeEndAyah(null);
      setStatus("Аудио не запущено");
      updateActiveSegment(null);
      if (audio) {
        audio.pause();
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
    setHasStarted(false);
    hasStartedRef.current = false;
    setRangeStartAyah(nextSegments[0]?.ayah_number ?? null);
    setRangeEndAyah(nextSegments[nextSegments.length - 1]?.ayah_number ?? null);
    setError(null);
    playWhenReadyRef.current = request.autoPlay !== false;

    if (!audio) return;
    audio.playbackRate = playbackRateRef.current;
    const sourceChanged = audio.getAttribute("src") !== request.track.asset.url;
    if (sourceChanged) {
      audio.src = request.track.asset.url;
      audio.load();
      return;
    }
    startPlan(nextPlan, playWhenReadyRef.current);
    playWhenReadyRef.current = false;
  }, [clearTransition, request, startPlan, updateActiveSegment]);

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
        stopAtCurrentPosition("Таймер сна остановил воспроизведение · позиция сохранена");
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
    setStatus(delay > 0 ? `Пауза между аятами · ${formatSeconds(delay)}` : "Переход к аяту…");
    transitionTimerRef.current = setTimeout(() => {
      transitionTimerRef.current = null;
      boundaryTransitionRef.current = false;
      const currentPlan = planRef.current;
      if (!currentPlan) return;
      setPlanPosition(currentPlan, nextIndex);
      attemptPlay();
    }, delay);
  }, [attemptPlay, setPlanPosition]);

  const handleBoundary = useCallback(() => {
    const plan = planRef.current;
    if (!plan || boundaryTransitionRef.current) return;

    if (sleepModeRef.current === "ayah") {
      setSleepMode("off");
      sleepModeRef.current = "off";
      stopAtCurrentPosition("Таймер сна остановил воспроизведение после аята");
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

    finishPlayback("Воспроизведение завершено");
  }, [finishPlayback, scheduleBoundaryTransition, stopAtCurrentPosition, updateActiveSegment]);

  const handleTimeUpdate = useCallback(() => {
    const audio = audioRef.current;
    const plan = planRef.current;
    if (!audio || !plan || boundaryTransitionRef.current) return;
    const currentMs = Math.round(audio.currentTime * 1000);

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
    audio.playbackRate = playbackRateRef.current;
    const shouldPlay = playWhenReadyRef.current;
    playWhenReadyRef.current = false;
    setPlanPosition(plan, plan.currentIndex, shouldPlay);
    if (shouldPlay) {
      setStatus("Запуск воспроизведения…");
      attemptPlay();
    } else {
      setStatus("Готово к воспроизведению");
      onActiveAyahChangeRef.current?.(null);
    }
  }, [attemptPlay, setPlanPosition]);

  const resumePlayback = useCallback(() => {
    const audio = audioRef.current;
    const plan = planRef.current;
    if (!audio || !plan) return;
    clearTransition();
    const currentMs = audio.currentTime * 1000;
    if (currentMs >= plan.endMs - 40 || currentMs < plan.startMs - 40) {
      setPlanPosition(plan, plan.startIndex);
    }
    setError(null);
    setStatus("Возобновление с сохранённой позиции…");
    attemptPlay();
  }, [attemptPlay, clearTransition, setPlanPosition]);

  const moveToAdjacentAyah = useCallback((offset: -1 | 1) => {
    const plan = planRef.current;
    if (!plan || plan.currentIndex < 0) return;
    const nextIndex = Math.min(
      plan.endIndex,
      Math.max(plan.startIndex, plan.currentIndex + offset),
    );
    clearTransition();
    setPlanPosition(plan, nextIndex);
    attemptPlay();
  }, [attemptPlay, clearTransition, setPlanPosition]);

  const seekBy = useCallback((seconds: number) => {
    const audio = audioRef.current;
    const plan = planRef.current;
    if (!audio || !plan) return;
    const nextMs = Math.min(plan.endMs, Math.max(plan.startMs, audio.currentTime * 1000 + seconds * 1000));
    audio.currentTime = nextMs / 1000;
    handleTimeUpdate();
  }, [handleTimeUpdate]);

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
      pause: () => stopAtCurrentPosition("Пауза · позиция сохранена"),
      stop: () => finishPlayback("Воспроизведение остановлено"),
      seekbackward: (details) => seekBy(-(details.seekOffset || 10)),
      seekforward: (details) => seekBy(details.seekOffset || 10),
      previoustrack: () => moveToAdjacentAyah(-1),
      nexttrack: () => moveToAdjacentAyah(1),
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

  useEffect(() => () => clearTransition(), [clearTransition]);

  const availableAyahs = useMemo(
    () => [...new Set((activeRequest?.segments || []).map((segment) => segment.ayah_number))],
    [activeRequest],
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
    ? `Диапазон ${activeRequest?.track.surah_number}:${activeRequest?.segments[activePlan.startIndex]?.ayah_number}–${activeRequest?.track.surah_number}:${activeRequest?.segments[activePlan.endIndex]?.ayah_number}`
    : activePlan?.kind === "ayah" && activeAyah
      ? `Аят ${activeAyah.surah_number}:${activeAyah.ayah_number}`
      : activeRequest?.title || "Аудио не выбрано";

  return (
    <div className={`segmented-audio-player ${className}`.trim()}>
      <div className="segmented-audio-summary">
        <div>
          <strong>{currentSelectionLabel}</strong>
          <p className="kpi-desc">
            {activeRequest?.artist || "Выберите запись"}
            {activeAyah ? ` · аят ${activeAyah.surah_number}:${activeAyah.ayah_number}` : ""}
          </p>
        </div>
        <span className={`status-chip${isPlaying ? " ok" : ""}`} aria-live="polite">
          {status}
        </span>
      </div>

      {error && <div className="alert alert-error">{error}</div>}

      <div className="segmented-audio-native-controls">
        <button
          className="btn btn-secondary btn-sm"
          type="button"
          onClick={resumePlayback}
          disabled={!activeRequest || isPlaying}
        >
          ▶ {hasStarted ? "Продолжить" : "Воспроизвести"}
        </button>
        <audio
          ref={audioRef}
          controls
          preload="metadata"
          onLoadedMetadata={handleLoadedMetadata}
          onPlay={() => {
            hasStartedRef.current = true;
            setHasStarted(true);
            setIsPlaying(true);
            onPlayingChangeRef.current?.(true);
            setStatus("Воспроизводится");
            setError(null);
            if ("mediaSession" in navigator) navigator.mediaSession.playbackState = "playing";
            handleTimeUpdate();
          }}
          onPlaying={() => {
            setIsPlaying(true);
            onPlayingChangeRef.current?.(true);
            setStatus("Воспроизводится");
          }}
          onPause={() => {
            setIsPlaying(false);
            onPlayingChangeRef.current?.(false);
            if (!boundaryTransitionRef.current) {
              setStatus(hasStartedRef.current
                ? "Пауза · позиция сохранена"
                : "Готово к воспроизведению");
            }
            if ("mediaSession" in navigator) navigator.mediaSession.playbackState = "paused";
            updateMediaPosition();
          }}
          onWaiting={() => setStatus("Буферизация · позиция сохранена")}
          onCanPlay={() => {
            if (!isPlaying) {
              setStatus(hasStartedRef.current
                ? "Готово к продолжению с сохранённой позиции"
                : "Готово к воспроизведению");
            }
          }}
          onEnded={handleBoundary}
          onTimeUpdate={handleTimeUpdate}
        />
      </div>

      <button
        className="btn btn-secondary btn-sm segmented-audio-settings-toggle"
        type="button"
        aria-expanded={settingsOpen}
        onClick={() => setSettingsOpen((current) => !current)}
      >
        {settingsOpen ? "Скрыть расширенные настройки" : "Повтор, диапазон и таймер"}
      </button>

      {settingsOpen && (
        <>
          <div className="segmented-audio-settings">
        <div className="form-group">
          <label className="form-label" htmlFor={`repeat-mode-${activeRequest?.track.id || "empty"}`}>
            Повтор
          </label>
          <select
            id={`repeat-mode-${activeRequest?.track.id || "empty"}`}
            aria-label="Режим повтора"
            value={repeatMode}
            onChange={(event) => setRepeatMode(event.target.value as RepeatMode)}
            disabled={!activeRequest}
          >
            <option value="off">Без повтора</option>
            <option value="ayah" disabled={availableAyahs.length === 0}>Повтор аята</option>
            <option value="selection">Повтор суры / диапазона</option>
          </select>
        </div>

        <div className="form-group">
          <label className="form-label" htmlFor={`playback-rate-${activeRequest?.track.id || "empty"}`}>
            Скорость
          </label>
          <select
            id={`playback-rate-${activeRequest?.track.id || "empty"}`}
            aria-label="Скорость воспроизведения"
            value={playbackRate}
            onChange={(event) => setPlaybackRate(Number(event.target.value))}
            disabled={!activeRequest}
          >
            {SPEED_OPTIONS.map((speed) => (
              <option key={speed} value={speed}>{speed.toLocaleString("ru-RU")}×</option>
            ))}
          </select>
        </div>

        <div className="form-group">
          <label className="form-label" htmlFor={`ayah-pause-${activeRequest?.track.id || "empty"}`}>
            Пауза между аятами
          </label>
          <select
            id={`ayah-pause-${activeRequest?.track.id || "empty"}`}
            aria-label="Пауза между аятами"
            value={pauseMs}
            onChange={(event) => setPauseMs(Number(event.target.value))}
            disabled={!activeRequest || availableAyahs.length === 0}
          >
            {PAUSE_OPTIONS.map((milliseconds) => (
              <option key={milliseconds} value={milliseconds}>{formatSeconds(milliseconds)}</option>
            ))}
          </select>
        </div>

        <div className="form-group">
          <label className="form-label" htmlFor={`sleep-timer-${activeRequest?.track.id || "empty"}`}>
            Таймер сна
          </label>
          <select
            id={`sleep-timer-${activeRequest?.track.id || "empty"}`}
            aria-label="Таймер сна"
            value={sleepMode}
            onChange={(event) => handleSleepModeChange(event.target.value as SleepMode)}
            disabled={!activeRequest}
          >
            <option value="off">Выключен</option>
            <option value="ayah" disabled={availableAyahs.length === 0}>После текущего аята</option>
            <option value="5">Через 5 минут</option>
            <option value="15">Через 15 минут</option>
            <option value="30">Через 30 минут</option>
            <option value="60">Через 60 минут</option>
          </select>
          {sleepRemainingMs !== null && (
            <span className="kpi-desc" aria-live="polite">
              Осталось {formatRemaining(sleepRemainingMs)}
            </span>
          )}
        </div>
          </div>

          {availableAyahs.length > 0 && (
            <div className="segmented-audio-range" aria-label="Воспроизведение диапазона аятов">
              <div className="form-group">
                <label className="form-label" htmlFor={`range-start-${activeRequest?.track.id}`}>С аята</label>
                <select
                  id={`range-start-${activeRequest?.track.id}`}
                  aria-label="Начало диапазона аятов"
                  value={rangeStartAyah ?? ""}
                  onChange={(event) => {
                    const nextStart = Number(event.target.value);
                    setRangeStartAyah(nextStart);
                    setRangeEndAyah((current) => current === null || current < nextStart ? nextStart : current);
                  }}
                >
                  {availableAyahs.map((ayah) => <option key={ayah} value={ayah}>{ayah}</option>)}
                </select>
              </div>
              <div className="form-group">
                <label className="form-label" htmlFor={`range-end-${activeRequest?.track.id}`}>По аят</label>
                <select
                  id={`range-end-${activeRequest?.track.id}`}
                  aria-label="Конец диапазона аятов"
                  value={rangeEndAyah ?? ""}
                  onChange={(event) => {
                    const nextEnd = Number(event.target.value);
                    setRangeEndAyah(nextEnd);
                    setRangeStartAyah((current) => current === null || current > nextEnd ? nextEnd : current);
                  }}
                >
                  {availableAyahs.map((ayah) => <option key={ayah} value={ayah}>{ayah}</option>)}
                </select>
              </div>
              <button className="btn btn-primary btn-sm" type="button" onClick={startRange}>
                ▶ Воспроизвести диапазон
              </button>
            </div>
          )}

          <p className="segmented-audio-browser-note">
            Управление Media Session доступно в поддерживаемых браузерах; воспроизведение после
            закрытия вкладки или приложения не гарантируется.
          </p>
        </>
      )}
    </div>
  );
}
