"use client";

import { useSearchParams } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import {
  api,
  AudioTrack,
  Recitation,
  Reciter,
} from "../../lib/api";
import { ReciterAvatar } from "../../components/ReciterAvatar";
import type { AudioPlaybackRequest } from "../../components/SegmentedAudioPlayer";
import { useAudioPlayer } from "../../lib/audio-player-context";
import { useI18n } from "../../lib/i18n-context";
import {
  groupRecitersByPerson,
  latestRecitationsByVariant,
  reciterPersonKey,
  reciterSourcesForPerson,
} from "../../lib/reciter-catalog";
import { reciterPortraitUrl } from "../../lib/reciter-portraits";

export default function AudioPage() {
  const searchParams = useSearchParams();
  const requestedReciterId = searchParams.get("reciter");
  const { locale, t, formatNumber } = useI18n();
  const { request: playerRequest, isPlaying, startPlayback } = useAudioPlayer();
  const [reciterSources, setReciterSources] = useState<Reciter[]>([]);
  const [reciters, setReciters] = useState<Reciter[]>([]);
  const [selectedReciterId, setSelectedReciterId] = useState<string>("");
  const [recitations, setRecitations] = useState<Recitation[]>([]);
  const [selectedRecitationId, setSelectedRecitationId] = useState<string>("");
  const [tracks, setTracks] = useState<AudioTrack[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

  const [loadingTrackId, setLoadingTrackId] = useState<string | null>(null);
  const requestIdRef = useRef(0);

  // Load reciters on mount
  useEffect(() => {
    setLoading(true);
    api
      .getReciters()
      .then((res) => {
        const availableReciters = res.results || [];
        const people = groupRecitersByPerson(availableReciters);
        setReciterSources(availableReciters);
        setReciters(people);
        if (people.length > 0) {
          const requestedSource = availableReciters.find((item) => item.id === requestedReciterId);
          const requestedPerson = requestedSource
            ? people.find((item) => reciterPersonKey(item) === reciterPersonKey(requestedSource))
            : undefined;
          setSelectedReciterId(requestedPerson?.id || people[0].id);
        }
        setLoading(false);
      })
      .catch((err) => {
        setError(api.normalizeError(err));
        setLoading(false);
      });
  }, [requestedReciterId]);

  // Load recitations when reciter changes
  useEffect(() => {
    if (!selectedReciterId) return;
    const selected = reciters.find((reciter) => reciter.id === selectedReciterId);
    if (!selected) return;
    const sources = reciterSourcesForPerson(reciterSources, selected);
    let cancelled = false;
    setLoading(true);
    Promise.all(sources.map((source) => api.getRecitations({ reciter_id: source.id })))
      .then((responses) => {
        if (cancelled) return;
        const available = latestRecitationsByVariant(
          responses.flatMap((response) => response.results || []),
        );
        setRecitations(available);
        if (available.length > 0) {
          setSelectedRecitationId(available[0].id);
        } else {
          setSelectedRecitationId("");
          setTracks([]);
        }
        setLoading(false);
      })
      .catch((err) => {
        if (cancelled) return;
        setError(api.normalizeError(err));
        setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [reciterSources, reciters, selectedReciterId]);

  // Load tracks when recitation changes
  useEffect(() => {
    if (!selectedRecitationId) return;
    setLoading(true);
    api
      .getTracks(selectedRecitationId, { scope: "surah", page_size: 114 })
      .then((res) => {
        setTracks(res.results || []);
        setLoading(false);
      })
      .catch((err) => {
        setError(api.normalizeError(err));
        setLoading(false);
      });
  }, [selectedRecitationId]);

  const selectedReciter = reciters.find((r) => r.id === selectedReciterId);
  const selectedRecitation = recitations.find((r) => r.id === selectedRecitationId);
  const reciterName = (reciter: Reciter) =>
    locale === "ar" ? reciter.name_ar : locale === "ru" ? reciter.name_ru : reciter.name_en;
  const reciterSecondaryName = (reciter: Reciter) =>
    locale === "ar" ? reciter.name_en : reciter.name_ar;

  const handlePlayTrack = async (track: AudioTrack) => {
    if (!track.surah_number || !selectedRecitation) return;
    setLoadingTrackId(track.id);
    setError(null);
    try {
      const playback = await api.getSurahPlayback(selectedRecitation.id, track.surah_number);
      requestIdRef.current += 1;
      const request: AudioPlaybackRequest = {
        requestId: requestIdRef.current,
        track: playback.track,
        segments: playback.segments || [],
        kind: "surah",
        title: t("common.surah", { surah: track.surah_number }),
        artist: selectedReciter ? reciterName(selectedReciter) : t("audio.reciterFallback"),
        album: `${selectedRecitation.quran_edition.riwayah} · ${selectedRecitation.style}`,
        autoPlay: true,
      };
      startPlayback(request);
    } catch (reason) {
      setError(api.normalizeError(reason));
    } finally {
      setLoadingTrackId(null);
    }
  };

  const formatDuration = (ms: number) => {
    const totalSecs = Math.floor(ms / 1000);
    const mins = Math.floor(totalSecs / 60);
    const secs = totalSecs % 60;
    return `${mins}:${secs.toString().padStart(2, "0")}`;
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 20 }}>
      {/* Header Controls */}
      <section className="surface">
        <div className="surface-head">
          <div>
            <p className="eyebrow">{t("audio.eyebrow")}</p>
            <h1 className="surface-title">{t("audio.title")}</h1>
            <p className="surface-subtitle">{t("audio.description")}</p>
          </div>
        </div>

        {error && <div className="alert alert-error" style={{ marginBottom: 16 }}>{error}</div>}

        <div className="form-row">
          <div className="form-group">
            <label className="form-label" htmlFor="audio-reciter-select">{t("audio.reciter")}</label>
            <select
              id="audio-reciter-select"
              value={selectedReciterId}
              onChange={(e) => setSelectedReciterId(e.target.value)}
              disabled={reciters.length === 0}
            >
              {reciters.map((r) => (
                <option key={r.id} value={r.id}>
                  {reciterName(r)} — {r.name_ar}
                </option>
              ))}
            </select>
          </div>

          <div className="form-group">
            <label className="form-label" htmlFor="audio-recitation-select">{t("audio.editionStyle")}</label>
            <select
              id="audio-recitation-select"
              value={selectedRecitationId}
              onChange={(e) => setSelectedRecitationId(e.target.value)}
              disabled={recitations.length === 0}
            >
              {recitations.map((rec) => (
                <option key={rec.id} value={rec.id}>
                  {rec.style.toUpperCase()} · {rec.quran_edition.riwayah} ({t("audio.tracksShort", { count: rec.coverage.track_count })})
                </option>
              ))}
            </select>
          </div>
        </div>

        {selectedReciter && (
          <div
            style={{
              marginTop: 16,
              padding: 14,
              background: "var(--bg-subtle)",
              borderRadius: "var(--radius-md)",
              display: "flex",
              justifyContent: "space-between",
              alignItems: "center",
              flexWrap: "wrap",
              gap: 12,
            }}
          >
            <div>
              <strong>{reciterName(selectedReciter)}</strong> ({selectedReciter.name_ar})
              <p className="kpi-desc">
                {t("audio.codeCountry", { code: selectedReciter.slug, country: selectedReciter.country_code || "SA" })}
              </p>
            </div>
            {selectedRecitation && (
              <div style={{ display: "flex", gap: 8 }}>
                <span className="status-chip ok">
                  {selectedRecitation.coverage.complete ? t("audio.complete") : t("audio.surahCoverage", { count: selectedRecitation.coverage.surah_count })}
                </span>
                <span className="status-chip">
                  {t("audio.timings", { status: selectedRecitation.timings.available ? t("common.available") : t("common.processing") })}
                </span>
              </div>
            )}
          </div>
        )}
      </section>

      <section className="surface reciter-showcase" data-testid="audio-reciter-catalog">
        <div className="surface-head">
          <div>
            <p className="eyebrow">{t("home.recitersEyebrow")}</p>
            <h3 className="surface-title">{t("home.recitersTitle")}</h3>
            <p className="surface-subtitle">{t("home.recitersDescription")}</p>
          </div>
        </div>

        {reciters.length > 0 ? (
          <div className="reciter-grid">
            {reciters.map((reciter, index) => {
              const name = reciterName(reciter) || reciter.name_en;
              const isSelected = reciter.id === selectedReciterId;
              return (
                <button
                  className={`reciter-card audio-reciter-card${isSelected ? " is-selected" : ""}`}
                  type="button"
                  key={reciter.id}
                  onClick={() => setSelectedReciterId(reciter.id)}
                  aria-label={t("home.listenReciter", { name })}
                  aria-pressed={isSelected}
                  data-testid="audio-reciter"
                >
                  <ReciterAvatar
                    name={name}
                    portraitUrl={reciterPortraitUrl(reciter)}
                    tone={index}
                  />
                  <span className="reciter-card-copy">
                    <strong>{name}</strong>
                    <span
                      lang={locale === "ar" ? "en" : "ar"}
                      dir={locale === "ar" ? "ltr" : "rtl"}
                    >
                      {reciterSecondaryName(reciter)}
                    </span>
                  </span>
                </button>
              );
            })}
          </div>
        ) : (
          <div className="reciter-empty" aria-live="polite">
            {loading ? t("home.loadingReciters") : t("home.recitersEmpty")}
          </div>
        )}
      </section>

      {/* Tracks List */}
      <section className="surface">
        <div className="surface-head">
          <h3 className="surface-title">{t("audio.trackList")}</h3>
          <span className="kpi-desc">{t("audio.foundTracks", { count: tracks.length })}</span>
        </div>

        {loading ? (
          <div style={{ padding: 32, textAlign: "center", color: "var(--text-muted)" }}>
            {t("audio.loadingTracks")}
          </div>
        ) : tracks.length > 0 ? (
          <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
            {tracks.map((track) => {
              const isSelected = playerRequest?.track.id === track.id;
              return (
                <div
                  key={track.id}
                  className="track-row"
                  style={{
                    borderColor: isSelected ? "var(--primary)" : undefined,
                    background: isSelected ? "var(--primary-subtle)" : undefined,
                  }}
                >
                  <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
                    <span className="ayah-badge" style={{ background: isSelected ? "var(--primary)" : undefined, color: isSelected ? "#fff" : undefined }}>
                      {track.surah_number || "♪"}
                    </span>
                    <div>
                      <strong>
                        {track.surah_number ? t("common.surah", { surah: track.surah_number }) : track.scope}
                      </strong>
                      <p className="kpi-desc">
                        {track.asset.codec.toUpperCase()} · {t("audio.bitrate", { value: formatNumber(track.asset.bitrate_kbps) })} ·{" "}
                        {formatDuration(track.duration_ms)}
                      </p>
                    </div>
                  </div>

                  <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                    <button
                      className={`btn ${isSelected && isPlaying ? "btn-primary" : "btn-secondary"} btn-sm`}
                      onClick={() => void handlePlayTrack(track)}
                      disabled={loadingTrackId === track.id}
                    >
                      {loadingTrackId === track.id
                        ? t("audio.trackLoading")
                        : isSelected && isPlaying
                          ? t("audio.playingButton")
                          : isSelected
                            ? t("audio.continuePlayer")
                            : t("audio.listen")}
                    </button>
                    {track.offline_download_allowed && (
                      <a
                        href={track.asset.url}
                        target="_blank"
                        rel="noreferrer"
                        className="btn btn-secondary btn-sm"
                        title={t("audio.downloadTitle")}
                      >
                        ⬇
                      </a>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        ) : (
          <div style={{ padding: 32, textAlign: "center", color: "var(--text-muted)" }}>
            {t("audio.noTracks")}
          </div>
        )}
      </section>

    </div>
  );
}
