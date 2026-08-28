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
  ApiError,
  Ayah,
  type AyahTafsir,
  Hizb,
  Juz,
  MushafPage,
  QuranDivision,
  QuranEdition,
  QuranFoundationMushaf,
  QuranFoundationMushafPage,
  QuranTranslationEdition,
  type QuranTafsirEdition,
  RubElHizb,
  Surah,
  type AyahTranslation,
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

const TRANSLATION_PREFERENCE_KEY_PREFIX = "iqro_quran_translation_v2";
const READER_PREFERENCE_KEY_PREFIX = "iqro_quran_reader_preference_v1";
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

function QuranContent() {
  const searchParams = useSearchParams();
  const deepLinkSurah = positiveInteger(searchParams.get("surah")) || 1;
  const deepLinkAyah = positiveInteger(searchParams.get("ayah"));
  const deepLinkKey = deepLinkAyah === null ? null : `${deepLinkSurah}:${deepLinkAyah}`;
  const deepLinkPageCandidate = positiveInteger(searchParams.get("page"));
  const deepLinkPage = deepLinkPageCandidate !== null && deepLinkPageCandidate <= 604
    ? deepLinkPageCandidate
    : null;

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
  const [currentPage, setCurrentPage] = useState<number>(deepLinkPage || 1);
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
  const handledPageDeepLink = useRef<number | null>(null);
  const handledPrayerReadingStart = useRef(false);
  const ayahPlaybackRequestId = useRef(0);
  const playerControlRequestId = useRef(0);
  const selectedFoundationMushaf = useMemo(
    () => foundationMushafs.find((mushaf) => mushaf.source_id === selectedFoundationMushafId) || null,
    [foundationMushafs, selectedFoundationMushafId],
  );
  const mushafPageCount = selectedFoundationMushaf?.pages_count || 604;
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
    if (foundationMushafPage) return expandVerseMapping(foundationMushafPage.verse_mapping);
    if (mushafPage) {
      return [
        ...new Set(
          mushafPage.regions.map(
            (region) => `${region.ayah.surah}:${region.ayah.number}`,
          ),
        ),
      ];
    }
    return ayahs
      .filter((ayah) => ayah.pages.includes(currentPage))
      .map((ayah) => `${ayah.surah_number}:${ayah.number}`);
  }, [ayahs, currentPage, foundationMushafPage, mushafPage]);
  const [viewMode, setViewMode] = useState<"text" | "mushaf">(
    deepLinkAyah === null && deepLinkPage === null && prayerReadingConfig === null
      ? "text"
      : "mushaf",
  );
  const requiredTranslationSurahs = useMemo(() => {
    if (viewMode === "text") return [selectedSurah];
    const pageSurahs = mushafVerseKeys.map((key) => Number(key.split(":")[0]));
    return [...new Set([selectedSurah, ...pageSurahs])].filter(Number.isSafeInteger);
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
        } else if (deepLinkAyah === null && deepLinkPage !== null) {
          setCurrentPage(deepLinkPage);
          handledPageDeepLink.current = deepLinkPage;
        } else if (res.length > 0 && res[0].pages?.length > 0) {
          setCurrentPage(res[0].pages[0]);
        }
      })
      .catch((err) => {
        setLoading(false);
        setFeedbackMessage({ text: api.normalizeError(err), type: "err" });
      });
  }, [deepLinkAyah, deepLinkPage, selectedEdition, selectedSurah]);

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
        <>
          {!prayerReadingFinished && (
            <ReadingActivityTracker
              currentPage={currentPage}
              viewMode={viewMode}
              creditPageProgress={false}
              timezoneName={prayerReadingConfig.timezoneName}
              onActiveSecondsChange={setPrayerReadingActiveSeconds}
            />
          )}
          <PrayerReadingSessionBar
            config={prayerReadingConfig}
            currentPage={currentPage}
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
