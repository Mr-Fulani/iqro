"use client";

import { Fragment, useEffect, useMemo, useState } from "react";

import { api, type QuranFoundationMushaf, type QuranFoundationMushafPage } from "../lib/api";
import { mushafAyahScript, readMushafVariantPreference, selectedMushaf, type MushafAyahScript, type MushafScriptWord } from "../lib/mushaf-script";
import { loadQuranFont, quranFontFamily, retainQuranFont } from "../lib/quran-font";
import type { SalahQuranAyah } from "../lib/salah";
import { quranWords } from "../lib/word-range";
import { SalahQuranText } from "./SalahQuranText";
import { mushafScriptWordContent, mushafScriptWordStyle } from "./useMushafScript";

// Loaded once for the visit: the steps of a lesson repeat the same surahs.
// A failed request is forgotten, so the next step tries again.
let mushafs: Promise<QuranFoundationMushaf[]> | null = null;
const indexes = new Map<number, Promise<Record<string, number[]>>>();
const pages = new Map<string, Promise<QuranFoundationMushafPage>>();

function once<K, V>(cache: Map<K, Promise<V>>, key: K, load: () => Promise<V>): Promise<V> {
  let promise = cache.get(key);
  if (!promise) {
    promise = load();
    cache.set(key, promise);
    promise.catch(() => cache.delete(key));
  }
  return promise;
}

/** A page of the Mushaf with its font ready and kept for the visit. */
async function loadPage(mushaf: QuranFoundationMushaf, number: number): Promise<QuranFoundationMushafPage> {
  const page = await api.getQuranFoundationMushafPage(mushaf.source_id, number);
  if (page.source_checksum_sha256 !== mushaf.source_checksum_sha256
    || !page.rendering.available || page.rendering.mode === "word-images") throw new Error("No script for the page");
  const family = quranFontFamily(mushaf.source_id, page);
  await loadQuranFont(family, page.rendering.font_url);
  retainQuranFont(family, page.rendering.font_url);
  return page;
}

/** The ayahs in the script of the Mushaf selected in the Quran reader; null for a Mushaf of pictures. */
async function loadScripts(surah: number, ayahs: SalahQuranAyah[]): Promise<(MushafAyahScript | null)[] | null> {
  mushafs ??= api.getQuranFoundationMushafs();
  mushafs.catch(() => { mushafs = null; });
  const mushaf = selectedMushaf(await mushafs, readMushafVariantPreference());
  if (!mushaf || mushaf.rendering.mode === "word-images") return null;
  const versePages = await once(indexes, mushaf.source_id,
    async () => (await api.getQuranFoundationMushafIndex(mushaf.source_id)).verse_pages);
  const loaded = new Map<number, QuranFoundationMushafPage>();
  await Promise.all([...new Set(ayahs.flatMap((ayah) => versePages[`${surah}:${ayah.number}`] ?? []))].map(async (number) => {
    try {
      loaded.set(number, await once(pages, `${mushaf.source_id}:${number}`, () => loadPage(mushaf, number)));
    } catch {
      // Offline or a failed font: the ayahs of this page keep the plain text.
    }
  }));
  return ayahs.map((ayah) => {
    const key = `${surah}:${ayah.number}`;
    return mushafAyahScript(mushaf.source_id, versePages[key], loaded, key, quranWords(ayah.text).length);
  });
}

function glyph(word: MushafScriptWord) {
  return <span style={mushafScriptWordStyle(word)}>{mushafScriptWordContent(word)}</span>;
}

/**
 * A formula of the Quran in the script of the selected Mushaf. Its pages and
 * fonts are asked for when the step is the open one or the next (`near`), so
 * the text is usually ready before the visitor comes to it.
 */
export default function SalahQuranScript({ surah, ayahs, near }: { surah: number; ayahs: SalahQuranAyah[]; near: boolean }) {
  const [loaded, setLoaded] = useState<{ ayahs: SalahQuranAyah[]; scripts: (MushafAyahScript | null)[] | null } | null>(null);
  useEffect(() => {
    if (!near) return;
    let live = true;
    void loadScripts(surah, ayahs).then((scripts) => { if (live) setLoaded({ ayahs, scripts }); }, () => undefined);
    return () => { live = false; };
  }, [near, surah, ayahs]);
  const scripts = loaded?.ayahs === ayahs ? loaded.scripts : null;
  const glyphs = useMemo(() => scripts?.map((script) => script && {
    words: script.words.map((word, index) => <Fragment key={word.key}>{index > 0 && " "}{glyph(word)}</Fragment>),
    end: script.end ? glyph(script.end) : null,
  }), [scripts]);
  return <SalahQuranText ayahs={ayahs} glyphs={glyphs} />;
}
