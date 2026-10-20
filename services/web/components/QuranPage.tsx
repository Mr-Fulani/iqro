"use client";

import {
  Suspense,
  lazy,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import dynamic from "next/dynamic";
import { useSearchParams } from "next/navigation";
import {
  MushafAudioPlayer,
  type AyahPlaybackTrigger,
} from "./MushafAudioPlayer";
import { useMushafPages } from "./useMushafPages";
import { MushafPageTurn } from "./MushafPageTurn";
import { MushafGestureSurface } from "./MushafGestureSurface";
import { QuranFoundationMushafPageView } from "./QuranFoundationMushafPage";
import {
  PrayerReadingSessionBar,
  type PrayerReadingSessionConfig,
} from "./PrayerReadingSessionBar";
import { ReadingActivityTracker } from "./ReadingActivityTracker";
import { FavoriteBookmarkIcon } from "./FavoriteBookmarkIcon";
import { ShareIcon } from "./ShareIcon";
import type { AyahShareTarget } from "./AyahShareDialog";
import { ShareDialogBoundary } from "./ShareDialogBoundary";
import { MushafReaderLayout, MushafReaderPanel, MushafReaderSettings } from "./MushafReaderLayout";
import type {
  AudioPlayerControlRequest,
  AudioPlaybackSettings,
} from "./SegmentedAudioPlayer";
import {
  api,
  ApiError,
  Ayah,
  OfflineMutationQueuedError,
  type AyahAnnotation,
  type Bookmark,
  type AyahTafsir,
  Hizb,
  Juz,
  QuranDivision,
  QuranEdition,
  QuranFoundationMushaf,
  QuranTranslationEdition,
  type QuranTafsirEdition,
  RubElHizb,
  Surah,
  type AyahTranslation,
  type PrayerReadingPrayer,
} from "../lib/api";
import { indexAyahBookmarks } from "../lib/ayah-bookmarks";
import {
  indexAyahAnnotations,
  normalizeAyahHighlightColor,
  type AyahHighlightColorKey,
} from "../lib/ayah-annotations";
import { SYNC_STATE_EVENT } from "../lib/sync-state";
import { useAuth } from "../lib/auth-context";
import { contentShareText, shareTextOnly } from "../lib/content-share";
import { useI18n } from "../lib/i18n-context";
import type { PublishedQuranReaderPreview } from "../lib/public-content";
import {
  editionName as localizedEditionName,
  quranAyahPath,
  quranSurahPath,
  surahName as localizedSurahName,
} from "../lib/quran-content";
import { localizedPath } from "../lib/routing";

// Loaded on first use so the reader's initial bundle stays within its budget.
const AyahAnnotationDialog = dynamic(() => import("./AyahAnnotationDialog"), { ssr: false });
// The share dialog is loaded again after a failed load, as React.lazy keeps it.
const loadAyahShareDialog = () => lazy(() => import("./AyahShareDialog"));
let AyahShareDialog = loadAyahShareDialog();
function reloadAyahShareDialog() {
  AyahShareDialog = loadAyahShareDialog();
}

const arabicNumber = new Intl.NumberFormat("ar-EG");

// The end-of-ayah sign with Arabic-Indic digits, ﴿١٢﴾, as the app draws it.
function ayahEndMarker(ayahNumber: number): string {
  return `\uFD3F${arabicNumber.format(ayahNumber)}\uFD3E`;
}

function positiveInteger(value: string | null): number | null {
  if (value === null || !/^\d+$/.test(value)) return null;
  const parsed = Number(value);
  return Number.isSafeInteger(parsed) && parsed > 0 ? parsed : null;
}

const PRAYER_READING_PRAYERS = new Set<PrayerReadingPrayer>([
  "fajr",
  "dhuhr",
  "asr",
  "maghrib",
  "isha",
]);

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const TRANSLATION_PREFERENCE_KEY_PREFIX = "iqro_quran_translation_v2";
const READER_PREFERENCE_KEY_PREFIX = "iqro_quran_reader_preference_v1";
const MUSHAF_VARIANT_PREFERENCE_KEY = "iqro_quran_mushaf_variant_v1";
const DEFAULT_TRANSLATION_BY_LOCALE: Record<string, number | null> = {
  ar: null,
  en: 20,
  ru: 45,
  tr: 77,
};
const DEFAULT_TAFSIR_BY_LOCALE: Record<string, number | null> = {
  ar: 16,
  en: 169,
  ru: 170,
  tr: null,
};

import {
  readLocalReadingPosition,
  writeLocalReadingPosition,
} from "../lib/reading-position-storage";

type TranslationPreference = {
  enabled: boolean;
  sourceId: number | null;
};

type ReaderPreference = {
  translationEnabled: boolean;
  translationSourceId: number | null;
  tafsirEnabled: boolean;
  tafsirSourceId: number | null;
};

type ReadingPlaceCandidate = {
  editionCode: string;
  pageNumber: number;
  surahNumber?: number;
  ayahNumber?: number;
  requestId: number;
  sourceId?: number;
};

function translationPreferenceKey(locale: string): string {
  return `${TRANSLATION_PREFERENCE_KEY_PREFIX}:${locale}`;
}

function readLegacyTranslationPreference(locale: string): TranslationPreference | null {
  try {
    const raw = window.localStorage.getItem(translationPreferenceKey(locale));
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<TranslationPreference>;
    if (typeof parsed.enabled !== "boolean") return null;
    if (parsed.sourceId !== null && !Number.isSafeInteger(parsed.sourceId)) return null;
    return { enabled: parsed.enabled, sourceId: parsed.sourceId ?? null };
  } catch {
    return null;
  }
}

function readerPreferenceKey(locale: string): string {
  return `${READER_PREFERENCE_KEY_PREFIX}:${locale}`;
}

function readMushafVariantPreference(): number | null {
  try {
    const stored = window.localStorage.getItem(MUSHAF_VARIANT_PREFERENCE_KEY);
    if (!stored) return null;
    const sourceId = Number(stored);
    return Number.isSafeInteger(sourceId) && sourceId > 0 ? sourceId : null;
  } catch {
    return null;
  }
}

function writeMushafVariantPreference(sourceId: number | null): void {
  try {
    window.localStorage.setItem(
      MUSHAF_VARIANT_PREFERENCE_KEY,
      sourceId === null ? "auto" : String(sourceId),
    );
  } catch {
    // Reading remains available when browser storage is blocked.
  }
}

function readReaderPreference(locale: string): ReaderPreference | null {
  try {
    const raw = window.localStorage.getItem(readerPreferenceKey(locale));
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<ReaderPreference>;
    if (
      typeof parsed.translationEnabled !== "boolean"
      || typeof parsed.tafsirEnabled !== "boolean"
      || (parsed.translationSourceId !== null && !Number.isSafeInteger(parsed.translationSourceId))
      || (parsed.tafsirSourceId !== null && !Number.isSafeInteger(parsed.tafsirSourceId))
    ) {
      return null;
    }
    return {
      translationEnabled: parsed.translationEnabled,
      translationSourceId: parsed.translationSourceId ?? null,
      tafsirEnabled: parsed.tafsirEnabled,
      tafsirSourceId: parsed.tafsirSourceId ?? null,
    };
  } catch {
    return null;
  }
}

function writeReaderPreference(locale: string, preference: ReaderPreference): void {
  try {
    window.localStorage.setItem(readerPreferenceKey(locale), JSON.stringify(preference));
  } catch {
    // Server persistence remains authoritative when browser storage is unavailable.
  }
}

function preferenceFingerprint(preference: ReaderPreference): string {
  return JSON.stringify(preference);
}

function tafsirForVerse(
  tafsirs: AyahTafsir[],
  surahNumber: number,
  ayahNumber: number,
): AyahTafsir | undefined {
  const verseKey = `${surahNumber}:${ayahNumber}`;
  const exact = tafsirs.find((tafsir) => tafsir.verse_key === verseKey);
  if (exact) return exact;
  return tafsirs.find(
    (tafsir) =>
      tafsir.start_surah_number === surahNumber
      && tafsir.end_surah_number === surahNumber
      && tafsir.start_ayah_number <= ayahNumber
      && tafsir.end_ayah_number >= ayahNumber,
  );
}

function translationFootnoteTexts(footNotes: AyahTranslation["foot_notes"]): string[] {
  const candidates = Array.isArray(footNotes) ? footNotes : Object.values(footNotes);
  return candidates.flatMap((note) => {
    if (typeof note === "string") return note.trim() ? [note.trim()] : [];
    if (!note || typeof note !== "object" || !("text" in note)) return [];
    const text = note.text;
    return typeof text === "string" && text.trim() ? [text.trim()] : [];
  });
}

function TranslationFootnotes({ footNotes }: { footNotes: AyahTranslation["foot_notes"] }) {
  const { t } = useI18n();
  const notes = translationFootnoteTexts(footNotes);
  if (notes.length === 0) return null;

  return (
    <details className="translation-footnotes">
      <summary>
        {t("quran.translationFootnotes")} <span>({notes.length})</span>
      </summary>
      <ol>
        {notes.map((note, index) => (
          <li key={`${index}-${note.slice(0, 32)}`}>
            <span>[{index + 1}]</span>
            <p>{note}</p>
          </li>
        ))}
      </ol>
    </details>
  );
}

function expandVerseMapping(mapping: Record<string, string>): string[] {
  const keys: string[] = [];
  for (const [surah, ranges] of Object.entries(mapping)) {
    for (const range of ranges.split(",")) {
      const match = range.trim().match(/^(\d+)(?:-(\d+))?$/);
      if (!match) continue;
      const start = Number(match[1]);
      const end = Number(match[2] || match[1]);
      for (let ayah = start; ayah <= end; ayah += 1) keys.push(`${surah}:${ayah}`);
    }
  }
  return keys;
}

function divisionAtAyah(divisions: QuranDivision[], ayahKey: string | null): number | "" {
  if (!ayahKey) return "";
  const [surah, ayah] = ayahKey.split(":").map(Number);
  const position = surah * 1000 + ayah;
  return divisions.find((division) => position >= division.start_ayah.surah * 1000 + division.start_ayah.number
    && position <= division.end_ayah.surah * 1000 + division.end_ayah.number)?.number ?? "";
}

function QuranContent() {
  const searchParams = useSearchParams();
  const rawSurahParam = positiveInteger(searchParams.get("surah"));
  const deepLinkSurah = rawSurahParam || 1;
  const deepLinkAyah = positiveInteger(searchParams.get("ayah"));
  const deepLinkKey = deepLinkAyah === null ? null : `${deepLinkSurah}:${deepLinkAyah}`;
  const deepLinkPageCandidate = positiveInteger(searchParams.get("page"));
  const deepLinkPage = deepLinkPageCandidate !== null && deepLinkPageCandidate <= 604
    ? deepLinkPageCandidate
    : null;
  const hasExplicitDeepLink = Boolean(rawSurahParam || deepLinkAyah || deepLinkPageCandidate);

  // Server and first browser render must agree. Restore browser state after hydration.
  const [initialLocalPosition, setInitialLocalPosition] =
    useState<ReturnType<typeof readLocalReadingPosition>>(null);
  const [localPositionReady, setLocalPositionReady] = useState(false);

  const prayerReadingConfig = useMemo<PrayerReadingSessionConfig | null>(() => {
    if (searchParams.get("mode") !== "after-prayer") return null;
    const prayer = searchParams.get("prayer") as PrayerReadingPrayer | null;
    const localDate = searchParams.get("prayer_date");
    const timezoneName = searchParams.get("prayer_timezone");
    const metricValue = searchParams.get("prayer_metric") || "pages";
    const metric = metricValue === "minutes" || metricValue === "ayahs" ? metricValue : "pages";
    const targetPages = Number(searchParams.get("prayer_target"));
    const creditedPages = Number(searchParams.get("prayer_credited") || 0);
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
      || !["pages", "minutes", "ayahs"].includes(metricValue)
      || !Number.isFinite(targetPages) || targetPages <= 0
      || !Number.isFinite(creditedPages) || creditedPages < 0
      || targetPages > (metric === "minutes" ? 1440 : metric === "ayahs" ? 6236 : 604)
      || creditedPages > (metric === "minutes" ? 1440 : metric === "ayahs" ? 6236 : 604)
      || (metric !== "minutes" && (!Number.isInteger(targetPages) || !Number.isInteger(creditedPages)))
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
      metric,
      checkInId,
      checkInRevision,
    };
  }, [searchParams]);

  const { isLoggedIn, isLoading: authLoading, loginGuest, session } = useAuth();
  const { formatNumber, locale, t } = useI18n();
  const [editions, setEditions] = useState<QuranEdition[]>([]);
  const [selectedEdition, setSelectedEdition] = useState<string>("madani-hafs");
  const [surahs, setSurahs] = useState<Surah[]>([]);
  const [selectedSurah, setSelectedSurah] = useState<number>(
    rawSurahParam || 1,
  );
  const [ayahs, setAyahs] = useState<Ayah[]>([]);
  const [translationEditions, setTranslationEditions] = useState<QuranTranslationEdition[]>([]);
  const [selectedTranslationId, setSelectedTranslationId] = useState<number | null>(null);
  const [translationEnabled, setTranslationEnabled] = useState(false);
  const [translationPreferenceReady, setTranslationPreferenceReady] = useState(false);
  const [translationsByVerse, setTranslationsByVerse] = useState<
    Record<string, AyahTranslation>
  >({});
  const [translationLoading, setTranslationLoading] = useState(false);
  const [translationError, setTranslationError] = useState(false);
  const [tafsirEditions, setTafsirEditions] = useState<QuranTafsirEdition[]>([]);
  const [selectedTafsirId, setSelectedTafsirId] = useState<number | null>(null);
  const [tafsirEnabled, setTafsirEnabled] = useState(false);
  const [tafsirRecords, setTafsirRecords] = useState<AyahTafsir[]>([]);
  const [tafsirLoading, setTafsirLoading] = useState(false);
  const [tafsirError, setTafsirError] = useState(false);
  const [expandedTafsirVerse, setExpandedTafsirVerse] = useState<string | null>(null);
  const [preferenceSyncError, setPreferenceSyncError] = useState(false);
  const readerPreferenceLocale = useRef<string | null>(null);
  const readerPreferenceRevisions = useRef<Record<string, number>>({});
  const readerPreferenceFingerprints = useRef<Record<string, string>>({});
  const readerPreferenceSaveChain = useRef<Promise<void>>(Promise.resolve());
  const [juz, setJuz] = useState<Juz[]>([]);
  const [hizb, setHizb] = useState<Hizb[]>([]);
  const [rubElHizb, setRubElHizb] = useState<RubElHizb[]>([]);
  const [currentPage, setCurrentPage] = useState<number>(
    deepLinkPage || 1,
  );
  const [viewMode, setViewMode] = useState<"text" | "mushaf">("mushaf");
  const [foundationMushafs, setFoundationMushafs] = useState<QuranFoundationMushaf[]>([]);
  const [selectedFoundationMushafId, setSelectedFoundationMushafId] = useState<number | null>(null);
  const [selectedMushafAyah, setSelectedMushafAyah] = useState<string | null>(null);
  const [playingMushafAyah, setPlayingMushafAyah] = useState<string | null>(null);
  const [isAudioPlaying, setIsAudioPlaying] = useState(false);
  const [isImmersiveReader, setIsImmersiveReader] = useState(false);
  const [playAyahRequest, setPlayAyahRequest] = useState<AyahPlaybackTrigger | null>(null);
  const [playerControlRequest, setPlayerControlRequest] = useState<AudioPlayerControlRequest | null>(null);
  const [audioSettings, setAudioSettings] = useState<AudioPlaybackSettings>({
    repeatMode: "off",
    playbackRate: 1,
  });
  const pendingNavigationPage = useRef<number | null>(null);
  const initializedAyahEdition = useRef<string | null>(null);
  const textReadingAyah = useRef<string | null>(null);
  const handledDeepLink = useRef<string | null>(null);
  const handledPageDeepLink = useRef<number | null>(null);
  const pendingTextAyah = useRef<string | null>(null);
  const pendingMushafAyah = useRef<string | null>(null);
  const lastMushafLocation = useRef<{ sourceId: number | null; ayah: string | null; page: number } | null>(null);
  const handledPrayerReadingStart = useRef(false);
  const ayahPlaybackRequestId = useRef(0);
  const playerControlRequestId = useRef(0);
  const selectedFoundationMushaf = useMemo(
    () => foundationMushafs.find((mushaf) => mushaf.source_id === selectedFoundationMushafId) || null,
    [foundationMushafs, selectedFoundationMushafId],
  );
  const mushafPageCount = selectedFoundationMushaf?.pages_count || 604;
  const [foundationIndex, setFoundationIndex] = useState<{
    sourceId: number; versePages: Record<string, number[]>;
  } | null>(null);
  const [foundationIndexError, setFoundationIndexError] = useState(false);
  const versePages = foundationIndex?.sourceId === selectedFoundationMushafId
    ? foundationIndex.versePages : null;
  const sourcePageFor = useCallback((key: string, fallback: number) =>
    versePages?.[key]?.includes(fallback) ? fallback : versePages?.[key]?.[0]
      ?? Math.min(mushafPageCount, fallback), [versePages, mushafPageCount]);
  useEffect(() => {
    if (!selectedFoundationMushaf) return;
    let cancelled = false;
    const source = selectedFoundationMushaf;
    setFoundationIndexError(false);
    void api.getQuranFoundationMushafIndex(source.source_id).then((index) => {
      if (cancelled) return;
      if (index.source_checksum_sha256 !== source.source_checksum_sha256) throw new Error("Mushaf index version changed");
      setFoundationIndex({ sourceId: source.source_id, versePages: index.verse_pages });
      const reference = pendingMushafAyah.current;
      if (reference && index.verse_pages[reference]?.length) setCurrentPage((page) =>
        index.verse_pages[reference].includes(page) ? page : index.verse_pages[reference][0]);
      else setCurrentPage((page) => Math.min(page, index.pages_count));
    }).catch(() => { if (!cancelled) { setFoundationIndex(null); setFoundationIndexError(true); } });
    return () => { cancelled = true; };
  }, [selectedFoundationMushaf]);
  const { foundationPage: foundationMushafPage, loading: pageLoading, error: pageError } = useMushafPages(
    selectedFoundationMushaf, currentPage,
    viewMode === "mushaf" && localPositionReady,
  );
  const foundationPageLoading = pageLoading;
  const selectedTranslation = useMemo(
    () =>
      translationEditions.find((edition) => edition.source_id === selectedTranslationId) || null,
    [selectedTranslationId, translationEditions],
  );
  const selectedTafsir = useMemo(
    () => tafsirEditions.find((edition) => edition.source_id === selectedTafsirId) || null,
    [selectedTafsirId, tafsirEditions],
  );
  const mushafVerseKeys = useMemo(() => {
    if (foundationMushafPage) return foundationMushafPage.verse_keys ?? expandVerseMapping(foundationMushafPage.verse_mapping);
    if (viewMode === "mushaf") return [];
    return ayahs
      .filter((ayah) => ayah.pages.includes(currentPage))
      .map((ayah) => `${ayah.surah_number}:${ayah.number}`);
  }, [ayahs, currentPage, foundationMushafPage, viewMode]);
  const currentAyahKey = viewMode === "mushaf"
    ? (selectedMushafAyah && mushafVerseKeys.includes(selectedMushafAyah) ? selectedMushafAyah : mushafVerseKeys[0] ?? null)
    : selectedMushafAyah?.startsWith(`${selectedSurah}:`) ? selectedMushafAyah : `${selectedSurah}:1`;
  const currentAyah = ayahs.find((ayah) => `${ayah.surah_number}:${ayah.number}` === currentAyahKey);
  const [resolvedCanonicalPage, setResolvedCanonicalPage] = useState<{ key: string; page: number } | null>(null);
  const canonicalPage = viewMode === "text" ? currentPage :
    (currentAyah?.pages.includes(currentPage) ? currentPage : currentAyah?.pages[0])
    ?? (resolvedCanonicalPage?.key === currentAyahKey ? resolvedCanonicalPage.page : null);
  useEffect(() => {
    if (viewMode !== "mushaf" || !currentAyahKey || currentAyah?.pages.length) return;
    let cancelled = false;
    const [surah, ayah] = currentAyahKey.split(":").map(Number);
    void api.getAyah(selectedEdition, surah, ayah).then((value) => {
      if (!cancelled && value.pages.length) setResolvedCanonicalPage({ key: currentAyahKey, page: value.pages[0] });
    }).catch(() => undefined);
    return () => { cancelled = true; };
  }, [currentAyahKey, currentAyah, selectedEdition, viewMode]);

  // A restored position or a layout change may precede the source index.
  // Resolve by verse when both are ready, never reuse a different layout's page.
  useEffect(() => {
    const target = pendingMushafAyah.current;
    if (viewMode === "mushaf" && target && versePages?.[target]?.length) {
      setCurrentPage((page) => versePages[target].includes(page) ? page : versePages[target][0]);
      pendingNavigationPage.current = null;
      if (selectedMushafAyah !== target) pendingMushafAyah.current = null;
    }
  }, [versePages, selectedMushafAyah, viewMode, currentPage]);

  // Page data establishes the reading position; loading a surah must not navigate.
  useEffect(() => {
    if (viewMode !== "mushaf" || !currentAyahKey || initializedAyahEdition.current !== selectedEdition) return;
    if (deepLinkKey && handledDeepLink.current !== deepLinkKey) return;
    if (pendingNavigationPage.current !== null || (pendingMushafAyah.current && pendingMushafAyah.current !== currentAyahKey)) return;
    setSelectedSurah(Number(currentAyahKey.split(":")[0]));
  }, [ayahs, currentAyahKey, deepLinkKey, selectedEdition, viewMode]);
  const requiredTranslationSurahs = useMemo(() => {
    if (viewMode === "text") return [selectedSurah];
    const pageSurahs = mushafVerseKeys.map((key) => Number(key.split(":")[0]));
    return [...new Set(pageSurahs.length ? pageSurahs : [selectedSurah])].filter(Number.isSafeInteger);
  }, [mushafVerseKeys, selectedSurah, viewMode]);
  const translationSurahKey = requiredTranslationSurahs.join(",");
  const mushafTranslations = useMemo(
    () => mushafVerseKeys.map((key) => translationsByVerse[key]).filter(Boolean),
    [mushafVerseKeys, translationsByVerse],
  );
  const tafsirsByVerse = useMemo(() => {
    const entries = [
      ...ayahs.map((ayah) => `${ayah.surah_number}:${ayah.number}`),
      ...mushafVerseKeys,
    ].map((key) => {
      const [surahNumber, ayahNumber] = key.split(":").map(Number);
      return [key, tafsirForVerse(tafsirRecords, surahNumber, ayahNumber)] as const;
    });
    return Object.fromEntries(entries.filter((entry) => entry[1] !== undefined)) as Record<
      string,
      AyahTafsir
    >;
  }, [ayahs, mushafVerseKeys, tafsirRecords]);
  const selectedMushafTafsir = selectedMushafAyah
    ? tafsirsByVerse[selectedMushafAyah]
    : undefined;
  const [prayerReadingReady, setPrayerReadingReady] = useState(
    prayerReadingConfig === null,
  );
  const [prayerReadingActiveSeconds, setPrayerReadingActiveSeconds] = useState(0);
  const [prayerReadingFinished, setPrayerReadingFinished] = useState(false);
  const [pageTurnDirection, setPageTurnDirection] = useState<"next" | "previous">("next");
  const previousPage = useRef(currentPage);
  const mushafReader = useRef<HTMLElement | null>(null);
  const [loading, setLoading] = useState<boolean>(true);
  const [feedbackMessage, setFeedbackMessage] = useState<{ text: string; type: "ok" | "err" } | null>(null);
  const [readingPlaceCandidate, setReadingPlaceCandidate] = useState<ReadingPlaceCandidate | null>(null);
  const readingPlaceRequestId = useRef(0);
  const readingPlaceSaveChain = useRef<Promise<void>>(Promise.resolve());
  const textScrollIntent = useRef(false);
  const [savedAyahBookmarks, setSavedAyahBookmarks] = useState<Record<string, Bookmark>>({});
  const [bookmarkStateReady, setBookmarkStateReady] = useState(false);
  const [bookmarkBusyKeys, setBookmarkBusyKeys] = useState<Set<string>>(new Set());
  const [bookmarkAnimationKey, setBookmarkAnimationKey] = useState<string | null>(null);
  const [annotations, setAnnotations] = useState<AyahAnnotation[]>([]);
  const [annotationAyahKey, setAnnotationAyahKey] = useState<string | null>(null);
  const [shareTarget, setShareTarget] = useState<AyahShareTarget | null>(null);
  const [annotationsReady, setAnnotationsReady] = useState(false);

  const queueReadingPlace = useCallback((candidate: Omit<ReadingPlaceCandidate, "editionCode" | "requestId">) => {
    if (viewMode !== "mushaf" && candidate.sourceId === undefined) {
      writeLocalReadingPosition(selectedEdition, candidate);
    }
    readingPlaceRequestId.current += 1;
    setReadingPlaceCandidate({
      ...candidate,
      sourceId: candidate.sourceId ?? (viewMode === "mushaf" ? selectedFoundationMushafId ?? undefined : undefined),
      editionCode: selectedEdition,
      requestId: readingPlaceRequestId.current,
    });
  }, [selectedEdition, viewMode, selectedFoundationMushafId]);

  // Save a displayed page locally as soon as its canonical verse is known.
  // Authentication and the debounced server write must not delay navigation safety.
  useEffect(() => {
    if (viewMode !== "mushaf" || canonicalPage === null || !currentAyahKey
      || readingPlaceCandidate?.pageNumber !== currentPage
      || readingPlaceCandidate.editionCode !== selectedEdition
      || readingPlaceCandidate.sourceId !== selectedFoundationMushafId) return;
    const [surahNumber, ayahNumber] = currentAyahKey.split(":").map(Number);
    writeLocalReadingPosition(selectedEdition, { pageNumber: canonicalPage, surahNumber, ayahNumber });
  }, [canonicalPage, currentAyahKey, currentPage, readingPlaceCandidate, selectedEdition, selectedFoundationMushafId, viewMode]);

  useEffect(() => {
    if (authLoading || readingPlaceCandidate === null) return;
    const candidate = { ...readingPlaceCandidate };
    const timeout = window.setTimeout(() => {
      const persistReadingPlace = async () => {
        // Reading progress belongs to the canonical Quran. Physical page
        // numbers in the 548/610-page layouts must never overwrite it.
        if (candidate.sourceId !== undefined) {
          if (candidate.surahNumber === undefined || candidate.ayahNumber === undefined) {
            const page = await api.getQuranFoundationMushafPage(candidate.sourceId, candidate.pageNumber);
            const key = page.verse_keys?.[0] ?? expandVerseMapping(page.verse_mapping)[0];
            if (!key) return;
            [candidate.surahNumber, candidate.ayahNumber] = key.split(":").map(Number);
          }
          const ayah = await api.getAyah(candidate.editionCode, candidate.surahNumber, candidate.ayahNumber);
          if (!ayah.pages.length) return;
          candidate.pageNumber = ayah.pages[0];
          if (candidate.requestId === readingPlaceRequestId.current) writeLocalReadingPosition(candidate.editionCode, candidate);
        }
        if (!api.getSession() && !(await loginGuest())) return;
        const currentRevision = async () => {
          try {
            return (await api.getReadingPosition(candidate.editionCode)).revision;
          } catch (error) {
            if (error instanceof ApiError && error.status === 404) return 0;
            throw error;
          }
        };
        const save = (baseRevision: number) => api.saveReadingPosition(candidate.editionCode, {
          page_number: candidate.pageNumber,
          ...(candidate.surahNumber !== undefined && candidate.ayahNumber !== undefined
            ? {
                surah_number: candidate.surahNumber,
                ayah_number: candidate.ayahNumber,
              }
            : {}),
          progress_percent: ((candidate.pageNumber / 604) * 100).toFixed(2),
          base_revision: baseRevision,
        });

        let baseRevision = await currentRevision();
        try {
          await save(baseRevision);
        } catch (error) {
          if (!(error instanceof ApiError) || error.code !== "sync_revision_conflict") throw error;
          baseRevision = await currentRevision();
          await save(baseRevision);
        }
      };

      readingPlaceSaveChain.current = readingPlaceSaveChain.current
        .catch(() => undefined)
        .then(persistReadingPlace)
        .catch(() => undefined);
    }, 1200);

    return () => window.clearTimeout(timeout);
  }, [authLoading, loginGuest, readingPlaceCandidate]);

  useEffect(() => {
    const local = hasExplicitDeepLink || prayerReadingConfig
      ? null : readLocalReadingPosition(selectedEdition);
    setInitialLocalPosition(local);
    if (local) {
      pendingNavigationPage.current = local.pageNumber;
      setCurrentPage(local.pageNumber);
      if (local.surahNumber) setSelectedSurah(local.surahNumber);
      if (local.surahNumber && local.ayahNumber) {
        pendingMushafAyah.current = `${local.surahNumber}:${local.ayahNumber}`;
        setSelectedMushafAyah(`${local.surahNumber}:${local.ayahNumber}`);
      }
    }
    setLocalPositionReady(true);
  }, [hasExplicitDeepLink, prayerReadingConfig, selectedEdition]);

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

  useEffect(() => {
    if (authLoading) return;
    let cancelled = false;
    readerPreferenceLocale.current = null;
    setTranslationPreferenceReady(false);
    const preferencePromise = session
      ? api.getQuranReaderPreference(locale)
      : Promise.resolve(null);
    Promise.all([api.getTranslations(locale), api.getTafsirs(locale), preferencePromise])
      .then(([translationCatalog, tafsirCatalog, serverPreference]) => {
        if (cancelled) return;
        setTranslationEditions(translationCatalog);
        setTafsirEditions(tafsirCatalog);
        const localPreference = readReaderPreference(locale);
        const legacyTranslation = readLegacyTranslationPreference(locale);
        const hasServerPreference = Boolean(serverPreference && serverPreference.revision > 0);
        const requestedTranslationId = hasServerPreference
          ? serverPreference?.translation_source_id ?? null
          : localPreference?.translationSourceId
            ?? legacyTranslation?.sourceId
            ?? DEFAULT_TRANSLATION_BY_LOCALE[locale]
            ?? null;
        const requestedTafsirId = hasServerPreference
          ? serverPreference?.tafsir_source_id ?? null
          : localPreference?.tafsirSourceId
            ?? DEFAULT_TAFSIR_BY_LOCALE[locale]
            ?? null;
        const translationFallback = locale === "ar"
          ? undefined
          : translationCatalog.find((edition) => edition.language_code === locale);
        const translationId = translationCatalog.find(
          (edition) => edition.source_id === requestedTranslationId,
        )?.source_id ?? translationFallback?.source_id ?? null;
        const tafsirId = tafsirCatalog.find(
          (edition) => edition.source_id === requestedTafsirId,
        )?.source_id ?? null;
        const resolved: ReaderPreference = {
          translationEnabled: Boolean(
            translationId
            && (hasServerPreference
              ? serverPreference?.translation_enabled
              : localPreference?.translationEnabled
                ?? legacyTranslation?.enabled
                ?? locale !== "ar"),
          ),
          translationSourceId: translationId,
          tafsirEnabled: Boolean(
            tafsirId
            && (hasServerPreference
              ? serverPreference?.tafsir_enabled
              : localPreference?.tafsirEnabled ?? false),
          ),
          tafsirSourceId: tafsirId,
        };
        setSelectedTranslationId(resolved.translationSourceId);
        setTranslationEnabled(resolved.translationEnabled);
        setSelectedTafsirId(resolved.tafsirSourceId);
        setTafsirEnabled(resolved.tafsirEnabled);
        setTranslationError(false);
        setTafsirError(false);
        setPreferenceSyncError(false);
        const preferenceKey = `${session?.user.id ?? "local"}:${locale}`;
        readerPreferenceRevisions.current[preferenceKey] = serverPreference?.revision ?? 0;
        readerPreferenceFingerprints.current[preferenceKey] = hasServerPreference
          ? preferenceFingerprint(resolved)
          : "";
        readerPreferenceLocale.current = locale;
        setTranslationPreferenceReady(true);
      })
      .catch(() => {
        if (cancelled) return;
        setTranslationEditions([]);
        setTafsirEditions([]);
        setSelectedTranslationId(null);
        setSelectedTafsirId(null);
        setTranslationEnabled(false);
        setTafsirEnabled(false);
        setTranslationError(true);
        setTafsirError(true);
        readerPreferenceLocale.current = null;
      });
    return () => {
      cancelled = true;
    };
  }, [authLoading, locale, session]);

  useEffect(() => {
    if (!translationPreferenceReady || readerPreferenceLocale.current !== locale) return;
    const desired: ReaderPreference = {
      translationEnabled: translationEnabled && selectedTranslationId !== null,
      translationSourceId: selectedTranslationId,
      tafsirEnabled: tafsirEnabled && selectedTafsirId !== null,
      tafsirSourceId: selectedTafsirId,
    };
    writeReaderPreference(locale, desired);
    if (!session) return;
    const preferenceKey = `${session.user.id}:${locale}`;
    const fingerprint = preferenceFingerprint(desired);
    if (readerPreferenceFingerprints.current[preferenceKey] === fingerprint) return;

    const timer = window.setTimeout(() => {
      const persist = async () => {
        const body = {
          base_revision: readerPreferenceRevisions.current[preferenceKey] ?? 0,
          translation_enabled: desired.translationEnabled,
          translation_source_id: desired.translationSourceId,
          tafsir_enabled: desired.tafsirEnabled,
          tafsir_source_id: desired.tafsirSourceId,
          client_updated_at: new Date().toISOString(),
        };
        try {
          const saved = await api.putQuranReaderPreference(locale, body);
          readerPreferenceRevisions.current[preferenceKey] = saved.revision;
        } catch (error) {
          if (
            !(error instanceof ApiError)
            || error.code !== "quran_reader_preference_revision_conflict"
          ) {
            throw error;
          }
          const latest = await api.getQuranReaderPreference(locale);
          const saved = await api.putQuranReaderPreference(locale, {
            ...body,
            base_revision: latest.revision,
          });
          readerPreferenceRevisions.current[preferenceKey] = saved.revision;
        }
        readerPreferenceFingerprints.current[preferenceKey] = fingerprint;
        if (readerPreferenceLocale.current === locale) setPreferenceSyncError(false);
      };
      readerPreferenceSaveChain.current = readerPreferenceSaveChain.current
        .catch(() => undefined)
        .then(persist)
        .catch(() => {
          if (readerPreferenceLocale.current === locale) setPreferenceSyncError(true);
        });
    }, 300);
    return () => window.clearTimeout(timer);
  }, [
    locale,
    selectedTafsirId,
    selectedTranslationId,
    session,
    tafsirEnabled,
    translationEnabled,
    translationPreferenceReady,
  ]);

  useEffect(() => {
    if (!translationEnabled || selectedTranslationId === null) {
      setTranslationsByVerse({});
      setTranslationLoading(false);
      if (selectedTranslationId !== null) setTranslationError(false);
      return;
    }
    let cancelled = false;
    setTranslationLoading(true);
    setTranslationError(false);
    Promise.all(
      requiredTranslationSurahs.map((surah) =>
        api.getSurahTranslation(selectedTranslationId, surah),
      ),
    )
      .then((surahTranslations) => {
        if (cancelled) return;
        const byVerse = Object.fromEntries(
          surahTranslations.flat().map((translation) => [translation.verse_key, translation]),
        );
        setTranslationsByVerse(byVerse);
        setTranslationLoading(false);
      })
      .catch(() => {
        if (cancelled) return;
        setTranslationsByVerse({});
        setTranslationLoading(false);
        setTranslationError(true);
      });
    return () => {
      cancelled = true;
    };
    // translationSurahKey is a stable dependency for the computed surah list.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedTranslationId, translationEnabled, translationSurahKey]);

  useEffect(() => {
    setExpandedTafsirVerse(null);
    if (!tafsirEnabled || selectedTafsirId === null) {
      setTafsirRecords([]);
      setTafsirLoading(false);
      if (selectedTafsirId !== null) setTafsirError(false);
      return;
    }
    let cancelled = false;
    setTafsirLoading(true);
    setTafsirError(false);
    Promise.all(
      requiredTranslationSurahs.map((surah) => api.getSurahTafsir(selectedTafsirId, surah)),
    )
      .then((surahTafsirs) => {
        if (cancelled) return;
        const unique = new Map(
          surahTafsirs.flat().map((tafsir) => [tafsir.verse_key, tafsir]),
        );
        setTafsirRecords([...unique.values()]);
        setTafsirLoading(false);
      })
      .catch(() => {
        if (cancelled) return;
        setTafsirRecords([]);
        setTafsirLoading(false);
        setTafsirError(true);
      });
    return () => {
      cancelled = true;
    };
    // translationSurahKey is shared by translation and Tafsir page requirements.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedTafsirId, tafsirEnabled, translationSurahKey]);

  // Display variants are independent from the published Quran text edition.
  useEffect(() => {
    api
      .getQuranFoundationMushafs()
      .then((mushafs) => {
        const renderable = mushafs.filter(
          (mushaf) =>
            mushaf.rendering.available &&
            ["page-font", "unicode-font", "word-images"].includes(mushaf.rendering.mode),
        );
        setFoundationMushafs(renderable);
        const preferredSourceId = readMushafVariantPreference();
        const resolvedSourceId = preferredSourceId !== null
          && renderable.some((mushaf) => mushaf.source_id === preferredSourceId)
          ? preferredSourceId
          : renderable.find((mushaf) => mushaf.source_id === 5)?.source_id ?? renderable[0]?.source_id ?? null;
        setSelectedFoundationMushafId(resolvedSourceId);
        if (preferredSourceId !== null && resolvedSourceId === null) {
          writeMushafVariantPreference(null);
        }
      })
      .catch(() => {
        setFoundationMushafs([]);
        setSelectedFoundationMushafId(null);
      });
  }, []);

  useEffect(() => {
    if (authLoading) return;
    if (!session) {
      setSavedAyahBookmarks({});
      setBookmarkStateReady(true);
      return;
    }
    setBookmarkStateReady(false);
    let cancelled = false;
    void api
      .getAllBookmarks()
      .then((bookmarks) => {
        if (cancelled) return;
        setSavedAyahBookmarks(indexAyahBookmarks(bookmarks));
        setBookmarkStateReady(true);
      })
      .catch(() => {
        // The public Quran reader remains usable if personal state is unavailable.
        if (!cancelled) setBookmarkStateReady(true);
      });
    return () => {
      cancelled = true;
    };
  }, [authLoading, session]);

  // Annotations live in the synced local cache: show it at once, then sync so
  // changes made in the app arrive, and flush queued changes when back online.
  const sessionUserId = session?.user.id ?? null;
  useEffect(() => {
    if (authLoading || !sessionUserId) {
      setAnnotations([]);
      setAnnotationsReady(!authLoading);
      return;
    }
    let cancelled = false;
    const refresh = (event?: Event) => {
      const userId = (event as CustomEvent<{ userId?: string }> | undefined)?.detail?.userId;
      if (!userId || userId === sessionUserId) setAnnotations(api.getAyahAnnotations());
    };
    const sync = () => api.syncNow().catch(() => undefined);
    refresh();
    setAnnotationsReady(false);
    void sync().then(() => {
      if (!cancelled) setAnnotationsReady(true);
    });
    window.addEventListener(SYNC_STATE_EVENT, refresh);
    const syncOnline = () => void sync();
    window.addEventListener("online", syncOnline);
    return () => {
      cancelled = true;
      window.removeEventListener(SYNC_STATE_EVENT, refresh);
      window.removeEventListener("online", syncOnline);
    };
  }, [authLoading, sessionUserId]);

  const ayahAnnotations = useMemo(
    () => indexAyahAnnotations(annotations, selectedEdition),
    [annotations, selectedEdition],
  );
  const ayahHighlightColors = useMemo(
    () => Object.fromEntries(
      Object.entries(ayahAnnotations).map(([key, annotation]) => [key, annotation.color_key]),
    ),
    [ayahAnnotations],
  );
  // Spoken state of a highlighted ayah, so the highlight is not conveyed by color alone.
  const ayahAnnotationLabels = useMemo(
    () => Object.fromEntries(
      Object.entries(ayahAnnotations).map(([key, annotation]) => {
        const color = t(`annotation.color.${normalizeAyahHighlightColor(annotation.color_key)}`);
        const highlighted = t("annotation.highlighted", { color });
        return [key, annotation.note.trim() ? `${highlighted}, ${t("annotation.hasNote")}` : highlighted];
      }),
    ),
    [ayahAnnotations, t],
  );

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
    if (!selectedEdition || !selectedSurah || !localPositionReady) return;
    let cancelled = false;
    setLoading(true);
    api
      .getAyahs(selectedEdition, selectedSurah)
      .then((res) => {
        if (cancelled) return;
        setAyahs(res);
        setLoading(false);
        if (pendingNavigationPage.current !== null) {
          setCurrentPage(pendingNavigationPage.current);
          pendingNavigationPage.current = null;
        } else if (
          initializedAyahEdition.current !== selectedEdition
          && deepLinkPage === null
          && initialLocalPosition === null
          && res[0]?.pages.length
        ) {
          pendingMushafAyah.current = `${selectedSurah}:${res[0].number}`;
          setCurrentPage(res[0].pages[0]);
        }
        initializedAyahEdition.current = selectedEdition;
      })
      .catch((err) => {
        if (cancelled) return;
        setLoading(false);
        setFeedbackMessage({ text: api.normalizeError(err), type: "err" });
      });
    return () => { cancelled = true; };
  }, [deepLinkPage, initialLocalPosition, localPositionReady, selectedEdition, selectedSurah]);

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
    pendingMushafAyah.current = deepLinkKey;
    setCurrentPage(sourcePageFor(deepLinkKey, linkedAyah.pages[0]));
    handledDeepLink.current = deepLinkKey;
  }, [ayahs, deepLinkAyah, deepLinkKey, deepLinkSurah, selectedSurah, sourcePageFor]);

  // Legacy bookmarks may point to a Mushaf page without an ayah reference.
  // Apply the page after the initial surah request, which otherwise resets the
  // reader to that surah's first page.
  useEffect(() => {
    if (
      deepLinkAyah !== null
      || deepLinkPage === null
      || handledPageDeepLink.current === deepLinkPage
    ) {
      return;
    }
    setViewMode("mushaf");
    pendingMushafAyah.current = null;
    setSelectedMushafAyah(null);
    setCurrentPage(Math.min(deepLinkPage, mushafPageCount));
    handledPageDeepLink.current = deepLinkPage;
  }, [deepLinkAyah, deepLinkPage, mushafPageCount]);

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
        const target = position.ayah ? `${positionSurah}:${position.ayah.ayah_number}` : null;
        if (target) {
          pendingMushafAyah.current = target;
          setSelectedMushafAyah(target);
        }
        const page = target ? sourcePageFor(target, position.page_number) : position.page_number;
        setCurrentPage(page);
        if (positionSurah === selectedSurah) {
          return;
        }
        pendingNavigationPage.current = page;
        setSelectedSurah(positionSurah);
      })
      .catch(() => {
        // A new reader starts from the first available Mushaf page.
      })
      .finally(() => {
        setPrayerReadingReady(true);
      });
  }, [authLoading, prayerReadingConfig, selectedEdition, selectedSurah, session, sourcePageFor]);

  const handledInitialPositionSync = useRef(false);

  // Restore saved server reading position for normal reading when opening the reader without deep links.
  useEffect(() => {
    if (
      hasExplicitDeepLink
      || prayerReadingConfig !== null
      || !localPositionReady
      || handledInitialPositionSync.current
      || authLoading
      || !selectedEdition
    ) {
      return;
    }
    handledInitialPositionSync.current = true;
    if (!session) return;

    let cancelled = false;
    api.getReadingPosition(selectedEdition)
      .then((position) => {
        if (cancelled || !position.page_number) return;
        const positionSurah = position.ayah?.surah_number;
        const positionAyah = position.ayah?.ayah_number;
        const serverUpdatedAt = position.last_read_at ? new Date(position.last_read_at).getTime() : 0;
        const local = readLocalReadingPosition(selectedEdition);
        const localUpdatedAt = local?.updatedAt ? new Date(local.updatedAt).getTime() : 0;

        if (local && localUpdatedAt > serverUpdatedAt) {
          return;
        }

        writeLocalReadingPosition(selectedEdition, {
          pageNumber: position.page_number,
          surahNumber: positionSurah,
          ayahNumber: positionAyah,
        });

        setCurrentPage(position.page_number);
        if (positionSurah && positionAyah) {
          pendingMushafAyah.current = `${positionSurah}:${positionAyah}`;
          setSelectedMushafAyah(`${positionSurah}:${positionAyah}`);
        }
        if (positionSurah && positionSurah !== selectedSurah) {
          pendingNavigationPage.current = position.page_number;
          setSelectedSurah(positionSurah);
        }
      })
      .catch(() => {
        // Fall back to local position if server state is unavailable.
      });

    return () => {
      cancelled = true;
    };
  }, [authLoading, hasExplicitDeepLink, localPositionReady, prayerReadingConfig, selectedEdition, selectedSurah, session]);

  // Load Mushaf page when page changes and in mushaf mode
  useEffect(() => {
    if (currentPage !== previousPage.current) {
      setPageTurnDirection(currentPage > previousPage.current ? "next" : "previous");
      previousPage.current = currentPage;
    }
  }, [currentPage]);

  useEffect(() => {
    if (viewMode !== "mushaf") return;
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
    const ayahKey = pendingMushafAyah.current;
    if (
      viewMode !== "mushaf"
      || !ayahKey
      || ayahKey !== selectedMushafAyah
      || foundationPageLoading
    ) {
      return;
    }
    const target = mushafReader.current?.querySelector(`[data-ayah-key="${ayahKey}"]`);
    if (!target) return;
    pendingMushafAyah.current = null;
    const timeout = window.setTimeout(() => {
      target.scrollIntoView({
        behavior: window.matchMedia("(prefers-reduced-motion: reduce)").matches
          ? "auto"
          : "smooth",
        block: "center",
      });
    }, 80);
    return () => window.clearTimeout(timeout);
  }, [
    foundationMushafPage,
    foundationPageLoading,
    selectedMushafAyah,
    viewMode,
  ]);

  useEffect(() => {
    if (pageError && selectedFoundationMushafId !== null) {
      setFeedbackMessage({ text: api.normalizeError(pageError), type: "err" });
    }
  }, [pageError, selectedFoundationMushafId]);

  const currentSurahObj = surahs.find((s) => s.number === selectedSurah);
  const editionName = (edition: QuranEdition) =>
    locale === "ar" ? edition.name_ar : locale === "ru" ? edition.name_ru : edition.name_en;
  const surahName = (surah: Surah) =>
    locale === "ar" ? surah.name_ar : locale === "ru" ? surah.name_ru : surah.name_en;

  const handleActiveAyahChange = useCallback((ayahKey: string | null) => {
    setPlayingMushafAyah(ayahKey);
    if (isImmersiveReader) return;
    if (!ayahKey) return;
    const [surahNumber, ayahNumber] = ayahKey.split(":").map(Number);
    if (surahNumber !== selectedSurah) return;
    const activeAyah = ayahs.find((ayah) => ayah.number === ayahNumber);
    const nextPage = activeAyah ? sourcePageFor(ayahKey, activeAyah.pages[0]) : undefined;
    if (viewMode === "mushaf" && nextPage && !mushafVerseKeys.includes(ayahKey)) {
      setCurrentPage((page) => nextPage === page ? page : nextPage);
    }
  }, [ayahs, isImmersiveReader, mushafVerseKeys, selectedSurah, viewMode, sourcePageFor]);

  const navigateToDivision = useCallback((division: QuranDivision) => {
    const targetSurah = division.start_ayah.surah;
    const targetAyah = division.start_ayah.number;
    const targetPage = sourcePageFor(`${targetSurah}:${targetAyah}`, division.start_page);
    queueReadingPlace({
      pageNumber: targetPage,
      sourceId: selectedFoundationMushafId ?? undefined,
      surahNumber: targetSurah,
      ayahNumber: targetAyah,
    });
    pendingMushafAyah.current = `${targetSurah}:${targetAyah}`;
    setViewMode("mushaf");
    setSelectedMushafAyah(`${targetSurah}:${targetAyah}`);
    if (targetSurah === selectedSurah) {
      setCurrentPage(targetPage);
      return;
    }
    pendingNavigationPage.current = targetPage;
    setSelectedSurah(targetSurah);
  }, [queueReadingPlace, selectedSurah, sourcePageFor, selectedFoundationMushafId]);

  const navigateToAyah = useCallback((ayahNumber: number) => {
    const ayah = ayahs.find((item) => item.number === ayahNumber);
    if (!ayah) return;
    const ayahKey = `${selectedSurah}:${ayahNumber}`;
    textReadingAyah.current = ayahKey;
    pendingTextAyah.current = viewMode === "text" ? ayahKey : null;
    pendingMushafAyah.current = viewMode === "mushaf" ? ayahKey : null;
    setSelectedMushafAyah(ayahKey);
    if (ayah.pages.length > 0) {
      setCurrentPage(viewMode === "mushaf" ? sourcePageFor(ayahKey, ayah.pages[0]) : ayah.pages[0]);
      queueReadingPlace({
        pageNumber: ayah.pages[0],
        surahNumber: selectedSurah,
        ayahNumber,
      });
    }
  }, [ayahs, queueReadingPlace, selectedSurah, viewMode, sourcePageFor]);

  useEffect(() => {
    const ayahKey = pendingTextAyah.current;
    if (viewMode !== "text" || !ayahKey || ayahKey !== selectedMushafAyah) return;
    const target = document.getElementById(`quran-ayah-${ayahKey.replace(":", "-")}`);
    if (!target) return;
    pendingTextAyah.current = null;
    window.requestAnimationFrame(() => {
      target.scrollIntoView({ behavior: "smooth", block: "center" });
    });
  }, [ayahs, selectedMushafAyah, viewMode]);

  useEffect(() => {
    if (viewMode !== "text" || ayahs.length === 0) return;
    let scrollTimeout: number | undefined;
    const markScrollIntent = (event: Event) => {
      if (event.target instanceof Element && event.target.closest("button, a, input, select, summary")) return;
      textScrollIntent.current = true;
    };
    const rememberVisibleAyah = () => {
      if (!textScrollIntent.current) return;
      window.clearTimeout(scrollTimeout);
      scrollTimeout = window.setTimeout(() => {
        const visibleAyah = ayahs
          .map((ayah) => {
            const element = document.getElementById(
              `quran-ayah-${ayah.surah_number}-${ayah.number}`,
            );
            if (!element) return null;
            const rect = element.getBoundingClientRect();
            if (rect.bottom <= 0 || rect.top >= window.innerHeight) return null;
            return {
              ayah,
              distance: Math.abs((rect.top + rect.bottom) / 2 - window.innerHeight / 2),
            };
          })
          .filter((candidate): candidate is { ayah: Ayah; distance: number } => Boolean(candidate))
          .sort((left, right) => left.distance - right.distance)[0]?.ayah;
        const pageNumber = visibleAyah?.pages[0];
        if (!visibleAyah || pageNumber === undefined) return;
        textReadingAyah.current = `${visibleAyah.surah_number}:${visibleAyah.number}`;
        setCurrentPage(pageNumber);
        queueReadingPlace({
          pageNumber,
          surahNumber: visibleAyah.surah_number,
          ayahNumber: visibleAyah.number,
        });
      }, 350);
    };

    window.addEventListener("wheel", markScrollIntent, { passive: true });
    window.addEventListener("touchstart", markScrollIntent, { passive: true });
    window.addEventListener("pointerdown", markScrollIntent, { passive: true });
    window.addEventListener("keydown", markScrollIntent);
    window.addEventListener("scroll", rememberVisibleAyah, { passive: true });
    return () => {
      window.clearTimeout(scrollTimeout);
      window.removeEventListener("wheel", markScrollIntent);
      window.removeEventListener("touchstart", markScrollIntent);
      window.removeEventListener("pointerdown", markScrollIntent);
      window.removeEventListener("keydown", markScrollIntent);
      window.removeEventListener("scroll", rememberVisibleAyah);
    };
  }, [ayahs, queueReadingPlace, viewMode]);

  const handleSelectMushafAyah = useCallback((ayahKey: string) => {
    setSelectedMushafAyah(ayahKey);
    const [surahNumber, ayahNumber] = ayahKey.split(":").map(Number);
    if (!Number.isSafeInteger(surahNumber) || !Number.isSafeInteger(ayahNumber)) return;
    setSelectedSurah(surahNumber);
    textReadingAyah.current = ayahKey;
    const knownAyah = ayahs.find(
      (ayah) => ayah.surah_number === surahNumber && ayah.number === ayahNumber,
    );
    queueReadingPlace({
      pageNumber: knownAyah?.pages.find((page) => page === currentPage)
        ?? knownAyah?.pages[0]
        ?? currentPage,
      surahNumber,
      ayahNumber,
    });
  }, [ayahs, currentPage, queueReadingPlace]);

  const handlePlayAyah = useCallback((ayahNumber: number) => {
    const ayahKey = `${selectedSurah}:${ayahNumber}`;
    const ayah = ayahs.find((item) => item.number === ayahNumber);
    ayahPlaybackRequestId.current += 1;
    setSelectedMushafAyah(ayahKey);
    queueReadingPlace({
      pageNumber: ayah?.pages[0] ?? currentPage,
      surahNumber: selectedSurah,
      ayahNumber,
    });
    setPlayAyahRequest({
      requestId: ayahPlaybackRequestId.current,
      ayahKey,
    });
  }, [ayahs, currentPage, queueReadingPlace, selectedSurah]);

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
    const nextPage = direction === "next"
      ? Math.min(mushafPageCount, currentPage + 1)
      : Math.max(1, currentPage - 1);
    setPageTurnDirection(direction);
    pendingMushafAyah.current = null;
    pendingNavigationPage.current = null;
    setSelectedMushafAyah(null);
    setCurrentPage(nextPage);
    queueReadingPlace({ pageNumber: nextPage });
  }, [currentPage, mushafPageCount, queueReadingPlace]);

  const annotationTarget = (ayahKey: string) => {
    const [surahNumber, ayahNumber] = ayahKey.split(":").map(Number);
    const ayah = ayahs.find(
      (item) => item.surah_number === surahNumber && item.number === ayahNumber,
    );
    return {
      edition_code: selectedEdition,
      surah_number: surahNumber,
      ayah_number: ayahNumber,
      page_number: ayah?.pages.find((page) => page === currentPage) ?? ayah?.pages[0] ?? null,
    };
  };

  const showAnnotationFeedback = (text: string) => {
    setFeedbackMessage({ text, type: "ok" });
    window.setTimeout(() => setFeedbackMessage(null), 4000);
  };

  const handleSaveAnnotation = async (
    ayahKey: string,
    colorKey: AyahHighlightColorKey,
    note: string,
  ): Promise<string | null> => {
    if (!api.getSession() && !(await loginGuest())) return t("annotation.loginError");
    const previousNote = ayahAnnotations[ayahKey]?.note.trim() ?? "";
    const success = note.trim()
      ? t("annotation.noteSaved")
      : previousNote ? t("annotation.noteRemoved") : t("annotation.highlightSaved");
    try {
      await api.saveAyahAnnotation({ ...annotationTarget(ayahKey), color_key: colorKey, note });
      showAnnotationFeedback(success);
      return null;
    } catch (err) {
      if (err instanceof OfflineMutationQueuedError) {
        showAnnotationFeedback(err.message);
        return null;
      }
      return api.normalizeError(err);
    }
  };

  const handleRemoveAnnotation = async (ayahKey: string): Promise<string | null> => {
    try {
      await api.deleteAyahAnnotation(annotationTarget(ayahKey));
      showAnnotationFeedback(t("annotation.highlightRemoved"));
      return null;
    } catch (err) {
      if (err instanceof OfflineMutationQueuedError) {
        showAnnotationFeedback(err.message);
        return null;
      }
      return api.normalizeError(err);
    }
  };

  const openAyahShare = (ayahKey: string) => {
    const [surahNumber, ayahNumber] = ayahKey.split(":").map(Number);
    const surah = surahs.find((item) => item.number === surahNumber);
    const ayah = ayahs.find(
      (item) => item.surah_number === surahNumber && item.number === ayahNumber,
    );
    setShareTarget({
      ayahKey,
      edition: selectedEdition,
      title: `${surah ? localizedSurahName(surah, locale) : t("common.surah", { surah: surahNumber })} · ${ayahKey}`,
      url: new URL(
        localizedPath(locale, quranAyahPath(selectedEdition, surahNumber, ayahNumber)),
        window.location.origin,
      ).href,
      arabic: ayah?.text_uthmani,
      translationId: selectedTranslationId,
      // While another translation loads, the old text is still shown; the
      // dialog then fetches the selected one, so text and translator match.
      translation: translationLoading ? undefined : translationsByVerse[ayahKey]?.text,
      translator: selectedTranslation
        ? selectedTranslation.author_name.trim() || selectedTranslation.name
        : "",
    });
  };

  // Without the dialog's code the ayah still goes, as the text the reader has
  // and the link.
  const shareAyahWithoutPicture = async (target: AyahShareTarget) => {
    reloadAyahShareDialog();
    setShareTarget(null);
    const translation = target.translation ?? "";
    const result = await shareTextOnly(target.title, contentShareText(
      target.title,
      {
        arabic: target.arabic ?? "",
        translation,
        reference: translation.trim() ? target.translator : "",
      },
      t("contentShare.readInIqro"),
      target.url,
    ));
    if (result === "copied") showAnnotationFeedback(t("contentShare.textCopied"));
    if (result === "failed") setFeedbackMessage({ text: t("contentShare.shareError"), type: "err" });
  };

  const handleToggleBookmark = async (ayahNumber: number) => {
    const ayahKey = `${selectedSurah}:${ayahNumber}`;
    if (!bookmarkStateReady || bookmarkBusyKeys.has(ayahKey)) return;
    if (!isLoggedIn) {
      const res = await loginGuest();
      if (!res) {
        setFeedbackMessage({ text: t("quran.bookmarkLoginError"), type: "err" });
        return;
      }
    }

    setBookmarkBusyKeys((current) => new Set(current).add(ayahKey));
    try {
      const existing = savedAyahBookmarks[ayahKey];
      if (existing) {
        await api.deleteBookmark(existing.id, existing.revision);
        setSavedAyahBookmarks((current) => {
          const next = { ...current };
          delete next[ayahKey];
          return next;
        });
        setFeedbackMessage({ text: t("quran.bookmarkRemoved"), type: "ok" });
      } else {
        const bookmarkedAyah = await api.getAyah(selectedEdition, selectedSurah, ayahNumber);
        const bookmarkPage = bookmarkedAyah.pages[0];
        if (!bookmarkPage) throw new Error("Missing canonical ayah page");
        const created = await api.createBookmark({
          edition_code: selectedEdition,
          page_number: bookmarkPage,
          surah_number: selectedSurah,
          ayah_number: ayahNumber,
          label: t("quran.bookmarkLabel", {
            surah: selectedSurah,
            ayah: ayahNumber,
            page: bookmarkPage,
          }),
          color_key: "emerald",
        });
        setSavedAyahBookmarks((current) => ({ ...current, [ayahKey]: created }));
        setBookmarkAnimationKey(ayahKey);
        window.setTimeout(() => {
          setBookmarkAnimationKey((current) => current === ayahKey ? null : current);
        }, 900);
        setFeedbackMessage({ text: t("quran.bookmarkAdded"), type: "ok" });
      }
      setTimeout(() => setFeedbackMessage(null), 4000);
    } catch (err) {
      setFeedbackMessage({ text: api.normalizeError(err), type: "err" });
    } finally {
      setBookmarkBusyKeys((current) => {
        const next = new Set(current);
        next.delete(ayahKey);
        return next;
      });
    }
  };

  return (
    <MushafReaderLayout
      active={viewMode === "mushaf"}
      page={currentPage}
      count={mushafPageCount}
      pageRatio={900 / 1380}
      hasNotes={translationEnabled || tafsirEnabled}
      hasSession={prayerReadingConfig !== null}
      onImmersiveChange={setIsImmersiveReader}
    >
      <MushafReaderPanel name="session" label={t("quran.readerSession")}>
        {prayerReadingConfig === null ? (
          <ReadingActivityTracker currentPage={canonicalPage ?? 1} viewMode={viewMode} creditPageProgress={canonicalPage !== null} />
        ) : prayerReadingReady ? (
          <>
            {!prayerReadingFinished && (
              <ReadingActivityTracker
                currentPage={canonicalPage ?? 1}
                viewMode={viewMode}
                creditPageProgress={false}
                persistActivity={false}
                timezoneName={prayerReadingConfig.timezoneName}
                onActiveSecondsChange={setPrayerReadingActiveSeconds}
              />
            )}
            <PrayerReadingSessionBar
              config={prayerReadingConfig}
              currentPage={canonicalPage}
              edition={selectedEdition}
              surah={selectedSurah}
              activeSeconds={prayerReadingActiveSeconds}
              onFinished={() => setPrayerReadingFinished(true)}
            />
          </>
        ) : (
          <section className="surface prayer-reading-session" aria-live="polite">
            {t("common.loading")}
          </section>
        )}
      </MushafReaderPanel>
      {/* Control Bar */}
      <MushafReaderPanel name="settings" label={t("quran.readerSettings")} className="surface quran-control-surface">
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

          <div className="quran-mode-switch">
            <button
              className={`btn ${viewMode === "text" ? "btn-primary" : "btn-secondary"}`}
              disabled={!localPositionReady}
              onClick={() => {
                const target = currentAyahKey;
                lastMushafLocation.current = { sourceId: selectedFoundationMushafId, ayah: target, page: currentPage };
                pendingTextAyah.current = target;
                textReadingAyah.current = target;
                textScrollIntent.current = false;
                setSelectedMushafAyah(target);
                if (target) setSelectedSurah(Number(target.split(":")[0]));
                if (canonicalPage !== null) setCurrentPage(canonicalPage);
                setViewMode("text");
              }}
            >
              {t("quran.textView")}
            </button>
            <button
              className={`btn ${viewMode === "mushaf" ? "btn-primary" : "btn-secondary"}`}
              onClick={() => {
                const target = textReadingAyah.current ?? selectedMushafAyah;
                const previous = lastMushafLocation.current;
                if (previous?.sourceId === selectedFoundationMushafId && previous?.ayah === target) {
                  setCurrentPage(previous.page);
                }
                pendingMushafAyah.current = target;
                setSelectedMushafAyah(target);
                textScrollIntent.current = false;
                setViewMode("mushaf");
              }}
            >
              {t("quran.mushafView", { page: currentPage })}
            </button>
          </div>
        </div>

        {feedbackMessage && (
          <div className={`alert ${feedbackMessage.type === "ok" ? "alert-success" : "alert-error"}`} style={{ marginBottom: 16 }}>
            {feedbackMessage.text}
          </div>
        )}

        <MushafReaderSettings>
          <div className="form-row quran-primary-controls">
            <div className="form-group">
              <label className="form-label" htmlFor="quran-edition">{t("quran.edition")}</label>
              <select
                id="quran-edition"
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
                value={selectedFoundationMushafId === null ? "" : String(selectedFoundationMushafId)}
                disabled={foundationMushafs.length === 0}
                onChange={(event) => {
                  const value = event.target.value;
                  const sourceId = Number(value);
                  pendingMushafAyah.current = currentAyahKey;
                  setSelectedFoundationMushafId(sourceId);
                  writeMushafVariantPreference(sourceId);
                  setSelectedMushafAyah(currentAyahKey);
                  setCurrentPage((page) => Math.min(page, foundationMushafs.find((mushaf) => mushaf.source_id === sourceId)?.pages_count ?? 604));
                }}
              >
                {foundationMushafs.length === 0 && <option value="">{t("quran.mushafUnavailable")}</option>}
                {foundationMushafs.map((mushaf) => (
                  <option value={mushaf.source_id} key={mushaf.source_id}>
                    {mushaf.name} · {mushaf.qirat_name}
                  </option>
                ))}
              </select>
            </div>

            <div className="form-group">
              <label className="form-label" htmlFor="surah-navigation">
                {t("quran.surahSelect")}
              </label>
              <select
                id="surah-navigation"
                value={selectedSurah}
                onChange={(event) => {
                  const targetSurah = Number(event.target.value);
                  const targetAyahKey = `${targetSurah}:1`;
                  textReadingAyah.current = targetAyahKey;
                  const canonicalPage = surahs.find((item) => item.number === targetSurah)?.first_page;
                  const targetPage = canonicalPage == null ? undefined : viewMode === "mushaf" ? sourcePageFor(targetAyahKey, canonicalPage) : canonicalPage;
                  pendingTextAyah.current = viewMode === "text" ? targetAyahKey : null;
                  pendingMushafAyah.current = viewMode === "mushaf" ? targetAyahKey : null;
                  setSelectedMushafAyah(targetAyahKey);
                  if (targetPage) {
                    setCurrentPage(targetPage);
                    queueReadingPlace({
                      pageNumber: targetPage,
                      surahNumber: targetSurah,
                      ayahNumber: 1,
                    });
                  }
                  setSelectedSurah(targetSurah);
                }}
                disabled={surahs.length === 0}
              >
                {surahs.map((s) => (
                  <option key={s.id} value={s.number}>
                    {s.number}. {surahName(s)} — {s.name_ar} ({t("quran.ayahsShort", { count: s.ayah_count })})
                  </option>
                ))}
              </select>
            </div>

            <div className="form-group quran-page-jump">
              <label className="form-label" htmlFor="mushaf-page-jump">{t("quran.mushafPage")}</label>
              <div style={{ display: "flex", gap: 8 }}>
                <button
                  className="btn btn-secondary btn-sm"
                  onClick={() => turnMushafPage("previous")}
                  disabled={currentPage <= 1}
                >
                  ◀ {t("common.back")}
                </button>
                <input
                  id="mushaf-page-jump"
                  type="number"
                  min={1}
                  max={mushafPageCount}
                  value={currentPage}
                  onChange={(e) => {
                    const nextPage = Math.min(
                      mushafPageCount,
                      Math.max(1, Number(e.target.value)),
                    );
                    pendingMushafAyah.current = null;
                    pendingNavigationPage.current = null;
                    setSelectedMushafAyah(null);
                    setCurrentPage(nextPage);
                    queueReadingPlace({ pageNumber: nextPage });
                  }}
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

          <div className="translation-settings" style={{ marginTop: 14 }}>
            <label className="translation-toggle" htmlFor="translation-enabled">
              <input
                id="translation-enabled"
                type="checkbox"
                checked={translationEnabled}
                onChange={(event) => setTranslationEnabled(event.target.checked)}
                disabled={translationEditions.length === 0}
              />
              <span>
                <strong>{t("quran.translationToggle")}</strong>
                <small>{t("quran.translationHelp")}</small>
              </span>
            </label>
            <div className="translation-edition-control">
              <label className="form-label" htmlFor="translation-edition">
                {t("quran.translationEdition")}
              </label>
              <select
                id="translation-edition"
                value={selectedTranslationId ?? ""}
                onChange={(event) => {
                  const sourceId = Number(event.target.value);
                  setSelectedTranslationId(
                    Number.isSafeInteger(sourceId) && sourceId > 0 ? sourceId : null,
                  );
                }}
                disabled={!translationEnabled || translationEditions.length === 0}
              >
                {translationEditions.length === 0 ? (
                  <option value="">{t("quran.translationUnavailable")}</option>
                ) : selectedTranslationId === null ? (
                  <option value="">{t("quran.translationChoose")}</option>
                ) : null}
                {translationEditions.map((edition) => (
                  <option key={edition.source_id} value={edition.source_id}>
                    {edition.name} · {edition.author_name}
                  </option>
                ))}
              </select>
            </div>
            {translationEnabled && selectedTranslation && (
              <p className="translation-source-note">
                {selectedTranslation.name} · {selectedTranslation.author_name}.{" "}
                <a href={selectedTranslation.source.url} target="_blank" rel="noreferrer">
                  {selectedTranslation.source.attribution}
                </a>
              </p>
            )}
            {locale === "ar" && translationEditions.length === 0 && (
              <p className="translation-context-note">
                {t("quran.translationArabicTafsirNotice")}
              </p>
            )}
            {translationError && (
              <p className="translation-error" role="status">
                {t("quran.translationError")}
              </p>
            )}
          </div>

          <div className="translation-settings tafsir-settings" style={{ marginTop: 12 }}>
            <label className="translation-toggle" htmlFor="tafsir-enabled">
              <input
                id="tafsir-enabled"
                type="checkbox"
                checked={tafsirEnabled}
                onChange={(event) => setTafsirEnabled(event.target.checked)}
                disabled={tafsirEditions.length === 0 || selectedTafsirId === null}
              />
              <span>
                <strong>{t("quran.tafsirToggle")}</strong>
                <small>{t("quran.tafsirHelp")}</small>
              </span>
            </label>
            <div className="translation-edition-control">
              <label className="form-label" htmlFor="tafsir-edition">
                {t("quran.tafsirEdition")}
              </label>
              <select
                id="tafsir-edition"
                value={selectedTafsirId ?? ""}
                onChange={(event) => {
                  const sourceId = Number(event.target.value);
                  setSelectedTafsirId(
                    Number.isSafeInteger(sourceId) && sourceId > 0 ? sourceId : null,
                  );
                }}
                disabled={tafsirEditions.length === 0}
              >
                {tafsirEditions.length === 0 ? (
                  <option value="">{t("quran.tafsirUnavailable")}</option>
                ) : selectedTafsirId === null ? (
                  <option value="">{t("quran.tafsirChoose")}</option>
                ) : null}
                {tafsirEditions.map((edition) => (
                  <option key={edition.source_id} value={edition.source_id}>
                    {edition.name} · {edition.author_name}
                  </option>
                ))}
              </select>
            </div>
            {selectedTafsir && (
              <p className="translation-source-note">
                {selectedTafsir.name} · {selectedTafsir.author_name}.{" "}
                <a href={selectedTafsir.source.url} target="_blank" rel="noreferrer">
                  {selectedTafsir.source.attribution}
                </a>
              </p>
            )}
            {locale === "tr" && !tafsirEditions.some((edition) => edition.language_code === "tr") && (
              <p className="translation-context-note">{t("quran.tafsirTurkishUnavailable")}</p>
            )}
            {tafsirError && (
              <p className="translation-error" role="status">
                {t("quran.tafsirError")}
              </p>
            )}
            {preferenceSyncError && (
              <p className="translation-context-note" role="status">
                {t("quran.preferenceSyncError")}
              </p>
            )}
          </div>

          <div className="form-row" style={{ marginTop: 14 }}>
            <div className="form-group">
              <label className="form-label" htmlFor="juz-navigation">{t("quran.juz")}</label>
              <select
                id="juz-navigation"
                value={currentAyah?.juz_number ?? divisionAtAyah(juz, currentAyahKey)}
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
                value={currentAyah?.hizb_number ?? divisionAtAyah(hizb, currentAyahKey)}
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
                value={currentAyah?.rub_el_hizb_number ?? divisionAtAyah(rubElHizb, currentAyahKey)}
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
                value={currentAyahKey?.split(":")[1] ?? ""}
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
        </MushafReaderSettings>
        {selectedFoundationMushaf && (
          <p className="reader-source-note">
            {selectedFoundationMushaf.source.attribution}{" "}
            <a href={selectedFoundationMushaf.source.url} target="_blank" rel="noreferrer">{selectedFoundationMushaf.source.name}</a>
          </p>
        )}
      </MushafReaderPanel>

      <MushafReaderPanel name="audio" label={t("audio.playerTitle")} className="surface quran-audio-surface">
        <MushafAudioPlayer
          editionCode={selectedEdition}
          selectedSurah={selectedSurah}
          selectedAyahKey={selectedMushafAyah}
          readerPageKey={viewMode === "mushaf" ? `${selectedEdition}:${selectedFoundationMushafId ?? "unavailable"}:${currentPage}` : undefined}
          readerAyahKey={selectedMushafAyah && mushafVerseKeys.includes(selectedMushafAyah)
            && !foundationPageLoading
            && foundationMushafPage?.page_number === currentPage
            ? selectedMushafAyah : null}
          playAyahRequest={playAyahRequest}
          controlRequest={playerControlRequest}
          onActiveAyahChange={handleActiveAyahChange}
          onPlayingChange={setIsAudioPlaying}
          onSettingsChange={setAudioSettings}
        />
      </MushafReaderPanel>

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
                const savedBookmark = savedAyahBookmarks[ayahKey];
                const annotation = ayahAnnotations[ayahKey];
                const bookmarkBusy = bookmarkBusyKeys.has(ayahKey);
                const bookmarkAnimating = bookmarkAnimationKey === ayahKey;
                const ayahTafsir = tafsirsByVerse[ayahKey];
                const isTafsirExpanded = expandedTafsirVerse === ayahKey;
                const playbackActionLabel = isAyahPlaying
                  ? t("player.pausePlayback")
                  : isAyahActive
                    ? t("player.continue")
                    : t("player.play");
                return (
                  <article
                    key={ayah.id}
                    id={`quran-ayah-${selectedSurah}-${ayah.number}`}
                    className={`ayah-card${playingMushafAyah === ayahKey ? " is-audio-active" : ""}${selectedMushafAyah === ayahKey ? " is-navigation-target" : ""}`}
                    data-highlight={annotation?.color_key}
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
                            className={`btn btn-sm ayah-icon-button ayah-speed-button${audioSettings.playbackRate !== 1 ? " is-active" : ""}`}
                            type="button"
                            onClick={() => sendPlayerControl("cycle-speed")}
                            aria-label={`${t("player.speedAria")}: ${formatNumber(audioSettings.playbackRate)}×`}
                            title={`${t("player.speedAria")}: ${formatNumber(audioSettings.playbackRate)}×`}
                          >
                            {formatNumber(audioSettings.playbackRate)}×
                          </button>
                          <button
                            className={`btn btn-sm ayah-icon-button quran-favorite-button${savedBookmark ? " is-saved" : ""}${bookmarkAnimating ? " is-animating" : ""}`}
                            type="button"
                            onClick={() => void handleToggleBookmark(ayah.number)}
                            aria-label={savedBookmark
                              ? t("quran.bookmarkRemoveTitle")
                              : t("quran.bookmarkTitle")}
                            title={savedBookmark
                              ? t("quran.bookmarkRemoveTitle")
                              : t("quran.bookmarkTitle")}
                            aria-pressed={Boolean(savedBookmark)}
                            aria-busy={bookmarkBusy || !bookmarkStateReady}
                            disabled={bookmarkBusy || !bookmarkStateReady}
                          >
                            <FavoriteBookmarkIcon active={Boolean(savedBookmark)} />
                          </button>
                          <button
                            className={`btn btn-sm ayah-icon-button${annotation ? " is-active" : ""}`}
                            type="button"
                            onClick={() => setAnnotationAyahKey(ayahKey)}
                            aria-label={`${t("annotation.action")}: ${t("common.ayah", { ayah: ayahKey })}${annotation ? ` · ${ayahAnnotationLabels[ayahKey]}` : ""}`}
                            title={t("annotation.action")}
                            aria-haspopup="dialog"
                          >
                            <span aria-hidden="true">✎</span>
                          </button>
                          <button
                            className="btn btn-sm ayah-icon-button"
                            type="button"
                            onClick={() => openAyahShare(ayahKey)}
                            aria-label={`${t("ayahShare.action")}: ${t("common.ayah", { ayah: ayahKey })}`}
                            title={t("ayahShare.action")}
                            aria-haspopup="dialog"
                          >
                            <ShareIcon />
                          </button>
                        </div>
                      </div>
                    </div>

                    {/* A no-break space keeps the marker with the last word. The
                        header already gives the number to screen readers. */}
                    <p className="quran-arabic-text">
                      {ayah.text_uthmani}{"\u00A0"}
                      <span className="ayah-end-marker" aria-hidden="true">{ayahEndMarker(ayah.number)}</span>
                    </p>
                    {translationEnabled && (
                      <div className="ayah-translation notranslate" translate="no">
                        {translationLoading ? (
                          <span className="ayah-translation-status">
                            {t("quran.translationLoading")}
                          </span>
                        ) : translationsByVerse[ayahKey] ? (
                          <>
                            <p>{translationsByVerse[ayahKey].text}</p>
                            <TranslationFootnotes
                              footNotes={translationsByVerse[ayahKey].foot_notes}
                            />
                          </>
                        ) : null}
                      </div>
                    )}
                    {tafsirEnabled && (
                      <div className="ayah-tafsir notranslate" translate="no">
                        <div className="ayah-tafsir-toolbar">
                          <div>
                            <strong>{t("quran.tafsirToggle")}</strong>
                            <span>{selectedTafsir?.name}</span>
                          </div>
                          <button
                            className="btn btn-secondary btn-sm"
                            type="button"
                            onClick={() => setExpandedTafsirVerse(
                              isTafsirExpanded ? null : ayahKey,
                            )}
                            disabled={tafsirLoading || !ayahTafsir}
                            aria-expanded={isTafsirExpanded}
                          >
                            {tafsirLoading
                              ? t("quran.tafsirLoading")
                              : isTafsirExpanded
                                ? t("quran.tafsirClose")
                                : t("quran.tafsirOpen")}
                          </button>
                        </div>
                        {isTafsirExpanded && ayahTafsir && (
                          <div className="ayah-tafsir-content">
                            <span>
                              {ayahTafsir.group_verses_count > 1
                                ? t("quran.tafsirRange", {
                                    from: ayahTafsir.start_verse_key,
                                    to: ayahTafsir.end_verse_key,
                                  })
                                : t("quran.tafsirForAyah", { ayah: ayahTafsir.verse_key })}
                            </span>
                            <p>{ayahTafsir.text}</p>
                          </div>
                        )}
                      </div>
                    )}
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
          <MushafGestureSurface
            onTurnPage={turnMushafPage}
            label={t("quran.madaniPage", { page: currentPage })}
          >
            {selectedFoundationMushaf ? (
              pageError || foundationIndexError ? (
                <div className="alert alert-error" role="alert">
                  {t("quran.mushafUnavailable")}
                  <button type="button" className="btn btn-secondary" onClick={() => window.location.reload()}>{t("errorPage.retry")}</button>
                </div>
              ) : foundationPageLoading || !versePages ? (
                <div className="qf-mushaf-page-loading">{t("quran.qfPageLoading")}</div>
              ) : foundationMushafPage ? (
                <MushafPageTurn
                  direction={pageTurnDirection}
                  pageId={`${selectedFoundationMushaf.source_id}-${foundationMushafPage.page_number}`}
                  key={selectedFoundationMushaf.source_id}
                >
                  <QuranFoundationMushafPageView
                    mushaf={selectedFoundationMushaf}
                    page={foundationMushafPage}
                    surahs={surahs}
                    selectedAyahKey={selectedMushafAyah}
                    playingAyahKey={playingMushafAyah}
                    highlightColors={ayahHighlightColors}
                    annotationLabels={ayahAnnotationLabels}
                    onSelectAyah={handleSelectMushafAyah}
                  />
                </MushafPageTurn>
              ) : null
            ) : (
              <p role="status" className="qf-mushaf-page-loading">{t("quran.mushafUnavailable")}</p>
            )}
          </MushafGestureSurface>

          {selectedMushafAyah && mushafVerseKeys.includes(selectedMushafAyah) && (
            <div className="mushaf-ayah-actions">
              <span>{t("common.ayah", { ayah: selectedMushafAyah })}</span>
              <button
                className={`btn btn-secondary btn-sm${ayahAnnotations[selectedMushafAyah] ? " is-active" : ""}`}
                type="button"
                onClick={() => setAnnotationAyahKey(selectedMushafAyah)}
                aria-haspopup="dialog"
                aria-label={ayahAnnotationLabels[selectedMushafAyah]
                  ? `${t("annotation.action")} · ${ayahAnnotationLabels[selectedMushafAyah]}`
                  : undefined}
              >
                <span aria-hidden="true">✎ </span>{t("annotation.action")}
              </button>
              <button
                className="btn btn-secondary btn-sm"
                type="button"
                onClick={() => openAyahShare(selectedMushafAyah)}
                aria-haspopup="dialog"
                aria-label={`${t("ayahShare.action")}: ${t("common.ayah", { ayah: selectedMushafAyah })}`}
              >
                <ShareIcon /> {t("contentShare.share")}
              </button>
            </div>
          )}

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
          <MushafReaderPanel name="notes" label={t("quran.readerNotes")}>
            {translationEnabled && (
              <aside
                className="mushaf-translation-panel notranslate"
                translate="no"
                aria-label={t("quran.translationToggle")}
              >
                <div className="mushaf-translation-heading">
                  <div>
                    <span className="eyebrow">{t("quran.translationToggle")}</span>
                    <strong>{selectedTranslation?.name}</strong>
                  </div>
                  <span>{t("quran.translationPage", { page: currentPage })}</span>
                </div>
                {translationLoading ? (
                  <p className="ayah-translation-status">{t("quran.translationLoading")}</p>
                ) : mushafTranslations.length > 0 ? (
                  <div className="mushaf-translation-list">
                    {mushafTranslations.map((translation) => (
                      <article key={translation.verse_key}>
                        <span>{translation.verse_key}</span>
                        <div>
                          <p>{translation.text}</p>
                          <TranslationFootnotes footNotes={translation.foot_notes} />
                        </div>
                      </article>
                    ))}
                  </div>
                ) : (
                  <p className="ayah-translation-status">
                    {t("quran.translationPageUnavailable")}
                  </p>
                )}
              </aside>
            )}
            {tafsirEnabled && (
              <aside
                className="mushaf-translation-panel mushaf-tafsir-panel notranslate"
                translate="no"
                aria-label={t("quran.tafsirToggle")}
              >
                <div className="mushaf-translation-heading">
                  <div>
                    <span className="eyebrow">{t("quran.tafsirToggle")}</span>
                    <strong>{selectedTafsir?.name}</strong>
                  </div>
                  {selectedMushafAyah && <span>{selectedMushafAyah}</span>}
                </div>
                {tafsirLoading ? (
                  <p className="ayah-translation-status">{t("quran.tafsirLoading")}</p>
                ) : !selectedMushafAyah ? (
                  <p className="ayah-translation-status">{t("quran.tafsirSelectAyah")}</p>
                ) : selectedMushafTafsir ? (
                  <div className="ayah-tafsir-content">
                    <span>
                      {selectedMushafTafsir.group_verses_count > 1
                        ? t("quran.tafsirRange", {
                            from: selectedMushafTafsir.start_verse_key,
                            to: selectedMushafTafsir.end_verse_key,
                          })
                        : t("quran.tafsirForAyah", { ayah: selectedMushafTafsir.verse_key })}
                    </span>
                    <p>{selectedMushafTafsir.text}</p>
                  </div>
                ) : (
                  <p className="ayah-translation-status">{t("quran.tafsirAyahUnavailable")}</p>
                )}
              </aside>
            )}
          </MushafReaderPanel>
        </section>
      )}
      {annotationAyahKey && (
        <AyahAnnotationDialog
          key={annotationAyahKey}
          ayahKey={annotationAyahKey}
          annotation={ayahAnnotations[annotationAyahKey]}
          ready={annotationsReady}
          onSave={(colorKey, note) => handleSaveAnnotation(annotationAyahKey, colorKey, note)}
          onRemove={() => handleRemoveAnnotation(annotationAyahKey)}
          onClose={() => setAnnotationAyahKey(null)}
        />
      )}
      {shareTarget && (
        <ShareDialogBoundary key={shareTarget.ayahKey} onFailure={() => void shareAyahWithoutPicture(shareTarget)}>
          <AyahShareDialog target={shareTarget} onClose={() => setShareTarget(null)} />
        </ShareDialogBoundary>
      )}
    </MushafReaderLayout>
  );
}

