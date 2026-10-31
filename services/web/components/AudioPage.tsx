"use client";

import { useSearchParams } from "next/navigation";
import {
  Suspense,
  useCallback,
  useDeferredValue,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import {
  api,
  AudioTrack,
  Recitation,
  Reciter,
} from "../lib/api";
import type { Surah } from "../lib/api";
import type { PublishedAudioInitialData } from "../lib/public-content";
import { ReciterAvatar } from "./ReciterAvatar";
import { heldSurahs } from "../lib/listening-queue";
import type { ListeningQueue } from "../lib/listening-queue";
import { formatClock, reciterName as localizedReciterName } from "../lib/audio-content";
import { useAudioPlayer } from "../lib/audio-player-context";
import { useI18n } from "../lib/i18n-context";
import {
  groupRecitersByPerson,
  latestRecitationsByVariant,
  recitationHasSurah,
  recitationStyleLabel,
  recitationVariantLabel,
  reciterSearch,
  reciterPersonKey,
  reciterSourcesForPerson,
} from "../lib/reciter-catalog";
import { reciterPortraitUrl } from "../lib/reciter-portraits";
import {
  loadReciterPreference,
  preferredRecitation,
  preferredReciter,
  rememberReciterPreference,
} from "../lib/reciter-preference";
import { useHydrated } from "../lib/use-hydrated";
import { SurahNameArt } from "./SurahNameArt";

// useSearchParams() renders its subtree in the browser only, so it stays out of
// the server-rendered catalog and reports the requested reciter after hydration.
const COLLAPSED_RECITER_COUNT = 30;

function RequestedReciter({ onChange }: { onChange: (reciterId: string | null) => void }) {
  const reciterId = useSearchParams().get("reciter");
  useEffect(() => onChange(reciterId), [onChange, reciterId]);
  return null;
}

export default function AudioPage({ initialData }: { initialData?: PublishedAudioInitialData }) {
  // Server HTML already lists the tracks; a click before hydration would be lost.
  const hydrated = useHydrated();
  // undefined until the browser has read the query string.
  const [requestedReciterId, setRequestedReciterId] = useState<string | null>();
  const { locale, t, formatNumber } = useI18n();
  const {
    request: playerRequest,
    isPlaying,
    startQueue,
    resumePlayback,
    clearPlayback,
    setReciterControls,
  } = useAudioPlayer();
  const [reciterSources, setReciterSources] = useState<Reciter[]>(initialData?.reciters ?? []);
  const [reciters, setReciters] = useState<Reciter[]>(
    () => groupRecitersByPerson(initialData?.reciters ?? []),
  );
  const [selectedReciterId, setSelectedReciterId] = useState<string>(initialData?.reciterId ?? "");
  const [reciterQuery, setReciterQuery] = useState("");
  const deferredReciterQuery = useDeferredValue(reciterQuery);
  const [showAllReciters, setShowAllReciters] = useState(false);
  const [selectionReady, setSelectionReady] = useState(false);
  const [recitations, setRecitations] = useState<Recitation[]>(initialData?.recitations ?? []);
  const [selectedRecitationId, setSelectedRecitationId] = useState<string>(
    initialData?.recitationId ?? "",
  );
  const [tracks, setTracks] = useState<AudioTrack[]>(initialData?.tracks ?? []);
  const [surahs, setSurahs] = useState<Surah[]>(initialData?.surahs ?? []);
  const [loading, setLoading] = useState<boolean>(!initialData);
  const [error, setError] = useState<string | null>(null);

  const [loadingTrackId, setLoadingTrackId] = useState<string | null>(null);
  const pendingReciterPlaybackRef = useRef<{ reciterId: string; surahNumber: number } | null>(null);

  // Choose the reciter once the query string and the saved preference are known.
  useEffect(() => {
    if (requestedReciterId === undefined) return;
    let cancelled = false;
    const applyCatalog = (availableReciters: Reciter[]) => {
      const people = groupRecitersByPerson(availableReciters);
      setReciterSources(availableReciters);
      setReciters(people);
      if (people.length > 0) {
        const requestedSource = availableReciters.find((item) => item.id === requestedReciterId);
        const requestedPerson = requestedSource
          ? people.find((item) => reciterPersonKey(item) === reciterPersonKey(requestedSource))
          : undefined;
        const selected =
          requestedPerson ||
          preferredReciter(people, loadReciterPreference("listening")) ||
          people[0];
        setSelectedReciterId(selected.id);
        rememberReciterPreference(selected, null, "listening");
      }
      setSelectionReady(true);
      setLoading(false);
    };
    if (initialData) {
      applyCatalog(initialData.reciters);
      return;
    }
    setLoading(true);
    api
      .getAllReciters()
      .then((availableReciters) => {
        if (!cancelled) applyCatalog(availableReciters);
      })
      .catch((err) => {
        if (cancelled) return;
        setError(api.normalizeError(err));
        setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [initialData, requestedReciterId]);

  // Load recitations when reciter changes
  useEffect(() => {
    if (!selectionReady || !selectedReciterId) return;
    const selected = reciters.find((reciter) => reciter.id === selectedReciterId);
    if (!selected) return;
    let cancelled = false;
    const applyRecitations = (available: Recitation[]) => {
      setRecitations(available);
      if (available.length > 0) {
        const selectedRecitation =
          preferredRecitation(available, loadReciterPreference("listening")) || available[0];
        setSelectedRecitationId(selectedRecitation.id);
        rememberReciterPreference(
          selectedRecitation.reciter,
          selectedRecitation,
          "listening",
        );
      } else {
        setSelectedRecitationId("");
        setTracks([]);
      }
      setLoading(false);
    };
    if (initialData && selectedReciterId === initialData.reciterId) {
      applyRecitations(initialData.recitations);
      return;
    }
    const sources = reciterSourcesForPerson(reciterSources, selected);
    setLoading(true);
    Promise.all(sources.map((source) => api.getAllRecitations({ reciter_id: source.id })))
      .then((responses) => {
        if (!cancelled) applyRecitations(latestRecitationsByVariant(responses.flat(), "listen"));
      })
      .catch((err) => {
        if (cancelled) return;
        setError(api.normalizeError(err));
        setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [initialData, reciterSources, reciters, selectedReciterId, selectionReady]);

  // Load tracks when recitation changes
  useEffect(() => {
    if (!selectedRecitationId) return;
    if (initialData && selectedRecitationId === initialData.recitationId) {
      setTracks(initialData.tracks);
      setLoading(false);
      return;
    }
    let cancelled = false;
    setLoading(true);
    api
      .getTracks(selectedRecitationId, { scope: "surah", page_size: 114 })
      .then((res) => {
        if (cancelled) return;
        setTracks(res.results || []);
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
  }, [initialData, selectedRecitationId]);

  const selectedReciter = reciters.find((r) => r.id === selectedReciterId);
  const selectedRecitation = recitations.find((r) => r.id === selectedRecitationId);
  const reciterName = useCallback(
    (reciter: Reciter) => localizedReciterName(reciter, locale) || reciter.name_ar,
    [locale],
  );
  const reciterSecondaryName = useCallback(
    (reciter: Reciter) => locale === "ar" ? reciter.name_en : reciter.name_ar,
    [locale],
  );

  // The player moves through this reciter's recordings by itself (docs/audio-listening-queue.md).
  const listeningQueue = useMemo<ListeningQueue | null>(() => {
    if (!selectedReciter || !selectedRecitation) return null;
    return {
      reciterId: selectedReciter.id,
      artist: reciterName(selectedReciter),
      artworkUrl: reciterPortraitUrl(selectedReciter),
      variantId: selectedRecitation.id,
      variants: recitations.map((recitation) => ({
        id: recitation.id,
        label: recitationVariantLabel(recitation, t),
        editionCode: recitation.quran_edition.code,
        surahNumbers: recitation.coverage.surah_numbers ?? [],
      })),
    };
  }, [reciterName, recitations, selectedRecitation, selectedReciter, t]);

  // A recording chosen in the player shows here too.
  const playerQueue = playerRequest?.queue;
  useEffect(() => {
    if (!playerQueue || playerQueue.reciterId !== selectedReciterId) return;
    if (playerQueue.variantId === selectedRecitationId) return;
    const recitation = recitations.find((item) => item.id === playerQueue.variantId);
    if (!recitation) return;
    rememberReciterPreference(recitation.reciter, recitation, "listening");
    setSelectedRecitationId(recitation.id);
  }, [playerQueue, recitations, selectedRecitationId, selectedReciterId]);

  const rememberCurrentTrackFor = useCallback((reciterId: string) => {
    const surahNumber = playerRequest?.track.surah_number;
    pendingReciterPlaybackRef.current = surahNumber ? { reciterId, surahNumber } : null;
    clearPlayback();
  }, [clearPlayback, playerRequest]);

  const selectReciter = useCallback((reciterId: string) => {
    if (reciterId === selectedReciterId) return;
    const reciter = reciters.find((item) => item.id === reciterId);
    if (reciter) rememberReciterPreference(reciter, null, "listening");
    rememberCurrentTrackFor(reciterId);
    setRecitations([]);
    setSelectedRecitationId("");
    setTracks([]);
    setSelectedReciterId(reciterId);
  }, [reciters, rememberCurrentTrackFor, selectedReciterId]);

  const selectRecitation = useCallback((recitationId: string) => {
    if (recitationId === selectedRecitationId) return;
    const recitation = recitations.find((item) => item.id === recitationId);
    if (recitation) {
      rememberReciterPreference(recitation.reciter, recitation, "listening");
    }
    rememberCurrentTrackFor(selectedReciterId);
    setTracks([]);
    setSelectedRecitationId(recitationId);
  }, [recitations, rememberCurrentTrackFor, selectedRecitationId, selectedReciterId]);

  const searchReciters = useMemo(() => reciterSearch(reciters), [reciters]);
  const foundReciters = useMemo(
    () => searchReciters(deferredReciterQuery),
    [deferredReciterQuery, searchReciters],
  );
  // Hundreds of cards would weigh down the page, so it opens a short list;
  // the search still reads all of them. The chosen reciter stays in view.
  const shownReciters = useMemo(() => {
    if (showAllReciters || deferredReciterQuery.trim()) return foundReciters;
    const shown = foundReciters.slice(0, COLLAPSED_RECITER_COUNT);
    const selected = foundReciters.find((reciter) => reciter.id === selectedReciterId);
    return selected && !shown.includes(selected) ? [selected, ...shown] : shown;
  }, [deferredReciterQuery, foundReciters, selectedReciterId, showAllReciters]);

  const reciterControlOptions = useMemo(() => reciters.map((reciter) => ({
    value: reciter.id,
    label: `${reciterName(reciter)} — ${reciter.name_ar}`,
  })), [reciterName, reciters]);

  useEffect(() => {
    setReciterControls({
      value: selectedReciterId,
      options: reciterControlOptions,
      disabled: reciters.length === 0,
      onChange: selectReciter,
    });
    return () => setReciterControls(null);
  }, [reciterControlOptions, reciters.length, selectReciter, selectedReciterId, setReciterControls]);

  useEffect(() => {
    const editionCode = selectedRecitation?.quran_edition.code;
    if (!editionCode) {
      setSurahs([]);
      return;
    }
    if (initialData && editionCode === initialData.editionCode) {
      setSurahs(initialData.surahs);
      return;
    }
    let cancelled = false;
    api.getSurahs(editionCode)
      .then((items) => {
        if (!cancelled) setSurahs(items);
      })
      .catch(() => {
        if (!cancelled) setSurahs([]);
      });
    return () => {
      cancelled = true;
    };
  }, [initialData, selectedRecitation?.quran_edition.code]);

  useEffect(() => {
    const pending = pendingReciterPlaybackRef.current;
    if (
      !pending ||
      !selectedRecitation ||
      !selectedReciter ||
      pending.reciterId !== selectedReciterId
    ) {
      return;
    }

    if (!recitationHasSurah(selectedRecitation, pending.surahNumber)) {
      // This recording does not hold the surah that was playing; the listener
      // picks one of its surahs from the list instead of seeing an error.
      pendingReciterPlaybackRef.current = null;
      return;
    }
    if (!listeningQueue || listeningQueue.variantId !== selectedRecitation.id) return;
    let cancelled = false;
    setLoadingTrackId(`reciter-switch-${pending.surahNumber}`);
    setError(null);
    startQueue(listeningQueue, pending.surahNumber, { autoPlay: false })
      .then(() => {
        if (!cancelled && pendingReciterPlaybackRef.current === pending) pendingReciterPlaybackRef.current = null;
      })
      .catch((reason) => {
        if (!cancelled) {
          pendingReciterPlaybackRef.current = null;
          setError(api.normalizeError(reason));
        }
      })
      .finally(() => {
        if (!cancelled) setLoadingTrackId(null);
      });
    return () => {
      cancelled = true;
    };
  }, [listeningQueue, selectedRecitation, selectedReciter, selectedReciterId, startQueue]);

  const surahByNumber = useMemo(
    () => new Map(surahs.map((surah) => [surah.number, surah])),
    [surahs],
  );

  const playFrom = async (surah: number, loadingId: string, wholeQuran = false) => {
    if (!listeningQueue) return;
    setLoadingTrackId(loadingId);
    setError(null);
    try {
      await startQueue(listeningQueue, surah, { wholeQuran });
    } catch (reason) {
      setError(api.normalizeError(reason));
    } finally {
      setLoadingTrackId(null);
    }
  };

  const handlePlayTrack = (track: AudioTrack) => {
    if (track.surah_number) void playFrom(track.surah_number, track.id);
  };

  const firstHeldSurah = selectedRecitation
    ? heldSurahs(selectedRecitation.coverage.surah_numbers)[0]
    : undefined;
  // The player rests on a saved place: one tap plays on from it.
  const restingPlace = playerRequest?.queue && !isPlaying && playerRequest.startPositionMs
    && playerRequest.track.surah_number
    ? { surah: playerRequest.track.surah_number, time: formatClock(playerRequest.startPositionMs) }
    : null;

  return (
    <div className="audio-page">
      <Suspense fallback={null}>
        <RequestedReciter onChange={setRequestedReciterId} />
      </Suspense>
      {/* Header Controls */}
      <section className="surface audio-controls">
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
              onChange={(e) => selectReciter(e.target.value)}
              disabled={!hydrated || reciters.length === 0}
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
              onChange={(e) => selectRecitation(e.target.value)}
              disabled={!hydrated || recitations.length === 0}
            >
              {recitations.map((rec) => (
                <option key={rec.id} value={rec.id}>
                  {recitationStyleLabel(rec.style, t)} · {rec.quran_edition.riwayah} ({t("audio.tracksShort", { count: rec.coverage.track_count })})
                </option>
              ))}
            </select>
          </div>
        </div>

        {(firstHeldSurah !== undefined || restingPlace) && (
          <div className="audio-queue-actions">
            {firstHeldSurah !== undefined && (
              <button
                type="button"
                className="btn btn-primary"
                onClick={() => void playFrom(firstHeldSurah, "whole-quran", true)}
                disabled={!hydrated || !listeningQueue || loadingTrackId === "whole-quran"}
                data-testid="audio-whole-quran"
              >
                <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M8 5v14l11-7z" /></svg>
                {t("audio.listenWholeQuran")}
              </button>
            )}
            {restingPlace && (
              <button type="button" className="btn btn-secondary audio-continue-place" onClick={resumePlayback}>
                <span>{t("audio.continueFrom")}</span>
                <strong>{t("audio.continuePlace", restingPlace)}</strong>
              </button>
            )}
          </div>
        )}

        {selectedReciter && (
          <div className="audio-reciter-summary">
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
          <input
            aria-label={t("audio.searchReciters")}
            className="reciter-search"
            data-testid="audio-reciter-search"
            onChange={(event) => setReciterQuery(event.target.value)}
            placeholder={t("audio.searchReciters")}
            type="search"
            value={reciterQuery}
          />
        ) : null}

        {shownReciters.length > 0 ? (
          <div className="reciter-grid">
            {shownReciters.map((reciter, index) => {
              const name = reciterName(reciter) || reciter.name_en;
              const isSelected = reciter.id === selectedReciterId;
              return (
                <button
                  className={`reciter-card audio-reciter-card${isSelected ? " is-selected" : ""}`}
                  type="button"
                  key={reciter.id}
                  onClick={() => selectReciter(reciter.id)}
                  disabled={!hydrated}
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
                      {/* Arabic names are shown after hydration: near the first
                          screen their Amiri faces would compete with the
                          server-rendered text. */}
                      {hydrated && reciterSecondaryName(reciter)}
                    </span>
                  </span>
                </button>
              );
            })}
            {shownReciters.length < foundReciters.length ? (
              <button
                className="btn btn-secondary reciter-show-all"
                data-testid="audio-show-all-reciters"
                onClick={() => setShowAllReciters(true)}
                type="button"
              >
                {t("audio.showAllReciters", { count: foundReciters.length })}
              </button>
            ) : null}
          </div>
        ) : (
          <div className="reciter-empty" aria-live="polite">
            {loading
              ? t("home.loadingReciters")
              : reciters.length > 0
                ? t("audio.noRecitersFound")
                : t("home.recitersEmpty")}
          </div>
        )}
      </section>

      {/* Tracks List */}
      <section className="surface audio-tracks">
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
              const trackSurah = track.surah_number
                ? surahByNumber.get(track.surah_number)
                : undefined;
              return (
                <div
                  key={track.id}
                  className="track-row"
                  style={{
                    borderColor: isSelected ? "var(--primary)" : undefined,
                    background: isSelected ? "var(--primary-subtle)" : undefined,
                  }}
                >
                  <div className="track-row-main">
                    <span className="ayah-badge" style={{ background: isSelected ? "var(--primary)" : undefined, color: isSelected ? "#fff" : undefined }}>
                      {track.surah_number || "♪"}
                    </span>
                    <div className="track-row-copy">
                      <strong>
                        {track.surah_number ? t("common.surah", { surah: track.surah_number }) : track.scope}
                      </strong>
                      <p className="kpi-desc">
                        {track.asset.codec.toUpperCase()} · {t("audio.bitrate", { value: formatNumber(track.asset.bitrate_kbps) })} ·{" "}
                        {formatClock(track.duration_ms)}
                      </p>
                    </div>
                    {hydrated && trackSurah?.name_ar && (
                      <SurahNameArt
                        surah={trackSurah.number}
                        fallback={trackSurah.name_ar}
                        className="track-surah-name-ar"
                      />
                    )}
                  </div>

                  <div className="track-row-actions">
                    <button
                      className={`btn ${isSelected && isPlaying ? "btn-primary" : "btn-secondary"} btn-sm`}
                      onClick={() => handlePlayTrack(track)}
                      disabled={!hydrated || loadingTrackId === track.id}
                    >
                      {loadingTrackId === track.id
                        ? t("audio.trackLoading")
                        : isSelected && isPlaying
                          ? t("audio.playingButton")
                          : isSelected
                            ? t("audio.continuePlayer")
                            : t("audio.listenFrom")}
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
