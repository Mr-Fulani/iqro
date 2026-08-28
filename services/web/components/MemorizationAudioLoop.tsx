"use client";

import { useEffect, useRef, useState } from "react";
import { api, SurahPlayback } from "../lib/api";
import { useI18n } from "../lib/i18n-context";

type Props = {
  recitationId: string | null;
  surahNumber: number;
  startAyah: number;
  endAyah: number;
  repeatLimit: number;
  pauseSeconds: number;
  onCycleComplete: () => void;
};

export function MemorizationAudioLoop({
  recitationId,
  surahNumber,
  startAyah,
  endAyah,
  repeatLimit,
  pauseSeconds,
  onCycleComplete,
}: Props) {
  const { formatNumber, t } = useI18n();
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const playbackRef = useRef<SurahPlayback | null>(null);
  const boundaryRef = useRef({ startMs: 0, endMs: 0 });
  const cycleRef = useRef(0);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [loading, setLoading] = useState(false);
  const [playing, setPlaying] = useState(false);
  const [completedCycles, setCompletedCycles] = useState(0);
  const [error, setError] = useState<string | null>(null);

  const clearTimer = () => {
    if (timerRef.current !== null) {
      clearTimeout(timerRef.current);
      timerRef.current = null;
    }
  };

  useEffect(() => {
    const audio = audioRef.current;
    return () => {
      clearTimer();
      audio?.pause();
    };
  }, []);

  useEffect(() => {
    clearTimer();
    playbackRef.current = null;
    cycleRef.current = 0;
    setCompletedCycles(0);
    setPlaying(false);
    audioRef.current?.pause();
  }, [endAyah, recitationId, startAyah, surahNumber]);

  const playFromStart = async () => {
    const audio = audioRef.current;
    if (!audio) return;
    audio.currentTime = boundaryRef.current.startMs / 1000;
    try {
      await audio.play();
      setPlaying(true);
    } catch {
      setPlaying(false);
      setError(t("memorization.audioBlocked"));
    }
  };

  const start = async () => {
    if (!recitationId) {
      setError(t("memorization.chooseReciterFirst"));
      return;
    }
    setLoading(true);
    setError(null);
    try {
      const playback = playbackRef.current ||
        await api.getSurahPlayback(recitationId, surahNumber);
      const selected = playback.segments.filter(
        (segment) => segment.ayah_number >= startAyah && segment.ayah_number <= endAyah,
      );
      if (selected.length === 0) throw new Error(t("memorization.audioUnavailable"));
      playbackRef.current = playback;
      boundaryRef.current = {
        startMs: selected[0].start_ms,
        endMs: selected[selected.length - 1].end_ms,
      };
      const audio = audioRef.current;
      if (!audio) return;
      if (audio.src !== playback.track.asset.url) {
        audio.src = playback.track.asset.url;
        audio.load();
        await new Promise<void>((resolve, reject) => {
          const ready = () => resolve();
          const failed = () => reject(new Error(t("memorization.audioUnavailable")));
          audio.addEventListener("loadedmetadata", ready, { once: true });
          audio.addEventListener("error", failed, { once: true });
        });
      }
      cycleRef.current = 0;
      setCompletedCycles(0);
      await playFromStart();
    } catch (reason) {
      setPlaying(false);
      setError(api.normalizeError(reason));
    } finally {
      setLoading(false);
    }
  };

  const pause = () => {
    clearTimer();
    audioRef.current?.pause();
    setPlaying(false);
  };

  const handleTimeUpdate = () => {
    const audio = audioRef.current;
    if (!audio || !playing || audio.currentTime * 1000 < boundaryRef.current.endMs) return;
    audio.pause();
    setPlaying(false);
    cycleRef.current += 1;
    setCompletedCycles(cycleRef.current);
    onCycleComplete();
    if (cycleRef.current >= Math.max(1, repeatLimit)) return;
    timerRef.current = setTimeout(() => void playFromStart(), pauseSeconds * 1000);
  };

  return (
    <div className="memorization-audio" data-testid="memorization-audio-loop">
      <audio ref={audioRef} preload="metadata" onTimeUpdate={handleTimeUpdate} onEnded={handleTimeUpdate} />
      <div className="memorization-audio-actions">
        {!playing ? (
          <button type="button" className="btn btn-primary" onClick={() => void start()} disabled={loading}>
            {loading ? t("common.loading") : t("memorization.playLoop")}
          </button>
        ) : (
          <button type="button" className="btn btn-secondary" onClick={pause}>
            {t("memorization.pauseAudio")}
          </button>
        )}
        <span className="muted">
          {t("memorization.audioCycles", {
            completed: formatNumber(completedCycles),
            target: formatNumber(Math.max(1, repeatLimit)),
          })}
        </span>
      </div>
      <p className="field-help">
        {t("memorization.pauseBetween", { count: formatNumber(pauseSeconds) })}
      </p>
      {error && <p className="error-text" role="alert">{error}</p>}
    </div>
  );
}