// The reader reads the query string and the saved position, so it renders in
// the browser only. Until it mounts, the server HTML shows the canonical text of
// the first Mushaf page and links to every surah.
function QuranReaderPreview({ preview }: { preview?: PublishedQuranReaderPreview | null }) {
  const { locale, t } = useI18n();
  if (!preview) return <div className="quran-reader-boot">{t("quran.loading")}</div>;
  const { edition, surahs, firstPageAyahs } = preview;
  const firstSurah = surahs.find((surah) => surah.number === firstPageAyahs[0]?.surah_number);
  return (
    <div className="quran-reader-boot quran-reader-preview" aria-busy="true">
      <p className="eyebrow">{t("quran.eyebrow")}</p>
      <h1 className="surface-title">
        {firstSurah
          ? `${firstSurah.number}. ${localizedSurahName(firstSurah, locale)} (${firstSurah.name_ar})`
          : t("nav.quran")}
      </h1>
      <p className="surface-subtitle">
        {localizedEditionName(edition, locale)} · {t("quran.loading")}
      </p>
      {firstPageAyahs.length > 0 && (
        <p className="quran-arabic-text quran-reader-preview-page" lang="ar" dir="rtl">
          {firstPageAyahs
            .map((ayah) => `${ayah.text_uthmani} ${ayahEndMarker(ayah.number)}`)
            .join(" ")}
        </p>
      )}
      <nav className="quran-reader-preview-surahs" aria-label={t("home.surahCatalog")}>
        {surahs.map((surah) => (
          <a key={surah.id} href={localizedPath(locale, quranSurahPath(edition.code, surah.number))}>
            {surah.number}. {localizedSurahName(surah, locale)}
          </a>
        ))}
      </nav>
    </div>
  );
}

export default function QuranPage({ preview }: { preview?: PublishedQuranReaderPreview | null }) {
  return (
    <Suspense fallback={<QuranReaderPreview preview={preview} />}>
      <QuranContent />
    </Suspense>
  );
}
