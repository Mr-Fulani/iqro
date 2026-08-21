"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import {
  api,
  AudioTrack,
  AyahAudioSegment,
  Recitation,
} from "../lib/api";

type MushafAudioPlayerProps = {
  editionCode: string;
  selectedSurah: number;
  selectedAyahKey: string | null;
  onActiveAyahChange: (ayahKey: string | null) => void;
};

type PlaybackTarget = {
  surah: number;
  ayah: number | null;
  startMs: number;
  endMs: number | null;
};

function parseAyahKey(value: string | null): { surah: number; ayah: number } | null {
  if (!value) return null;
  const [surah, ayah] = value.split(":").map(Number);
  if (!Number.isInteger(surah) || !Number.isInteger(ayah)) return null;
  return { surah, ayah };
}

function recitationLabel(recitation: Recitation): string {
  const style = recitation.style === "muallim"
    ? "Муаллим"
    : recitation.style === "mujawwad"
      ? "Муджаввад"
      : "Мурратталь";
  return `${recitation.reciter.name_ru || recitation.reciter.name_en} · ${style}`;
}

export function MushafAudioPlayer({
  editionCode,
  selectedSurah,
  selectedAyahKey,
  onActiveAyahChange,
}: MushafAudioPlayerProps) {
  const [recitations, setRecitations] = useState<Recitation[]>([]);
  const [selectedRecitationId, setSelectedRecitationId] = useState("");
  const [track, setTrack] = useState<AudioTrack | null>(null);
  const [target, setTarget] = useState<PlaybackTarget | null>(null);
  const [loading, setLoading] = useState(false);
  const [isPlaying, setIsPlaying] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const audioRef = useRef<HTMLAudioElement | null>(null);
  const targetRef = useRef<PlaybackTarget | null>(null);
  const segmentsRef = useRef<AyahAudioSegment[]>([]);

  const selectedAyah = useMemo(() => parseAyahKey(selectedAyahKey), [selectedAyahKey]);
  const selectedRecitation = recitations.find((item) => item.id === selectedRecitationId);

  useEffect(() => {
    let cancelled = false;
    setLoading(true);
    setError(null);
    api
      .getRecitations({ quran_edition: editionCode })
      .then((response) => {
        if (cancelled) return;
        const available = response.results || [];
        setRecitations(available);
        setSelectedRecitationId((current) => {
          if (available.some((item) => item.id === current)) return current;
          const preferred = available
            .filter((item) => item.code.startsWith("qf-7-"))
            .sort((left, right) => right.coverage.surah_count - left.coverage.surah_count)[0];
          return preferred?.id || available[0]?.id || "";
        });
      })
      .catch((reason) => {
        if (!cancelled) setError(api.normalizeError(reason));
      })
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [editionCode]);

  useEffect(() => {
    const audio = audioRef.current;
    if (audio) {
      audio.pause();
      audio.removeAttribute("src");
      audio.load();
    }
    setTrack(null);
    segmentsRef.current = [];
    setTarget(null);
    targetRef.current = null;
    setIsPlaying(false);
    setLoading(false);
    onActiveAyahChange(null);
  }, [selectedRecitationId, onActiveAyahChange]);

  const startAudio = (nextTrack: AudioTrack, nextTarget: PlaybackTarget) => {
    const audio = audioRef.current;
    if (!audio) return;
    const start = () => {
      audio.currentTime = nextTarget.startMs / 1000;
      void audio.play().catch(() => {
        setError("Браузер заблокировал автозапуск. Нажмите ▶ в аудиоплеере.");
      });
    };
    if (audio.getAttribute("src") !== nextTrack.asset.url) {
      audio.src = nextTrack.asset.url;
      audio.load();
      audio.addEventListener("loadedmetadata", start, { once: true });
    } else if (audio.readyState >= 1) {
      start();
    } else {
      audio.addEventListener("loadedmetadata", start, { once: true });
    }
  };

  const playSurah = async () => {
    if (!selectedRecitationId) return;
    setLoading(true);
    setError(null);
    try {
      const playback = await api.getSurahPlayback(selectedRecitationId, selectedSurah);
      const nextSegments = playback.segments || [];
      const nextTarget = { surah: selectedSurah, ayah: null, startMs: 0, endMs: null };
      setTrack(playback.track);
      segmentsRef.current = nextSegments;
      setTarget(nextTarget);
      targetRef.current = nextTarget;
      onActiveAyahChange(
        nextSegments[0]
          ? `${nextSegments[0].surah_number}:${nextSegments[0].ayah_number}`
          : null,
      );
      startAudio(playback.track, nextTarget);
    } catch (reason) {
      setError(api.normalizeError(reason));
    } finally {
      setLoading(false);
    }
  };

  const playAyah = async () => {
    if (!selectedRecitationId || !selectedAyah) return;
    setLoading(true);
    setError(null);
    try {
      const playback = await api.getAyahPlayback(
        selectedRecitationId,
        selectedAyah.surah,
        selectedAyah.ayah,
      );
      const nextTarget = {
        surah: selectedAyah.surah,
        ayah: selectedAyah.ayah,
        startMs: playback.segment.start_ms,
        endMs: playback.segment.end_ms,
      };
      setTrack(playback.track);
      segmentsRef.current = [playback.segment];
      setTarget(nextTarget);
      targetRef.current = nextTarget;
      onActiveAyahChange(`${selectedAyah.surah}:${selectedAyah.ayah}`);
      startAudio(playback.track, nextTarget);
    } catch (reason) {
      setError(api.normalizeError(reason));
    } finally {
      setLoading(false);
    }
  };

  const handleTimeUpdate = () => {
    const audio = audioRef.current;
    const currentTarget = targetRef.current;
    if (!audio || !currentTarget) return;
    const currentMs = Math.round(audio.currentTime * 1000);
    if (currentTarget.endMs !== null && currentMs >= currentTarget.endMs) {
      audio.pause();
      audio.currentTime = currentTarget.endMs / 1000;
      setIsPlaying(false);
      onActiveAyahChange(null);
      return;
    }
    let currentSegment: AyahAudioSegment | undefined;
    for (const segment of segmentsRef.current) {
      if (currentMs >= segment.start_ms && currentMs < segment.end_ms) {
        currentSegment = segment;
      }
    }
    if (currentSegment) {
      onActiveAyahChange(`${currentSegment.surah_number}:${currentSegment.ayah_number}`);
    }
  };

  const handlePlay = () => {
    const audio = audioRef.current;
    const currentTarget = targetRef.current;
    if (
      audio &&
      currentTarget?.endMs !== null &&
      currentTarget?.endMs !== undefined &&
      audio.currentTime * 1000 >= currentTarget.endMs - 40
    ) {
      audio.currentTime = currentTarget.startMs / 1000;
    }
    setIsPlaying(true);
    handleTimeUpdate();
  };

  return (
    <div className="mushaf-audio-panel">
      <div className="mushaf-audio-controls">
        <div className="form-group mushaf-reciter-select">
          <label className="form-label" htmlFor="mushaf-recitation">
            Чтец Quran.Foundation
          </label>
          <select
            id="mushaf-recitation"
            value={selectedRecitationId}
            onChange={(event) => {
              setLoading(true);
              setSelectedRecitationId(event.target.value);
            }}
            disabled={loading || recitations.length === 0}
          >
            {recitations.map((recitation) => (
              <option key={recitation.id} value={recitation.id}>
                {recitationLabel(recitation)} · {recitation.coverage.surah_count}/114 сур
              </option>
            ))}
          </select>
        </div>

        <button
          className="btn btn-primary"
          type="button"
          onClick={() => void playSurah()}
          disabled={loading || !selectedRecitationId}
        >
          {loading ? "Загрузка…" : `▶ Сура ${selectedSurah}`}
        </button>
        <button
          className="btn btn-secondary"
          type="button"
          onClick={() => void playAyah()}
          disabled={loading || !selectedRecitationId || !selectedAyah}
        >
          ▶ {selectedAyahKey ? `Аят ${selectedAyahKey}` : "Выберите аят"}
        </button>
      </div>

      {error && <div className="alert alert-error">{error}</div>}
      {recitations.length === 0 && !loading && !error && (
        <div className="alert alert-info">Для этого издания пока нет опубликованных аудиозаписей.</div>
      )}

      <div className="mushaf-audio-now-playing">
        <div>
          <strong>
            {target
              ? target.ayah
                ? `Аят ${target.surah}:${target.ayah}`
                : `Сура ${target.surah}`
              : "Аудио не запущено"}
          </strong>
          <p className="kpi-desc">
            {selectedRecitation ? recitationLabel(selectedRecitation) : "Выберите чтеца"}
            {track && isPlaying ? " · воспроизводится" : ""}
          </p>
        </div>
        <audio
          ref={audioRef}
          controls
          preload="metadata"
          onPlay={handlePlay}
          onPause={() => {
            setIsPlaying(false);
            onActiveAyahChange(null);
          }}
          onEnded={() => {
            setIsPlaying(false);
            onActiveAyahChange(null);
          }}
          onTimeUpdate={handleTimeUpdate}
        />
      </div>
    </div>
  );
}
