"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { api, Recitation, SurahPlayback } from "../lib/api";
import { useI18n } from "../lib/i18n-context";
import { latestRecitationsByVariant } from "../lib/reciter-catalog";
import {
  AudioPlaybackRequest,
  SegmentedAudioPlayer,
  type AudioPlayerControlRequest,
  type AudioPlaybackSettings,
} from "./SegmentedAudioPlayer";

export type AyahPlaybackTrigger = {
  requestId: number;
  ayahKey: string;
};

type MushafAudioPlayerProps = {
  editionCode: string;
  selectedSurah: number;
  selectedAyahKey: string | null;
  playAyahRequest?: AyahPlaybackTrigger | null;
  controlRequest?: AudioPlayerControlRequest | null;
  onActiveAyahChange: (ayahKey: string | null) => void;
  onPlayingChange?: (isPlaying: boolean) => void;
  onSettingsChange?: (settings: AudioPlaybackSettings) => void;
};

function parseAyahKey(value: string | null): { surah: number; ayah: number } | null {
  if (!value) return null;
  const [surah, ayah] = value.split(":").map(Number);
  if (!Number.isInteger(surah) || !Number.isInteger(ayah)) return null;
  return { surah, ayah };
}

export function MushafAudioPlayer({
  editionCode,
  selectedSurah,
  selectedAyahKey,
  playAyahRequest,
  controlRequest,
  onActiveAyahChange,
  onPlayingChange,
  onSettingsChange,
}: MushafAudioPlayerProps) {
  const { locale, t } = useI18n();
  const [recitations, setRecitations] = useState<Recitation[]>([]);
  const [selectedRecitationId, setSelectedRecitationId] = useState("");
  const [preparedPlayback, setPreparedPlayback] = useState<SurahPlayback | null>(null);
  const [playerRequest, setPlayerRequest] = useState<AudioPlaybackRequest | null>(null);
  const [catalogLoading, setCatalogLoading] = useState(false);
  const [playbackLoading, setPlaybackLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const requestIdRef = useRef(0);
  const handledAyahRequestRef = useRef<number | null>(null);

  const selectedAyah = useMemo(() => parseAyahKey(selectedAyahKey), [selectedAyahKey]);
  const selectedRecitation = recitations.find((item) => item.id === selectedRecitationId);
  const recitationLabel = useCallback((recitation: Recitation): string => {
    const style = recitation.style === "muallim"
      ? t("audio.style.muallim")
      : recitation.style === "mujawwad"
        ? t("audio.style.mujawwad")
        : t("audio.style.murattal");
    const reciter = locale === "ar"
      ? recitation.reciter.name_ar
      : locale === "ru"
        ? recitation.reciter.name_ru
        : recitation.reciter.name_en;
    return `${reciter || recitation.reciter.name_en} · ${style}`;
  }, [locale, t]);

  useEffect(() => {
    let cancelled = false;
    setCatalogLoading(true);
    setError(null);
    api
      .getRecitations({ quran_edition: editionCode })
      .then((response) => {
        if (cancelled) return;
        const available = latestRecitationsByVariant(response.results || []);
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
        if (!cancelled) setCatalogLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [editionCode]);

  useEffect(() => {
    if (!selectedRecitationId) {
      setPreparedPlayback(null);
      setPlayerRequest(null);
      return;
    }

    let cancelled = false;
    setPlaybackLoading(true);
    setPreparedPlayback(null);
    setPlayerRequest(null);
    setError(null);
    api
      .getSurahPlayback(selectedRecitationId, selectedSurah)
      .then((playback) => {
        if (cancelled) return;
        setPreparedPlayback(playback);
        const recitation = recitations.find((item) => item.id === selectedRecitationId);
        requestIdRef.current += 1;
        setPlayerRequest({
          requestId: requestIdRef.current,
          track: playback.track,
          segments: playback.segments || [],
          kind: "surah",
          title: t("common.surah", { surah: selectedSurah }),
          artist: recitation ? recitationLabel(recitation) : t("audio.qfReciter"),
          album: t("audio.mushafAlbum"),
          autoPlay: false,
        });
      })
      .catch((reason) => {
        if (!cancelled) setError(api.normalizeError(reason));
      })
      .finally(() => {
        if (!cancelled) setPlaybackLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [recitationLabel, recitations, selectedRecitationId, selectedSurah, t]);

  const startPlayback = useCallback(async (
    kind: "surah" | "ayah",
    requestedAyah = selectedAyah,
  ) => {
    if (!selectedRecitationId) return;
    if (kind === "ayah" && (!requestedAyah || requestedAyah.surah !== selectedSurah)) return;
    setPlaybackLoading(true);
    setError(null);
    try {
      const playback = preparedPlayback || await api.getSurahPlayback(
        selectedRecitationId,
        selectedSurah,
      );
      setPreparedPlayback(playback);
      requestIdRef.current += 1;
      setPlayerRequest({
        requestId: requestIdRef.current,
        track: playback.track,
        segments: playback.segments || [],
        kind,
        startAyah: kind === "ayah" ? requestedAyah?.ayah : undefined,
        endAyah: kind === "ayah" ? requestedAyah?.ayah : undefined,
        title: kind === "ayah" && requestedAyah
          ? t("common.ayah", { ayah: `${requestedAyah.surah}:${requestedAyah.ayah}` })
          : t("common.surah", { surah: selectedSurah }),
        artist: selectedRecitation
          ? recitationLabel(selectedRecitation)
          : t("audio.qfReciter"),
        album: t("audio.mushafAlbum"),
        autoPlay: true,
      });
    } catch (reason) {
      setError(api.normalizeError(reason));
    } finally {
      setPlaybackLoading(false);
    }
  }, [
    preparedPlayback,
    recitationLabel,
    selectedAyah,
    selectedRecitation,
    selectedRecitationId,
    selectedSurah,
    t,
  ]);

  useEffect(() => {
    if (
      !playAyahRequest ||
      handledAyahRequestRef.current === playAyahRequest.requestId ||
      !selectedRecitationId ||
      !preparedPlayback ||
      preparedPlayback.track.surah_number !== selectedSurah
    ) {
      return;
    }
    const requestedAyah = parseAyahKey(playAyahRequest.ayahKey);
    if (!requestedAyah || requestedAyah.surah !== selectedSurah) return;
    handledAyahRequestRef.current = playAyahRequest.requestId;
    void startPlayback("ayah", requestedAyah);
  }, [
    playAyahRequest,
    preparedPlayback,
    selectedRecitationId,
    selectedSurah,
    startPlayback,
  ]);

  return (
    <div className="mushaf-audio-panel">
      <div className="mushaf-audio-controls">
        <div className="form-group mushaf-reciter-select">
          <label className="form-label" htmlFor="mushaf-recitation">
            {t("mushafAudio.reciter")}
          </label>
          <select
            id="mushaf-recitation"
            value={selectedRecitationId}
            onChange={(event) => setSelectedRecitationId(event.target.value)}
            disabled={catalogLoading || recitations.length === 0}
          >
            {recitations.map((recitation) => (
              <option key={recitation.id} value={recitation.id}>
                {recitationLabel(recitation)} · {t("mushafAudio.coverage", { count: recitation.coverage.surah_count })}
              </option>
            ))}
          </select>
        </div>

        <button
          className="btn btn-primary"
          type="button"
          onClick={() => void startPlayback("surah")}
          disabled={playbackLoading || !preparedPlayback}
        >
          {playbackLoading ? t("common.loading") : `▶ ${t("common.surah", { surah: selectedSurah })}`}
        </button>
        <button
          className="btn btn-secondary"
          type="button"
          onClick={() => void startPlayback("ayah")}
          disabled={playbackLoading || !preparedPlayback || !selectedAyah}
        >
          ▶ {selectedAyahKey ? t("common.ayah", { ayah: selectedAyahKey }) : t("mushafAudio.chooseAyah")}
        </button>
      </div>

      {error && <div className="alert alert-error">{error}</div>}
      {recitations.length === 0 && !catalogLoading && !error && (
        <div className="alert alert-info">{t("mushafAudio.none")}</div>
      )}

      <SegmentedAudioPlayer
        request={playerRequest}
        className="mushaf-audio-now-playing"
        controlRequest={controlRequest}
        onActiveAyahChange={onActiveAyahChange}
        onPlayingChange={onPlayingChange}
        onSettingsChange={onSettingsChange}
      />
    </div>
  );
}
