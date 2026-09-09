"use client";

import { useEffect, useMemo, useState } from "react";
import { api, type MushafPage, type QuranFoundationMushaf, type QuranFoundationMushafPage } from "../lib/api";
import { MushafPageCache } from "../lib/mushaf-page-cache";
import { loadQuranFont, quranFontFamily } from "../lib/quran-font";

type ReaderPage = { image: MushafPage; foundation?: never } | { foundation: QuranFoundationMushafPage; image?: never };

export function useMushafPages(edition: string, mushaf: QuranFoundationMushaf | null, page: number, enabled: boolean) {
  const cache = useMemo(() => new MushafPageCache<ReaderPage>(
    async (pageNumber) => mushaf
      ? { foundation: await api.getQuranFoundationMushafPage(mushaf.source_id, pageNumber) }
      : { image: await api.getPage(edition, pageNumber) },
    async (data) => {
      if (data.foundation && mushaf) {
        const rendering = data.foundation.rendering;
        if (rendering.available) {
          await loadQuranFont(quranFontFamily(mushaf.source_id, data.foundation), rendering.font_url).catch(() => {});
        }
      } else if (data.image?.assets[0]) {
        const image = new Image();
        image.src = data.image.assets[0].url;
        // Keep decoded pixels alongside JSON for immediate image rendering.
        await image.decode().catch(() => {});
        preparedImages.set(data.image, image);
      }
    },
    mushaf?.pages_count || 604,
  ), [edition, mushaf]);
  const [settled, setSettled] = useState<{ cache: typeof cache; page: number; data?: ReaderPage; error?: unknown } | null>(null);
  const active = enabled && Boolean(edition);
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
    imagePage: data?.image ?? null,
    foundationPage: data?.foundation ?? null,
    loading: active && !data && !result?.error,
    error: result?.error,
  };
}

// Weak keys let the bounded page cache release decoded images as pages leave it.
const preparedImages = new WeakMap<MushafPage, HTMLImageElement>();
