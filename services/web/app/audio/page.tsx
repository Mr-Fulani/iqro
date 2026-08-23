"use client";

import { useEffect, useRef, useState } from "react";
import {
  api,
  AudioTrack,
  Recitation,
  Reciter,
} from "../../lib/api";
import {
  AudioPlaybackRequest,
  SegmentedAudioPlayer,
} from "../../components/SegmentedAudioPlayer";

export default function AudioPage() {
  const [reciters, setReciters] = useState<Reciter[]>([]);
  const [selectedReciterId, setSelectedReciterId] = useState<string>("");
  const [recitations, setRecitations] = useState<Recitation[]>([]);
  const [selectedRecitationId, setSelectedRecitationId] = useState<string>("");
  const [tracks, setTracks] = useState<AudioTrack[]>([]);
  const [loading, setLoading] = useState<boolean>(true);
  const [error, setError] = useState<string | null>(null);

  const [playerRequest, setPlayerRequest] = useState<AudioPlaybackRequest | null>(null);
  const [isPlaying, setIsPlaying] = useState<boolean>(false);
  const [loadingTrackId, setLoadingTrackId] = useState<string | null>(null);
  const requestIdRef = useRef(0);

  // Load reciters on mount
  useEffect(() => {
    setLoading(true);
    api
      .getReciters()
      .then((res) => {
        setReciters(res.results || []);
        if (res.results && res.results.length > 0) {
          setSelectedReciterId(res.results[0].id);
        }
        setLoading(false);
      })
      .catch((err) => {
        setError(api.normalizeError(err));
        setLoading(false);
      });
  }, []);

  // Load recitations when reciter changes
  useEffect(() => {
    if (!selectedReciterId) return;
    setLoading(true);
    api
      .getRecitations({ reciter_id: selectedReciterId })
      .then((res) => {
        setRecitations(res.results || []);
        if (res.results && res.results.length > 0) {
          setSelectedRecitationId(res.results[0].id);
        } else {
          setSelectedRecitationId("");
          setTracks([]);
        }
        setLoading(false);
      })
      .catch((err) => {
        setError(api.normalizeError(err));
        setLoading(false);
      });
  }, [selectedReciterId]);

  // Load tracks when recitation changes
  useEffect(() => {
    if (!selectedRecitationId) return;
    setPlayerRequest(null);
    setIsPlaying(false);
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

  const handlePlayTrack = async (track: AudioTrack) => {
    if (!track.surah_number || !selectedRecitation) return;
    setLoadingTrackId(track.id);
    setError(null);
    try {
      const playback = await api.getSurahPlayback(selectedRecitation.id, track.surah_number);
      requestIdRef.current += 1;
      setPlayerRequest({
        requestId: requestIdRef.current,
        track: playback.track,
        segments: playback.segments || [],
        kind: "surah",
        title: `Сура ${track.surah_number}`,
        artist: selectedReciter?.name_ru || selectedReciter?.name_en || "Чтец",
        album: `${selectedRecitation.quran_edition.riwayah} · ${selectedRecitation.style}`,
        autoPlay: true,
      });
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
            <p className="eyebrow">Аудиозаписи Священного Корана</p>
            <h2 className="surface-title">Каталог чтецов и декламаций</h2>
            <p className="surface-subtitle">
              Выбирайте признанных чтецов, стили чтения (Хафс, Мурраттал) и слушайте с разбивкой по
              сурам и аятам.
            </p>
          </div>
        </div>

        {error && <div className="alert alert-error" style={{ marginBottom: 16 }}>{error}</div>}

        <div className="form-row">
          <div className="form-group">
            <label className="form-label">Чтец (Кари)</label>
            <select
              value={selectedReciterId}
              onChange={(e) => setSelectedReciterId(e.target.value)}
              disabled={reciters.length === 0}
            >
              {reciters.map((r) => (
                <option key={r.id} value={r.id}>
                  {r.name_ru} — {r.name_ar}
                </option>
              ))}
            </select>
          </div>

          <div className="form-group">
            <label className="form-label">Издание и стиль чтения</label>
            <select
              value={selectedRecitationId}
              onChange={(e) => setSelectedRecitationId(e.target.value)}
              disabled={recitations.length === 0}
            >
              {recitations.map((rec) => (
                <option key={rec.id} value={rec.id}>
                  {rec.style.toUpperCase()} · {rec.quran_edition.riwayah} ({rec.coverage.track_count} трек.)
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
              <strong>{selectedReciter.name_ru}</strong> ({selectedReciter.name_ar})
              <p className="kpi-desc">
                Код: {selectedReciter.slug} · Страна: {selectedReciter.country_code || "SA"}
              </p>
            </div>
            {selectedRecitation && (
              <div style={{ display: "flex", gap: 8 }}>
                <span className="status-chip ok">
                  {selectedRecitation.coverage.complete ? "Полный Коран (114 сур)" : `${selectedRecitation.coverage.surah_count} сур`}
                </span>
                <span className="status-chip">
                  Таймкоды аятов: {selectedRecitation.timings.available ? "Доступны" : "В обработке"}
                </span>
              </div>
            )}
          </div>
        )}
      </section>

      {/* Tracks List */}
      <section className="surface">
        <div className="surface-head">
          <h3 className="surface-title">Список аудиодорожек</h3>
          <span className="kpi-desc">Найдено треков: {tracks.length}</span>
        </div>

        {loading ? (
          <div style={{ padding: 32, textAlign: "center", color: "var(--text-muted)" }}>
            Загрузка списка аудиодорожек...
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
                        {track.surah_number ? `Сура ${track.surah_number}` : track.scope}
                      </strong>
                      <p className="kpi-desc">
                        {track.asset.codec.toUpperCase()} · {track.asset.bitrate_kbps} кбит/с ·{" "}
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
                        ? "Загрузка…"
                        : isSelected && isPlaying
                          ? "▶ Играет"
                          : isSelected
                            ? "Продолжить в плеере"
                            : "Слушать"}
                    </button>
                    {track.offline_download_allowed && (
                      <a
                        href={track.asset.url}
                        target="_blank"
                        rel="noreferrer"
                        className="btn btn-secondary btn-sm"
                        title="Скачать трек для офлайн-прослушивания"
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
            Аудиодорожки не найдены для выбранной конфигурации.
          </div>
        )}
      </section>

      {playerRequest && (
        <SegmentedAudioPlayer
          request={playerRequest}
          className="audio-player-bar"
          onPlayingChange={setIsPlaying}
        />
      )}
    </div>
  );
}
