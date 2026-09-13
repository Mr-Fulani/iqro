"use client";

import { useEffect, useMemo, useState } from "react";
import { api, type QuranFoundationMushaf, type QuranFoundationMushafPage } from "../lib/api";
import { MushafPageCache } from "../lib/mushaf-page-cache";
import { loadQuranFont, quranFontFamily } from "../lib/quran-font";

type ReaderPage = QuranFoundationMushafPage;

export function useMushafPages(mushaf: QuranFoundationMushaf | null, page: number, enabled: boolean) {
  const sourceId = mushaf?.source_id ?? null;
  const pageCount = mushaf?.pages_count ?? 604;
  const sourceRevision = mushaf
    ? mushaf.source_checksum_sha256
    : null;
  const cache = useMemo(() => new MushafPageCache<ReaderPage>(
    async (pageNumber) => {
      if (sourceId === null || sourceRevision === null) throw new Error("No published Mushaf selected");
      const data = await api.getQuranFoundationMushafPage(sourceId, pageNumber);
      if (data.mushaf_id !== sourceId || data.page_number !== pageNumber ||
          data.source_checksum_sha256 !== sourceRevision) {
        throw new Error("Mushaf source version changed. Reload the catalog.");
      }
      return data;
    },
    async (data) => {
      if (sourceId !== null && data.rendering.available && data.rendering.mode !== "word-images") {
        await loadQuranFont(quranFontFamily(sourceId, data), data.rendering.font_url);
      }
    },
    pageCount,
  ), [sourceId, sourceRevision, pageCount]);
  const [settled, setSettled] = useState<{ cache: typeof cache; page: number; data?: ReaderPage; error?: unknown } | null>(null);
  const active = enabled && mushaf !== null;
  const result = settled?.cache === cache && settled.page === page ? settled : null;
  // A warm page is available in the very render that changes the page number.
  const data = active ? cache.peek(page) ?? result?.data : undefined;

  useEffect(() => {
    if (!active) { cache.stopPrefetch(); return; }
    let cancelled = false;
    cache.focus(page);
    void cache.load(page).then((loaded) => {
      if (cancelled) return;
      setSettled({ cache, page, data: loaded });
      cache.prefetch();
    }).catch((error: unknown) => {
      if (!cancelled) setSettled({ cache, page, error });
    });
    return () => { cancelled = true; cache.stopPrefetch(); };
  }, [active, cache, page]);

  return {
    foundationPage: data ?? null,
    loading: active && !data && !result?.error,
    error: result?.error,
  };
}
