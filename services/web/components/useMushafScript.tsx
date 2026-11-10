"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import { api, type QuranFoundationMushaf, type QuranFoundationMushafPage } from "../lib/api";
import { mushafAyahScript, type MushafAyahScript, type MushafScriptWord } from "../lib/mushaf-script";
import { loadQuranFont, quranFontFamily, retainQuranFont } from "../lib/quran-font";

/**
 * The ayahs of a text reader in the script of the selected Mushaf: its page
 * fonts and words, colours of tajweed included. Pages load as their ayahs
 * (elements with `data-script-ayah` inside `container`) come near the screen;
 * until then, and for a Mushaf of word images, the returned function gives
 * null and the reader draws its plain text.
 */
export function useMushafScript(
  mushaf: QuranFoundationMushaf | null,
  versePages: Record<string, number[]> | null,
  surah: number,
  ayahCount: number,
  container: HTMLElement | null,
  root: HTMLElement | null = null,
): (ayah: number, wordCount: number) => MushafAyahScript | null {
  const source = mushaf?.rendering.available && mushaf.rendering.mode !== "word-images" ? mushaf : null;
  // One loading session: its fonts are held until it ends.
  const session = useMemo(() => ({ source, versePages, surah, ayahCount, container, root }),
    [source, versePages, surah, ayahCount, container, root]);
  const [loaded, setLoaded] = useState<{ session: object; pages: Map<number, QuranFoundationMushafPage> } | null>(null);

  useEffect(() => {
    if (!source || !versePages || !container || typeof IntersectionObserver === "undefined") return;
    let cancelled = false;
    const requested = new Set<number>();
    const releases: (() => void)[] = [];
    const load = async (number: number) => {
      if (requested.has(number)) return;
      requested.add(number);
      try {
        const page = await api.getQuranFoundationMushafPage(source.source_id, number);
        if (cancelled || page.source_checksum_sha256 !== source.source_checksum_sha256
          || !page.rendering.available || page.rendering.mode === "word-images") return;
        const family = quranFontFamily(source.source_id, page);
        await loadQuranFont(family, page.rendering.font_url);
        if (cancelled) return;
        releases.push(retainQuranFont(family, page.rendering.font_url));
        setLoaded((previous) => ({
          session,
          pages: new Map(previous?.session === session ? previous.pages : []).set(number, page),
        }));
      } catch {
        // Offline or a failed font: the plain text stays; tried again when the ayah next comes near.
        requested.delete(number);
      }
    };
    const observer = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        const ayah = (entry.target as HTMLElement).dataset.scriptAyah;
        for (const page of versePages[`${surah}:${ayah}`] ?? []) void load(page);
      }
    }, { root, rootMargin: "600px 0px" });
    container.querySelectorAll("[data-script-ayah]").forEach((element) => observer.observe(element));
    return () => {
      cancelled = true;
      observer.disconnect();
      releases.forEach((release) => release());
    };
  }, [session, source, versePages, surah, container, root]);

  const pages = loaded?.session === session ? loaded.pages : null;
  return useCallback((ayah: number, wordCount: number) => {
    if (!source || !versePages || !pages) return null;
    const key = `${surah}:${ayah}`;
    return mushafAyahScript(source.source_id, versePages[key], pages, key, wordCount);
  }, [pages, source, surah, versePages]);
}

/** A word of the Mushaf's script: its glyphs, in the source's colour runs where it has them. */
export function mushafScriptWordContent(word: MushafScriptWord) {
  return word.runs
    ? word.runs.map((run, index) => <span key={index} style={run.color ? { color: run.color } : undefined}>{run.text}</span>)
    : word.text;
}

export function mushafScriptWordStyle(word: MushafScriptWord) {
  return {
    fontFamily: `"${word.fontFamily}", serif`,
    unicodeBidi: word.bidiOverride ? "bidi-override" as const : undefined,
  };
}
