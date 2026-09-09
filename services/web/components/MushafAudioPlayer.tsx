"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { api, Recitation, SurahPlayback } from "../lib/api";
import { reciterName } from "../lib/audio-content";
import { useI18n } from "../lib/i18n-context";
import { latestRecitationsByVariant } from "../lib/reciter-catalog";
import { useMushafReader } from "./MushafReaderLayout";
import {
  loadReciterPreference,
  preferredRecitation,
  rememberReciterPreference,
} from "../lib/reciter-preference";
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
  readerAyahKey?: string | null;
  readerPageKey?: string;
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
  readerAyahKey = null,
  readerPageKey,
  playAyahRequest,
  controlRequest,
  onActiveAyahChange,
  onPlayingChange,
  onSettingsChange,
}: MushafAudioPlayerProps) {
  const { locale, t } = useI18n();
  const reader = useMushafReader();
  const readerScopeKey = readerPageKey ? `${reader?.immersive}:${readerPageKey}:${selectedAyahKey ?? ""}` : undefined;
  const [recitations, setRecitations] = useState<Recitation[]>([]);
  const [selectedRecitationId, setSelectedRecitationId] = useState("");
  const [preparedPlayback, setPreparedPlayback] = useState<SurahPlayback | null>(null);
  const [playerRequest, setPlayerRequest] = useState<AudioPlaybackRequest | null>(null);
  const [catalogLoading, setCatalogLoading] = useState(false);
  const [playbackLoading, setPlaybackLoading] = useState(false);
  const [ayahLoading, setAyahLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const requestIdRef = useRef(0);
  const handledAyahRequestRef = useRef<number | null>(null);
  const playbackGeneration = useRef(0);
  // Only timing metadata is retained, for at most three surahs per voice.
  const playbackCache = useMemo(() => ({ recitationId: selectedRecitationId, requests: new Map<number, Promise<SurahPlayback>>() }), [selectedRecitationId]);
  const loadPlayback = useCallback((surah: number) => {
    const cached = playbackCache.requests.get(surah);
    if (cached) return cached;
    const pending = api.getSurahPlayback(playbackCache.recitationId, surah).catch((reason) => {
      playbackCache.requests.delete(surah);
      throw reason;
    });
    playbackCache.requests.set(surah, pending);
    if (playbackCache.requests.size > 3) playbackCache.requests.delete(playbackCache.requests.keys().next().value!);
    return pending;
  }, [playbackCache]);

  useEffect(() => {
    playbackGeneration.current += 1;
    setAyahLoading(false);
    return () => { playbackGeneration.current += 1; };
  }, [readerScopeKey, selectedRecitationId, selectedSurah]);

  const selectedAyah = useMemo(() => parseAyahKey(selectedAyahKey), [selectedAyahKey]);
  const selectedRecitation = recitations.find((item) => item.id === selectedRecitationId);
  const recitationLabel = useCallback((recitation: Recitation): string => {
    const style = recitation.style === "muallim"
      ? t("audio.style.muallim")
      : recitation.style === "mujawwad"
        ? t("audio.style.mujawwad")
        : t("audio.style.murattal");
    const reciter = reciterName(recitation.reciter, locale);
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
        const remembered = preferredRecitation(available, loadReciterPreference());
        const fallback = available
          .filter((item) => item.code.startsWith("qf-7-"))
          .sort((left, right) => right.coverage.surah_count - left.coverage.surah_count)[0];
        const selected = remembered || fallback || available[0];
        setSelectedRecitationId(selected?.id || "");
        if (selected) rememberReciterPreference(selected.reciter, selected);
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

  const selectRecitation = (recitationId: string) => {
    const recitation = recitations.find((item) => item.id === recitationId);
    if (recitation) rememberReciterPreference(recitation.reciter, recitation);
    setSelectedRecitationId(recitationId);
  };

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
    loadPlayback(selectedSurah)
      .then((playback) => {
        if (cancelled) return;
        setPreparedPlayback(playback);
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
  }, [loadPlayback, selectedRecitationId, selectedSurah]);

  // Prepare the selected segment before the user presses play. The audio element
  // can then start directly in that gesture, without another request or load().
  useEffect(() => {
    if (!preparedPlayback || preparedPlayback.track.surah_number !== selectedSurah
      || preparedPlayback.track.recitation_id !== selectedRecitationId) return;
    const ayah = selectedAyah?.surah === selectedSurah ? selectedAyah : null;
    if (ayah && !preparedPlayback.segments?.some((segment) => segment.ayah_number === ayah.ayah)) {
      setPlayerRequest(null);
      setError(t("quran.readerAyahUnavailable"));
      return;
    }
    setError(null);
    requestIdRef.current += 1;
    setPlayerRequest({
      requestId: requestIdRef.current,
      track: preparedPlayback.track,
      segments: preparedPlayback.segments || [],
      kind: ayah ? "ayah" : "surah",
      startAyah: ayah?.ayah,
      endAyah: ayah?.ayah,
      title: ayah ? t("common.ayah", { ayah: `${ayah.surah}:${ayah.ayah}` }) : t("common.surah", { surah: selectedSurah }),
      artist: selectedRecitation ? recitationLabel(selectedRecitation) : t("audio.qfReciter"),
      album: t("audio.mushafAlbum"),
      autoPlay: false,
    });
  }, [preparedPlayback, selectedAyah, selectedSurah, selectedRecitationId, selectedRecitation, recitationLabel, t]);

  const startPlayback = useCallback(async (
    kind: "surah" | "ayah",
    requestedAyah = selectedAyah,
  ) => {
    if (!selectedRecitationId) return;
    if (kind === "ayah" && !requestedAyah) return;
    const requestedSurah = kind === "ayah" ? requestedAyah!.surah : selectedSurah;
    const generation = ++playbackGeneration.current;
    setAyahLoading(true);
    setError(null);
    try {
      const playback = preparedPlayback?.track.surah_number === requestedSurah ? preparedPlayback : await loadPlayback(requestedSurah);
      if (generation !== playbackGeneration.current) return;
      if (kind === "ayah" && !playback.segments?.some((segment) => segment.surah_number === requestedSurah && segment.ayah_number === requestedAyah!.ayah)) {
        setError(t("quran.readerAyahUnavailable"));
        return;
      }
      if (requestedSurah === selectedSurah) setPreparedPlayback(playback);
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
      if (generation === playbackGeneration.current) setError(api.normalizeError(reason));
    } finally {
      if (generation === playbackGeneration.current) setAyahLoading(false);
    }
  }, [
    preparedPlayback,
    loadPlayback,
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
            onChange={(event) => selectRecitation(event.target.value)}
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
          disabled={playbackLoading || ayahLoading || !preparedPlayback}
        >
          {playbackLoading || ayahLoading ? t("common.loading") : `▶ ${t("common.surah", { surah: selectedSurah })}`}
        </button>
        <button
          className="btn btn-secondary"
          type="button"
          onClick={() => void startPlayback("ayah")}
          disabled={playbackLoading || ayahLoading || !preparedPlayback || !selectedAyah}
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
        pauseOnNavigationKey={readerScopeKey}
        readerControls={reader?.immersive ? {
          container: reader.audioSlot,
          ayahKey: readerAyahKey,
          artist: selectedRecitation ? reciterName(selectedRecitation.reciter, locale) : "",
          loading: catalogLoading || playbackLoading || ayahLoading,
          available: Boolean(selectedRecitationId),
          error,
          onPlayAyah: () => void startPlayback("ayah", parseAyahKey(readerAyahKey)),
        } : undefined}
      />
    </div>
  );
}
