"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import {
  api,
  Ayah,
  QuranFoundationMushaf,
  QuranFoundationMushafPage,
} from "../lib/api";
import { useI18n } from "../lib/i18n-context";
import { isAllowedQuranFontUrl } from "../lib/quran-font";

type MemorizationTajweedAyahsProps = {
  ayahs: Ayah[];
  hiddenAyahs: Set<number>;
  onReveal: (ayahNumber: number) => void;
};

type TajweedWord = {
  key: string;
  text: string;
  fontFamily: string;
  isAyahEnd: boolean;
};

type LoadState = "loading" | "ready" | "fallback";
const MAX_PARALLEL_PAGE_REQUESTS = 6;

function verseKeysFromMapping(mapping: Record<string, string>): string[] {
  const keys: string[] = [];
  for (const [surahValue, rangeValue] of Object.entries(mapping).sort(
    ([left], [right]) => Number(left) - Number(right),
  )) {
    const surah = Number(surahValue);
    const match = /^(\d+)(?:-(\d+))?$/.exec(rangeValue.trim());
    if (!Number.isInteger(surah) || !match) continue;
    const start = Number(match[1]);
    const end = Number(match[2] || match[1]);
    if (start < 1 || end < start) continue;
    for (let ayah = start; ayah <= end; ayah += 1) keys.push(`${surah}:${ayah}`);
  }
  return keys;
}

function verseKeyById(page: QuranFoundationMushafPage): Map<number, string> {
  const verseIds: number[] = [];
  const seen = new Set<number>();
  for (const word of [...page.words].sort(
    (left, right) => left.position_in_page - right.position_in_page,
  )) {
    if (word.verse_id === null || seen.has(word.verse_id)) continue;
    seen.add(word.verse_id);
    verseIds.push(word.verse_id);
  }
  const verseKeys = verseKeysFromMapping(page.verse_mapping);
  return new Map(
    verseIds.slice(0, verseKeys.length).map((verseId, index) => [verseId, verseKeys[index]]),
  );
}

function tajweedMushaf(catalog: QuranFoundationMushaf[]): QuranFoundationMushaf | undefined {
  return catalog.find(
    (item) =>
      item.default_font_name === "v4-tajweed" &&
      item.rendering.available &&
      item.rendering.mode === "page-font" &&
      item.rendering.color_format === "COLRv1",
  );
}

function fontFamily(mushafId: number, pageNumber: number): string {
  return `memorization-tajweed-${mushafId}-page-${pageNumber}`;
}

