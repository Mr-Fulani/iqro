"use client";

import {
  Suspense,
  type PointerEvent as ReactPointerEvent,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { useSearchParams } from "next/navigation";
import {
  MushafAudioPlayer,
  type AyahPlaybackTrigger,
} from "../../components/MushafAudioPlayer";
import { QuranFoundationMushafPageView } from "../../components/QuranFoundationMushafPage";
import {
  PrayerReadingSessionBar,
  type PrayerReadingSessionConfig,
} from "../../components/PrayerReadingSessionBar";
import { ReadingActivityTracker } from "../../components/ReadingActivityTracker";
import type {
  AudioPlayerControlRequest,
  AudioPlaybackSettings,
} from "../../components/SegmentedAudioPlayer";
import {
  api,
  Ayah,
  Hizb,
  Juz,
  MushafPage,
  QuranDivision,
  QuranEdition,
  QuranFoundationMushaf,
  QuranFoundationMushafPage,
  RubElHizb,
  Surah,
  type PrayerReadingPrayer,
} from "../../lib/api";
import { useAuth } from "../../lib/auth-context";
import { useI18n } from "../../lib/i18n-context";

function positiveInteger(value: string | null): number | null {
  if (value === null || !/^\d+$/.test(value)) return null;
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null;
}

function nonNegativeInteger(value: string | null): number | null {
  if (value === null || !/^\d+$/.test(value)) return null;
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) ? parsed : null;
}

const PRAYER_READING_PRAYERS = new Set<PrayerReadingPrayer>([
  "fajr",
  "dhuhr",
  "asr",
  "maghrib",
  "isha",
]);

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function QuranContent() {
  const searchParams = useSearchParams();
  const deepLinkSurah = positiveInteger(searchParams.get("surah")) || 1;
  const deepLinkAyah = positiveInteger(searchParams.get("ayah"));
  const deepLinkKey = deepLinkAyah === null ? null : `${deepLinkSurah}:${deepLinkAyah}`;

  const prayerReadingConfig = useMemo<PrayerReadingSessionConfig | null>(() => {
    if (searchParams.get("mode") !== "after-prayer") return null;
    const prayer = searchParams.get("prayer") as PrayerReadingPrayer | null;
    const localDate = searchParams.get("prayer_date");
    const timezoneName = searchParams.get("prayer_timezone");
    const targetPages = positiveInteger(searchParams.get("prayer_target"));
    const creditedPages = nonNegativeInteger(searchParams.get("prayer_credited")) ?? 0;
    const checkInId = searchParams.get("check_in_id");
    const checkInRevision = positiveInteger(searchParams.get("check_in_revision"));
    const hasValidExistingCheckIn = checkInId !== null || checkInRevision !== null
      ? Boolean(checkInId && UUID_PATTERN.test(checkInId) && checkInRevision)
      : true;
    if (
      prayer === null
      || !PRAYER_READING_PRAYERS.has(prayer)
      || localDate === null
      || !/^\d{4}-\d{2}-\d{2}$/.test(localDate)
      || timezoneName === null
      || timezoneName.length > 64
      || targetPages === null
      || targetPages > 20
      || creditedPages > 604
      || !hasValidExistingCheckIn
    ) {
      return null;
    }
    return {
      prayer,
      localDate,
      timezoneName,
      targetPages,
      creditedPages,
      checkInId,
      checkInRevision,
    };
  }, [searchParams]);

  const { isLoggedIn, isLoading: authLoading, loginGuest, session } = useAuth();
  const { formatNumber, locale, t } = useI18n();
  const [editions, setEditions] = useState<QuranEdition[]>([]);
  const [selectedEdition, setSelectedEdition] = useState<string>("madani-hafs");
  const [surahs, setSurahs] = useState<Surah[]>([]);
  const [selectedSurah, setSelectedSurah] = useState<number>(deepLinkSurah);
  const [ayahs, setAyahs] = useState<Ayah[]>([]);
  const [juz, setJuz] = useState<Juz[]>([]);
  const [hizb, setHizb] = useState<Hizb[]>([]);
  const [rubElHizb, setRubElHizb] = useState<RubElHizb[]>([]);
  const [currentPage, setCurrentPage] = useState<number>(1);
  const [mushafPage, setMushafPage] = useState<MushafPage | null>(null);
  const [mushafPageLoading, setMushafPageLoading] = useState(false);
  const [foundationMushafs, setFoundationMushafs] = useState<QuranFoundationMushaf[]>([]);
  const [selectedFoundationMushafId, setSelectedFoundationMushafId] = useState<number | null>(null);
  const [foundationMushafPage, setFoundationMushafPage] = useState<QuranFoundationMushafPage | null>(null);
  const [foundationPageLoading, setFoundationPageLoading] = useState(false);
  const [selectedMushafAyah, setSelectedMushafAyah] = useState<string | null>(null);
  const [playingMushafAyah, setPlayingMushafAyah] = useState<string | null>(null);
  const [isAudioPlaying, setIsAudioPlaying] = useState(false);
  const [playAyahRequest, setPlayAyahRequest] = useState<AyahPlaybackTrigger | null>(null);
  const [playerControlRequest, setPlayerControlRequest] = useState<AudioPlayerControlRequest | null>(null);
  const [audioSettings, setAudioSettings] = useState<AudioPlaybackSettings>({
    repeatMode: "off",
    playbackRate: 1,
  });
  const pendingNavigationPage = useRef<number | null>(null);
  const handledDeepLink = useRef<string | null>(null);
  const handledPrayerReadingStart = useRef(false);
  const ayahPlaybackRequestId = useRef(0);
  const playerControlRequestId = useRef(0);
  const selectedFoundationMushaf = useMemo(
    () => foundationMushafs.find((mushaf) => mushaf.source_id === selectedFoundationMushafId) || null,
    [foundationMushafs, selectedFoundationMushafId],
  );
  const mushafPageCount = selectedFoundationMushaf?.pages_count || 604;

  const [viewMode, setViewMode] = useState<"text" | "mushaf">(
    deepLinkAyah === null && prayerReadingConfig === null ? "text" : "mushaf",
  );
  const [prayerReadingReady, setPrayerReadingReady] = useState(
    prayerReadingConfig === null,
  );
  const [pageTurnDirection, setPageTurnDirection] = useState<"next" | "previous">("next");
  const previousPage = useRef(currentPage);
  const mushafReader = useRef<HTMLElement | null>(null);
  const swipeStart = useRef<{ x: number; y: number } | null>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [feedbackMessage, setFeedbackMessage] = useState<{ text: string; type: "ok" | "err" } | null>(null);

  // Load Editions
  useEffect(() => {
    api
      .getEditions()
      .then((res) => {
        setEditions(res);
        if (res.length > 0) {
          const defaultEd = res.find((e) => e.code === "madani-hafs") || res[0];
          setSelectedEdition(defaultEd.code);
        }
      })
      .catch((err) => {
        setFeedbackMessage({ text: api.normalizeError(err), type: "err" });
      });
  }, []);

  // Display variants are independent from the published Quran text edition.
  useEffect(() => {
    api
      .getQuranFoundationMushafs()
      .then((mushafs) => {
        const renderable = mushafs.filter(
          (mushaf) =>
            mushaf.rendering.available &&
            (mushaf.rendering.mode === "page-font" || mushaf.rendering.mode === "unicode-font"),
        );
        setFoundationMushafs(renderable);
        setSelectedFoundationMushafId((sourceId) =>
          sourceId !== null && renderable.some((mushaf) => mushaf.source_id === sourceId)
            ? sourceId
            : null,
        );
      })
      .catch(() => {
        setFoundationMushafs([]);
        setSelectedFoundationMushafId(null);
      });
  }, []);

  // Load Surahs when edition changes
  useEffect(() => {
    if (!selectedEdition) return;
    setLoading(true);
    Promise.all([
      api.getSurahs(selectedEdition),
      api.getJuzList(selectedEdition),
      api.getHizbList(selectedEdition),
      api.getRubElHizbList(selectedEdition),
    ])
      .then(([surahList, juzList, hizbList, rubList]) => {
        setSurahs(surahList);
        setJuz(juzList);
        setHizb(hizbList);
        setRubElHizb(rubList);
        setLoading(false);
      })
      .catch((err) => {
        setLoading(false);
        setFeedbackMessage({ text: api.normalizeError(err), type: "err" });
      });
  }, [selectedEdition]);

  // Load Ayahs when surah changes
  useEffect(() => {
    if (!selectedEdition || !selectedSurah) return;
    setLoading(true);
    api
      .getAyahs(selectedEdition, selectedSurah)
      .then((res) => {
        setAyahs(res);
        setLoading(false);
        if (pendingNavigationPage.current !== null) {
          setCurrentPage(pendingNavigationPage.current);
          pendingNavigationPage.current = null;
        } else if (res.length > 0 && res[0].pages?.length > 0) {
          setCurrentPage(res[0].pages[0]);
        }
      })
      .catch((err) => {
        setLoading(false);
        setFeedbackMessage({ text: api.normalizeError(err), type: "err" });
      });
  }, [selectedEdition, selectedSurah]);

  // Notification links include the first ayah of a review range. Wait until
  // that surah's ayahs are loaded, then open its Mushaf page and highlight it.
  useEffect(() => {
    if (deepLinkKey === null || deepLinkAyah === null || handledDeepLink.current === deepLinkKey) {
      return;
    }
    setViewMode("mushaf");
    if (selectedSurah !== deepLinkSurah) {
      setSelectedSurah(deepLinkSurah);
      return;
    }
    const linkedAyah = ayahs.find(
      (ayah) => ayah.surah_number === deepLinkSurah && ayah.number === deepLinkAyah,
    );
    if (!linkedAyah?.pages.length) return;
    setSelectedMushafAyah(deepLinkKey);
    setCurrentPage(linkedAyah.pages[0]);
    handledDeepLink.current = deepLinkKey;
  }, [ayahs, deepLinkAyah, deepLinkKey, deepLinkSurah, selectedSurah]);

  useEffect(() => {
    if (
      prayerReadingConfig === null
      || handledPrayerReadingStart.current
      || authLoading
      || !selectedEdition
    ) {
      return;
    }
    handledPrayerReadingStart.current = true;
    setViewMode("mushaf");
    if (!session) {
      setPrayerReadingReady(true);
      return;
    }
    api.getReadingPosition(selectedEdition)
      .then((position) => {
        const positionSurah = position.ayah?.surah_number || selectedSurah;
        setCurrentPage(position.page_number);
        if (positionSurah === selectedSurah) {
          return;
        }
        pendingNavigationPage.current = position.page_number;
        setSelectedSurah(positionSurah);
      })
      .catch(() => {
        // A new reader starts from the first available Mushaf page.
      })
      .finally(() => {
        setPrayerReadingReady(true);
      });
  }, [authLoading, prayerReadingConfig, selectedEdition, selectedSurah, session]);

  // Load Mushaf page when page changes and in mushaf mode
  useEffect(() => {
    if (currentPage !== previousPage.current) {
      setPageTurnDirection(currentPage > previousPage.current ? "next" : "previous");
      previousPage.current = currentPage;
    }
  }, [currentPage]);

  useEffect(() => {
    if (viewMode !== "mushaf" || !window.matchMedia("(max-width: 768px)").matches) return;
    const timeout = window.setTimeout(() => {
      mushafReader.current?.scrollIntoView({
        behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches
          ? "auto"
          : "smooth",
        block: "start",
      });
    }, 80);
    return () => window.clearTimeout(timeout);
  }, [viewMode]);

  useEffect(() => {
    if (
      viewMode !== "mushaf" ||
      !selectedEdition ||
      !currentPage ||
      selectedFoundationMushafId !== null
    ) {
      setMushafPage(null);
      setMushafPageLoading(false);
      return;
    }
    let cancelled = false;
    setMushafPageLoading(true);
    api
      .getPage(selectedEdition, currentPage)
      .then((pageData) => {
        if (cancelled) return;
        setMushafPage(pageData);
        setMushafPageLoading(false);
        setSelectedMushafAyah((selectedAyah) => {
          if (!selectedAyah) return null;
          const isOnLoadedPage = pageData.regions.some(
            (region) => `${region.ayah.surah}:${region.ayah.number}` === selectedAyah,
          );
          return isOnLoadedPage ? selectedAyah : null;
        });
      })
      .catch(() => {
        if (cancelled) return;
        setMushafPage(null);
        setMushafPageLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [selectedEdition, currentPage, selectedFoundationMushafId, viewMode]);

  useEffect(() => {
    if (
      viewMode !== "mushaf" ||
      selectedFoundationMushafId === null ||
      !selectedFoundationMushaf ||
      !currentPage
    ) {
      setFoundationMushafPage(null);
      setFoundationPageLoading(false);
      return;
    }
    let cancelled = false;
    setFoundationMushafPage(null);
    setFoundationPageLoading(true);
    api
      .getQuranFoundationMushafPage(selectedFoundationMushafId, currentPage)
      .then((pageData) => {
        if (cancelled) return;
        setFoundationMushafPage(pageData);
        setFoundationPageLoading(false);
      })
      .catch((err) => {
        if (cancelled) return;
        setFoundationMushafPage(null);
        setFoundationPageLoading(false);
        setFeedbackMessage({ text: api.normalizeError(err), type: "err" });
      });
    return () => {
      cancelled = true;
    };
  }, [currentPage, selectedFoundationMushaf, selectedFoundationMushafId, viewMode]);

  const currentSurahObj = surahs.find((s) => s.number === selectedSurah);
  const editionName = (edition: QuranEdition) =>
    locale === "ar" ? edition.name_ar : locale === "ru" ? edition.name_ru : edition.name_en;
  const surahName = (surah: Surah) =>
    locale === "ar" ? surah.name_ar : locale === "ru" ? surah.name_ru : surah.name_en;
  const mushafRegions = useMemo(() => {
    const unique = new Map<string, MushafPage["regions"][number]>();
    for (const region of mushafPage?.regions || []) {
      const key = `${region.ayah.surah}:${region.ayah.number}:${JSON.stringify(region.polygon)}`;
      if (!unique.has(key)) unique.set(key, region);
    }
    return [...unique.values()];
  }, [mushafPage]);

  const handleActiveAyahChange = useCallback((ayahKey: string | null) => {
    setPlayingMushafAyah(ayahKey);
    if (!ayahKey) return;
    const [surahNumber, ayahNumber] = ayahKey.split(":").map(Number);
    if (surahNumber !== selectedSurah) return;
    const activeAyah = ayahs.find((ayah) => ayah.number === ayahNumber);
    const nextPage = activeAyah?.pages[0];
    if (viewMode === "mushaf" && nextPage) {
      setCurrentPage((page) => nextPage === page ? page : nextPage);
    }
  }, [ayahs, selectedSurah, viewMode]);

  const navigateToDivision = useCallback((division: QuranDivision) => {
    const targetSurah = division.start_ayah.surah;
    const targetAyah = division.start_ayah.number;
    setViewMode("mushaf");
    setSelectedMushafAyah(`${targetSurah}:${targetAyah}`);
    if (targetSurah === selectedSurah) {
      setCurrentPage(division.start_page);
      return;
    }
    pendingNavigationPage.current = division.start_page;
    setSelectedSurah(targetSurah);
  }, [selectedSurah]);

  const navigateToAyah = useCallback((ayahNumber: number) => {
    const ayah = ayahs.find((item) => item.number === ayahNumber);
    if (!ayah?.pages.length) return;
    setViewMode("mushaf");
    setSelectedMushafAyah(`${selectedSurah}:${ayahNumber}`);
    setCurrentPage(ayah.pages[0]);
  }, [ayahs, selectedSurah]);

  const handlePlayAyah = useCallback((ayahNumber: number) => {
    const ayahKey = `${selectedSurah}:${ayahNumber}`;
    ayahPlaybackRequestId.current += 1;
    setSelectedMushafAyah(ayahKey);
    setPlayAyahRequest({
      requestId: ayahPlaybackRequestId.current,
      ayahKey,
    });
  }, [selectedSurah]);

  const sendPlayerControl = useCallback((action: AudioPlayerControlRequest["action"]) => {
    playerControlRequestId.current += 1;
    setPlayerControlRequest({
      requestId: playerControlRequestId.current,
      action,
    });
  }, []);

  const handleToggleAyahPlayback = useCallback((ayahNumber: number) => {
    const ayahKey = `${selectedSurah}:${ayahNumber}`;
    if (playingMushafAyah === ayahKey) {
      sendPlayerControl("toggle-playback");
      return;
    }
    handlePlayAyah(ayahNumber);
  }, [handlePlayAyah, playingMushafAyah, selectedSurah, sendPlayerControl]);

  const handleToggleAyahRepeat = useCallback((ayahNumber: number) => {
    const ayahKey = `${selectedSurah}:${ayahNumber}`;
    if (playingMushafAyah !== ayahKey) {
      handlePlayAyah(ayahNumber);
      if (audioSettings.repeatMode !== "ayah") {
        sendPlayerControl("toggle-ayah-repeat");
      }
      return;
    }
    sendPlayerControl("toggle-ayah-repeat");
  }, [
    audioSettings.repeatMode,
    handlePlayAyah,
    playingMushafAyah,
    selectedSurah,
    sendPlayerControl,
  ]);

  const turnMushafPage = useCallback((direction: "next" | "previous") => {
    setPageTurnDirection(direction);
    setCurrentPage((page) => direction === "next"
      ? Math.min(mushafPageCount, page + 1)
      : Math.max(1, page - 1));
  }, [mushafPageCount]);

  const handleMushafPointerDown = useCallback((event: ReactPointerEvent<HTMLDivElement>) => {
    const target = event.target as Element;
    if (target.closest("button, a, input, select, [role='button']")) return;
    swipeStart.current = { x: event.clientX, y: event.clientY };
  }, []);

  const handleMushafPointerUp = useCallback((event: ReactPointerEvent<HTMLDivElement>) => {
    const start = swipeStart.current;
    swipeStart.current = null;
    if (!start) return;
    const deltaX = event.clientX - start.x;
    const deltaY = event.clientY - start.y;
    if (Math.abs(deltaX) < 48 || Math.abs(deltaX) < Math.abs(deltaY) * 1.25) return;
    // A Mushaf progresses right-to-left: dragging the page to the right opens
    // the next page, while dragging it to the left returns to the previous one.
    turnMushafPage(deltaX > 0 ? "next" : "previous");
  }, [turnMushafPage]);

  const handleSavePosition = async (ayahNumber?: number) => {
    if (!isLoggedIn) {
      const res = await loginGuest();
      if (!res) {
        setFeedbackMessage({ text: t("quran.savePositionLoginError"), type: "err" });
        return;
      }
    }

    try {
      const progress = ((currentPage / 604) * 100).toFixed(2);
      await api.saveReadingPosition(selectedEdition, {
        page_number: currentPage,
        surah_number: selectedSurah,
        ayah_number: ayahNumber || 1,
        progress_percent: progress,
        base_revision: 0,
      });
      setFeedbackMessage({
        text: t("quran.positionSaved", { surah: selectedSurah, page: currentPage }),
        type: "ok",
      });
      setTimeout(() => setFeedbackMessage(null), 4000);
    } catch (err) {
      setFeedbackMessage({ text: api.normalizeError(err), type: "err" });
    }
  };

  const handleAddBookmark = async (ayahNumber?: number) => {
    if (!isLoggedIn) {
      const res = await loginGuest();
      if (!res) {
        setFeedbackMessage({ text: t("quran.bookmarkLoginError"), type: "err" });
        return;
      }
    }

    try {
      await api.createBookmark({
        edition_code: selectedEdition,
        page_number: currentPage,
        surah_number: selectedSurah,
        ayah_number: ayahNumber || undefined,
        label: t("quran.bookmarkLabel", {
          surah: selectedSurah,
          ayah: ayahNumber || 1,
          page: currentPage,
        }),
        color_key: "emerald",
      });
      setFeedbackMessage({ text: t("quran.bookmarkAdded"), type: "ok" });
      setTimeout(() => setFeedbackMessage(null), 4000);
    } catch (err) {
      setFeedbackMessage({ text: api.normalizeError(err), type: "err" });
    }
  };

  return (
    <div className={`quran-page-layout${viewMode === "mushaf" ? " is-mushaf-mode" : ""}`}>
      {prayerReadingConfig === null ? (
        <ReadingActivityTracker currentPage={currentPage} viewMode={viewMode} />
      ) : prayerReadingReady ? (
        <PrayerReadingSessionBar
          config={prayerReadingConfig}
          currentPage={currentPage}
          edition={selectedEdition}
          surah={selectedSurah}
        />
      ) : (
        <section className="surface prayer-reading-session" aria-live="polite">
          {t("common.loading")}
        </section>
      )}
      {/* Control Bar */}
      <section className="surface quran-control-surface">
        <div className="surface-head" style={{ marginBottom: 16 }}>
          <div>
            <p className="eyebrow">{t("quran.eyebrow")}</p>
            <h1 className="surface-title">
              {currentSurahObj ? `${currentSurahObj.number}. ${surahName(currentSurahObj)} (${currentSurahObj.name_ar})` : t("nav.quran")}
            </h1>
            {currentSurahObj && (
              <p className="surface-subtitle">
                {t("quran.ayahsMeta", {
                  count: currentSurahObj.ayah_count,
                  revelation: currentSurahObj.revelation_type === "meccan" ? t("home.meccan") : t("home.medinan"),
                  page: currentPage,
                })}
              </p>
            )}
          </div>

          <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
            <button
              className={`btn ${viewMode === "text" ? "btn-primary" : "btn-secondary"}`}
              onClick={() => setViewMode("text")}
            >
              {t("quran.textView")}
            </button>
            <button
              className={`btn ${viewMode === "mushaf" ? "btn-primary" : "btn-secondary"}`}
              onClick={() => setViewMode("mushaf")}
            >
              {t("quran.mushafView", { page: currentPage })}
            </button>
            <button
              className="btn btn-outline-primary"
              onClick={() => void handleSavePosition(1)}
              title={t("quran.savePositionTitle")}
            >
              {t("quran.savePosition")}
            </button>
          </div>
        </div>

        {feedbackMessage && (
          <div className={`alert ${feedbackMessage.type === "ok" ? "alert-success" : "alert-error"}`} style={{ marginBottom: 16 }}>
            {feedbackMessage.text}
          </div>
        )}

        <div className="form-row">
          <div className="form-group">
            <label className="form-label">{t("quran.edition")}</label>
            <select
              value={selectedEdition}
              onChange={(e) => setSelectedEdition(e.target.value)}
              disabled={editions.length === 0}
            >
              {editions.map((ed) => (
                <option key={ed.id} value={ed.code}>
                  {editionName(ed)} ({ed.riwayah})
                </option>
              ))}
            </select>
          </div>

          <div className="form-group">
            <label className="form-label" htmlFor="mushaf-variant">
              {t("quran.mushafVariant")}
            </label>
            <select
              id="mushaf-variant"
              value={selectedFoundationMushafId === null ? "image" : String(selectedFoundationMushafId)}
              onChange={(event) => {
                const value = event.target.value;
                setSelectedFoundationMushafId(value === "image" ? null : Number(value));
                setSelectedMushafAyah(null);
              }}
            >
              <option value="image">{t("quran.mushafVariantImage")}</option>
              {foundationMushafs.map((mushaf) => (
                <option value={mushaf.source_id} key={mushaf.source_id}>
                  {mushaf.name} · {mushaf.qirat_name}
                </option>
              ))}
            </select>
          </div>

          <div className="form-group">
            <label className="form-label">{t("quran.surahSelect")}</label>
            <select
              value={selectedSurah}
              onChange={(e) => setSelectedSurah(Number(e.target.value))}
              disabled={surahs.length === 0}
            >
              {surahs.map((s) => (
                <option key={s.id} value={s.number}>
                  {s.number}. {surahName(s)} — {s.name_ar} ({t("quran.ayahsShort", { count: s.ayah_count })})
                </option>
              ))}
            </select>
          </div>

          <div className="form-group">
            <label className="form-label">{t("quran.mushafPage")}</label>
            <div style={{ display: "flex", gap: 8 }}>
              <button
                className="btn btn-secondary btn-sm"
                onClick={() => turnMushafPage("previous")}
                disabled={currentPage <= 1}
              >
                ◀ {t("common.back")}
              </button>
              <input
                type="number"
                min={1}
                max={mushafPageCount}
                value={currentPage}
                onChange={(e) =>
                  setCurrentPage(Math.min(mushafPageCount, Math.max(1, Number(e.target.value))))
                }
                style={{ textAlign: "center", fontWeight: 700 }}
              />
              <button
                className="btn btn-secondary btn-sm"
                onClick={() => turnMushafPage("next")}
                disabled={currentPage >= mushafPageCount}
              >
                {t("common.next")} ▶
              </button>
            </div>
          </div>
        </div>

        <div className="form-row" style={{ marginTop: 14 }}>
          <div className="form-group">
            <label className="form-label" htmlFor="juz-navigation">{t("quran.juz")}</label>
            <select
              id="juz-navigation"
              value=""
              onChange={(event) => {
                const division = juz.find((item) => item.number === Number(event.target.value));
                if (division) navigateToDivision(division);
              }}
              disabled={juz.length === 0}
            >
              <option value="">{t("quran.goJuz")}</option>
              {juz.map((item) => (
                <option key={item.id} value={item.number}>
                  {t("quran.divisionOption", { number: item.number, surah: item.start_ayah.surah, ayah: item.start_ayah.number, page: item.start_page })}
                </option>
              ))}
            </select>
          </div>

          <div className="form-group">
            <label className="form-label" htmlFor="hizb-navigation">{t("quran.hizb")}</label>
            <select
              id="hizb-navigation"
              value=""
              onChange={(event) => {
                const division = hizb.find((item) => item.number === Number(event.target.value));
                if (division) navigateToDivision(division);
              }}
              disabled={hizb.length === 0}
            >
              <option value="">{t("quran.goHizb")}</option>
              {hizb.map((item) => (
                <option key={item.id} value={item.number}>
                  {t("quran.divisionOption", { number: item.number, surah: item.start_ayah.surah, ayah: item.start_ayah.number, page: item.start_page })}
                </option>
              ))}
            </select>
          </div>

          <div className="form-group">
            <label className="form-label" htmlFor="rub-navigation">{t("quran.rub")}</label>
            <select
              id="rub-navigation"
              value=""
              onChange={(event) => {
                const division = rubElHizb.find(
                  (item) => item.number === Number(event.target.value),
                );
                if (division) navigateToDivision(division);
              }}
              disabled={rubElHizb.length === 0}
            >
              <option value="">{t("quran.goRub")}</option>
              {rubElHizb.map((item) => (
                <option key={item.id} value={item.number}>
                  {t("quran.rubOption", { number: item.number, hizb: item.hizb_number, quarter: item.quarter_number, surah: item.start_ayah.surah, ayah: item.start_ayah.number })}
                </option>
              ))}
            </select>
          </div>

          <div className="form-group">
            <label className="form-label" htmlFor="ayah-navigation">
              {t("quran.surahAyah", { count: currentSurahObj?.ayah_count || "—" })}
            </label>
            <select
              id="ayah-navigation"
              value=""
              onChange={(event) => navigateToAyah(Number(event.target.value))}
              disabled={ayahs.length === 0}
            >
              <option value="">{t("quran.goAyah")}</option>
              {ayahs.map((ayah) => (
                <option key={ayah.id} value={ayah.number}>
                  {t("quran.ayahOption", { surah: selectedSurah, ayah: ayah.number, pages: ayah.pages.join(", ") })}
                </option>
              ))}
            </select>
          </div>
        </div>
      </section>

      <section className="surface quran-audio-surface" aria-label={t("audio.playerTitle")}>
        <MushafAudioPlayer
          editionCode={selectedEdition}
          selectedSurah={selectedSurah}
          selectedAyahKey={selectedMushafAyah}
          playAyahRequest={playAyahRequest}
          controlRequest={playerControlRequest}
          onActiveAyahChange={handleActiveAyahChange}
          onPlayingChange={setIsAudioPlaying}
          onSettingsChange={setAudioSettings}
        />
      </section>

      {/* Content Area */}
      {viewMode === "text" ? (
        <section className="surface quran-content-surface">
          {/* Bismillah Header */}
          {selectedSurah !== 1 && selectedSurah !== 9 && (
            <div style={{ textAlign: "center", padding: "16px 0 24px", borderBottom: "1px solid var(--border)" }}>
              <span className="quran-arabic-text" style={{ fontSize: 32, color: "var(--primary)" }}>
                بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ
              </span>
            </div>
          )}

          {loading ? (
            <div style={{ padding: 32, textAlign: "center", color: "var(--text-muted)" }}>
              {t("quran.loadingAyahs")}
            </div>
          ) : ayahs.length > 0 ? (
            <div style={{ display: "flex", flexDirection: "column", gap: 16, marginTop: 16 }}>
              {ayahs.map((ayah) => {
                const ayahKey = `${selectedSurah}:${ayah.number}`;
                const isAyahActive = playingMushafAyah === ayahKey;
                const isAyahPlaying = isAyahActive && isAudioPlaying;
                const isAyahRepeating = isAyahActive && audioSettings.repeatMode === "ayah";
                const playbackActionLabel = isAyahPlaying
                  ? t("player.pausePlayback")
                  : isAyahActive
                    ? t("player.continue")
                    : t("player.play");
                return (
                  <article
                    key={ayah.id}
                    className={`ayah-card${playingMushafAyah === ayahKey ? " is-audio-active" : ""}`}
                  >
                    <div className="ayah-header">
                      <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                        <span className="ayah-badge">{ayah.number}</span>
                        <span className="kpi-desc">
                          {t("quran.ayahMeta", { ayah: ayah.number, juz: ayah.juz_number })}
                        </span>
                      </div>

                      <div className="ayah-actions">
                        <div className="ayah-action-buttons">
                          <button
                            className={`btn btn-sm ayah-icon-button ayah-play-button${isAyahPlaying ? " is-active" : ""}`}
                            type="button"
                            onClick={() => handleToggleAyahPlayback(ayah.number)}
                            aria-label={`${playbackActionLabel}: ${t("common.ayah", { ayah: ayahKey })}`}
                            title={playbackActionLabel}
                          >
                            <span aria-hidden="true">{isAyahPlaying ? "⏸" : "▶"}</span>
                          </button>
                          <button
                            className={`btn btn-sm ayah-icon-button${isAyahRepeating ? " is-active" : ""}`}
                            type="button"
                            onClick={() => handleToggleAyahRepeat(ayah.number)}
                            aria-pressed={isAyahRepeating}
                            aria-label={isAyahRepeating
                              ? `${t("player.repeatAria")}: ${t("player.repeatOff")}`
                              : `${t("player.repeatAyah")}: ${t("common.ayah", { ayah: ayahKey })}`}
                            title={isAyahRepeating
                              ? `${t("player.repeatAria")}: ${t("player.repeatOff")}`
                              : `${t("player.repeatAyah")}: ${t("common.ayah", { ayah: ayahKey })}`}
                          >
                            <span aria-hidden="true">🔁</span>
                          </button>
                          <button
                            className="btn btn-sm ayah-icon-button ayah-speed-button"
                            type="button"
                            onClick={() => sendPlayerControl("cycle-speed")}
                            aria-label={`${t("player.speedAria")}: ${formatNumber(audioSettings.playbackRate)}×`}
                            title={`${t("player.speedAria")}: ${formatNumber(audioSettings.playbackRate)}×`}
                          >
                            {formatNumber(audioSettings.playbackRate)}×
                          </button>
                          <button
                            className="btn btn-sm ayah-icon-button"
                            type="button"
                            onClick={() => void handleSavePosition(ayah.number)}
                            aria-label={t("quran.markReadTitle")}
                            title={t("quran.markReadTitle")}
                          >
                            <span aria-hidden="true">📍</span>
                          </button>
                          <button
                            className="btn btn-sm ayah-icon-button"
                            type="button"
                            onClick={() => void handleAddBookmark(ayah.number)}
                            aria-label={t("quran.bookmarkTitle")}
                            title={t("quran.bookmarkTitle")}
                          >
                            <span aria-hidden="true">🔖</span>
                          </button>
                        </div>
                      </div>
                    </div>

                    <p className="quran-arabic-text">{ayah.text_uthmani}</p>
                  </article>
                );
              })}
            </div>
          ) : (
            <div style={{ padding: 32, textAlign: "center", color: "var(--text-muted)" }}>
              {t("quran.noAyahs")}
            </div>
          )}
        </section>
      ) : (
        /* Mushaf Page View */
        <section
          className="surface quran-content-surface mushaf-reader-surface"
          ref={mushafReader}
        >
          <div className="mushaf-reader-toolbar" aria-label={t("quran.mushafPage")}>
            <button
              className="mushaf-reader-toolbar-button"
              type="button"
              onClick={() => turnMushafPage("previous")}
              disabled={currentPage <= 1}
              aria-label={t("quran.previousPage", { page: currentPage - 1 })}
            >
              ‹
            </button>
            <div className="mushaf-reader-toolbar-status">
              <strong>{t("quran.pageOf", { page: currentPage, count: mushafPageCount })}</strong>
              <span>{t("quran.swipePages")}</span>
            </div>
            <button
              className="mushaf-reader-toolbar-button"
              type="button"
              onClick={() => turnMushafPage("next")}
              disabled={currentPage >= mushafPageCount}
              aria-label={t("quran.nextPage", { page: currentPage + 1 })}
            >
              ›
            </button>
          </div>
          <div
            className="mushaf-page-container"
            data-swipe-next="right"
            onPointerDown={handleMushafPointerDown}
            onPointerUp={handleMushafPointerUp}
            onPointerCancel={() => {
              swipeStart.current = null;
            }}
            onKeyDown={(event) => {
              if (event.key === "ArrowRight") {
                event.preventDefault();
                turnMushafPage("next");
              } else if (event.key === "ArrowLeft") {
                event.preventDefault();
                turnMushafPage("previous");
              }
            }}
            tabIndex={0}
            aria-label={t("quran.madaniPage", { page: currentPage })}
          >
            {selectedFoundationMushaf ? (
              foundationPageLoading ? (
                <div className="qf-mushaf-page-loading">{t("quran.qfPageLoading")}</div>
              ) : foundationMushafPage ? (
                <div
                  className={`mushaf-page-turn is-${pageTurnDirection}`}
                  data-page-turn={pageTurnDirection}
                  key={`${selectedFoundationMushaf.source_id}-${foundationMushafPage.page_number}`}
                >
                  <QuranFoundationMushafPageView
                    mushaf={selectedFoundationMushaf}
                    page={foundationMushafPage}
                    surahs={surahs}
                    selectedAyahKey={selectedMushafAyah}
                    playingAyahKey={playingMushafAyah}
                    onSelectAyah={setSelectedMushafAyah}
                  />
                </div>
              ) : null
            ) : mushafPageLoading ? (
              <div className="qf-mushaf-page-loading">{t("quran.qfPageLoading")}</div>
            ) : mushafPage && mushafPage.assets && mushafPage.assets.length > 0 ? (
              <div
                className={`mushaf-page-turn is-${pageTurnDirection}`}
                data-page-turn={pageTurnDirection}
                key={`image-${mushafPage.number}`}
              >
                <div
                  className="mushaf-page-frame"
                  style={{ aspectRatio: `${mushafPage.image_width} / ${mushafPage.image_height}` }}
                >
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img
                    src={mushafPage.assets[0].url}
                    alt={t("quran.mushafAlt", { page: mushafPage.number })}
                    className="mushaf-image"
                    data-page-number={mushafPage.number}
                    width={mushafPage.image_width}
                    height={mushafPage.image_height}
                  />
                  <svg
                    className="mushaf-regions"
                    viewBox="0 0 1 1"
                    preserveAspectRatio="none"
                    aria-label={t("quran.regionsAria", { page: mushafPage.number })}
                    data-page-number={mushafPage.number}
                  >
                    {mushafRegions.map((region) => {
                      const key = `${region.ayah.surah}:${region.ayah.number}`;
                      return (
                        <polygon
                          key={region.id}
                          points={region.polygon.map(([x, y]) => `${x},${y}`).join(" ")}
                          className={`mushaf-region${selectedMushafAyah === key ? " is-selected" : ""}${playingMushafAyah === key ? " is-playing" : ""}`}
                          role="button"
                          tabIndex={0}
                          aria-label={t("common.ayah", { ayah: key })}
                          onClick={() => setSelectedMushafAyah(key)}
                          onKeyDown={(event) => {
                            if (event.key === "Enter" || event.key === " ") {
                              event.preventDefault();
                              setSelectedMushafAyah(key);
                            }
                          }}
                        >
                          <title>{t("common.ayah", { ayah: key })}</title>
                        </polygon>
                      );
                    })}
                  </svg>
                  {selectedMushafAyah && (
                    <div className="mushaf-selection-label">
                      {playingMushafAyah === selectedMushafAyah
                        ? t("quran.playingAyah", { ayah: selectedMushafAyah })
                        : t("quran.selectedAyah", { ayah: selectedMushafAyah })}
                    </div>
                  )}
                </div>
              </div>
            ) : (
              <div style={{ textAlign: "center", padding: 40 }}>
                <p className="eyebrow" style={{ marginBottom: 12 }}>
                  {t("quran.madaniPage", { page: currentPage })}
                </p>
                <div
                  style={{
                    maxWidth: 540,
                    margin: "0 auto",
                    padding: 32,
                    background: "#fff",
                    borderRadius: 12,
                    border: "1px solid var(--border)",
                  }}
                >
                  <p className="quran-arabic-text" style={{ fontSize: 24, textAlign: "center" }}>
                    {ayahs.slice(0, 5).map((a) => a.text_uthmani).join(" ۝ ")}
                  </p>
                </div>
              </div>
            )}
          </div>

          <div className="mushaf-page-navigation">
            <button
              className="btn btn-secondary"
              onClick={() => turnMushafPage("previous")}
              disabled={currentPage <= 1}
            >
              {t("quran.previousPage", { page: currentPage - 1 })}
            </button>
            <span className="mushaf-page-navigation-status">
              {t("quran.pageOf", { page: currentPage, count: mushafPageCount })}
            </span>
            <button
              className="btn btn-secondary"
              onClick={() => turnMushafPage("next")}
              disabled={currentPage >= mushafPageCount}
            >
              {t("quran.nextPage", { page: currentPage + 1 })}
            </button>
          </div>
        </section>
      )}
    </div>
  );
}

export default function QuranPage() {
  const { t } = useI18n();
  return (
    <Suspense fallback={<div style={{ padding: 32, textAlign: "center" }}>{t("quran.loading")}</div>}>
      <QuranContent />
    </Suspense>
  );
}