export function MemorizationTajweedAyahs({
  ayahs,
  hiddenAyahs,
  onReveal,
}: MemorizationTajweedAyahsProps) {
  const { formatNumber, t } = useI18n();
  const [mushaf, setMushaf] = useState<QuranFoundationMushaf | null>(null);
  const [pages, setPages] = useState<QuranFoundationMushafPage[]>([]);
  const [readyPages, setReadyPages] = useState<Set<number>>(new Set());
  const [state, setState] = useState<LoadState>("loading");
  const pageCache = useRef(new Map<number, QuranFoundationMushafPage>());
  const loadedFonts = useRef(new Map<number, FontFace>());
  const pageNumbers = useMemo(
    () => [...new Set(ayahs.flatMap((ayah) => ayah.pages))].sort((a, b) => a - b),
    [ayahs],
  );

  useEffect(() => {
    let cancelled = false;
    setState("loading");
    api.getQuranFoundationMushafs()
      .then((catalog) => {
        if (cancelled) return;
        const selected = tajweedMushaf(catalog);
        if (!selected) {
          setState("fallback");
          return;
        }
        setMushaf(selected);
      })
      .catch(() => {
        if (!cancelled) setState("fallback");
      });
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (!mushaf || pageNumbers.length === 0) return;
    let cancelled = false;
    setState("loading");
    const loadPages = async () => {
      const loadedPages: QuranFoundationMushafPage[] = [];
      for (let index = 0; index < pageNumbers.length; index += MAX_PARALLEL_PAGE_REQUESTS) {
        const batch = pageNumbers.slice(index, index + MAX_PARALLEL_PAGE_REQUESTS);
        const loadedBatch = await Promise.all(
          batch.map(async (pageNumber) => {
            const cached = pageCache.current.get(pageNumber);
            if (cached) return cached;
            const page = await api.getQuranFoundationMushafPage(mushaf.source_id, pageNumber);
            pageCache.current.set(pageNumber, page);
            return page;
          }),
        );
        loadedPages.push(...loadedBatch);
      }
      return loadedPages;
    };
    void loadPages()
      .then((loadedPages) => {
        if (!cancelled) setPages(loadedPages.sort((a, b) => a.page_number - b.page_number));
      })
      .catch(() => {
        if (!cancelled) setState("fallback");
      });
    return () => {
      cancelled = true;
    };
  }, [mushaf, pageNumbers]);

  useEffect(() => {
    if (!mushaf || pages.length === 0) return;
    let cancelled = false;
    Promise.all(
      pages.map(async (page) => {
        if (loadedFonts.current.has(page.page_number)) return page.page_number;
        const fontUrl = page.rendering.available ? page.rendering.font_url : undefined;
        if (!isAllowedQuranFontUrl(fontUrl)) throw new Error("Invalid Quran font URL");
        const face = new FontFace(
          fontFamily(mushaf.source_id, page.page_number),
          `url("${fontUrl}") format("woff2")`,
        );
        face.display = "block";
        const loaded = await face.load();
        if (cancelled) return page.page_number;
        document.fonts.add(loaded);
        loadedFonts.current.set(page.page_number, loaded);
        return page.page_number;
      }),
    )
      .then((loadedPageNumbers) => {
        if (cancelled) return;
        setReadyPages((current) => new Set([...current, ...loadedPageNumbers]));
        setState("ready");
      })
      .catch(() => {
        if (!cancelled) setState("fallback");
      });
    return () => {
      cancelled = true;
    };
  }, [mushaf, pages]);

  useEffect(() => () => {
    for (const face of loadedFonts.current.values()) document.fonts.delete(face);
    loadedFonts.current.clear();
  }, []);

  const wordsByAyah = useMemo(() => {
    if (!mushaf) return new Map<number, TajweedWord[]>();
    const expected = new Set(ayahs.map((ayah) => `${ayah.surah_number}:${ayah.number}`));
    const result = new Map<number, TajweedWord[]>();
    for (const page of pages) {
      const keys = verseKeyById(page);
      for (const word of [...page.words].sort(
        (left, right) => left.position_in_page - right.position_in_page || left.id - right.id,
      )) {
        const verseKey = word.verse_id === null ? undefined : keys.get(word.verse_id);
        if (!verseKey || !expected.has(verseKey)) continue;
        const ayahNumber = Number(verseKey.split(":")[1]);
        const current = result.get(ayahNumber) || [];
        current.push({
          key: `${page.page_number}-${word.id}`,
          text: word.text,
          fontFamily: fontFamily(mushaf.source_id, page.page_number),
          isAyahEnd: word.char_type_name === "end",
        });
        result.set(ayahNumber, current);
      }
    }
    return result;
  }, [ayahs, mushaf, pages]);

  const allPagesReady = pageNumbers.every((pageNumber) => readyPages.has(pageNumber));
  const useTajweed = state === "ready" && allPagesReady;

  return (
    <div
      className="memorization-ayah-list"
      lang="ar"
      dir="rtl"
      data-testid="memorization-tajweed"
      data-tajweed-status={useTajweed ? "ready" : state}
    >
      {!useTajweed && (
        <p className="field-help memorization-tajweed-status" lang={undefined} dir="auto">
          {state === "loading" ? t("memorization.tajweedLoading") : t("memorization.tajweedFallback")}
        </p>
      )}
      {ayahs.map((ayah) => {
        const hidden = hiddenAyahs.has(ayah.number);
        const tajweedWords = wordsByAyah.get(ayah.number) || [];
        return (
          <article key={ayah.id} className="memorization-ayah-card">
            <span className="memorization-ayah-number">{formatNumber(ayah.number)}</span>
            {hidden ? (
              <button
                type="button"
                className="memorization-reveal"
                onClick={() => onReveal(ayah.number)}
              >
                {t("memorization.revealAyah", { ayah: formatNumber(ayah.number) })}
              </button>
            ) : useTajweed && tajweedWords.length > 0 ? (
              <p
                className="memorization-arabic memorization-tajweed-text"
                aria-label={ayah.text_uthmani}
                translate="no"
              >
                {tajweedWords.map((word) => (
                  <span
                    className={`memorization-tajweed-word${word.isAyahEnd ? " is-ayah-end" : ""}`}
                    style={{ fontFamily: `"${word.fontFamily}", serif` }}
                    aria-hidden="true"
                    key={word.key}
                  >
                    {word.text}
                  </span>
                ))}
              </p>
            ) : (
              <p className="memorization-arabic">{ayah.text_uthmani}</p>
            )}
          </article>
        );
      })}
    </div>
  );
}
