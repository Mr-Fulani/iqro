"use client";

import { Fragment, useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import type { QuranFoundationMushaf, Surah } from "../lib/api";
import { useI18n } from "../lib/i18n-context";
import { kashidaLayout, type KashidaLayout } from "../lib/kashida";
import { mushafPageEnds, readerDigits } from "../lib/mushaf-script";
import { ayahTextParts, sameWord, wordKey, wordRangeContains, type QuranWord, type QuranWordRange } from "../lib/word-range";
import { ReaderSwipeReveal, useReaderSwipe } from "./ReaderSwipe";
import { WordRangeHandles } from "./WordSelection";
import { mushafScriptWordContent, mushafScriptWordStyle, useMushafScript } from "./useMushafScript";
import { LAST_SURAH, NextSurahCard, QuranEnd, usePullToNext } from "./NextSurah";

export const PLAIN_TEXT_SIZE_KEY = "iqro_plain_text_size";
const DEFAULT_SIZE = 40;
const MIN_SIZE = 24;
const MAX_SIZE = 72;

const arabicNumber = new Intl.NumberFormat("ar-EG");

type PlainAyah = { id: number | string; number: number; text_uthmani: string; pages: number[] };

function readSize() {
  try {
    const saved = Number(window.localStorage.getItem(PLAIN_TEXT_SIZE_KEY));
    return saved >= MIN_SIZE && saved <= MAX_SIZE ? saved : DEFAULT_SIZE;
  } catch {
    return DEFAULT_SIZE;
  }
}

/**
 * The surah as plain Arabic text, running on as on a Mushaf page, in a size
 * the reader picks: for those who find the Mushaf too small and the cards,
 * translation and buttons in the way. It turns in over the text from the
 * ayah a swipe to the right started on; a swipe back to the left turns it
 * away and hands back the ayah at the top of the screen. Word selection works
 * as in the text: the page passes its words area in `wordArea`. Lines reach
 * both edges by drawn-out joins (lib/kashida.ts). At the end of the surah the
 * next one opens, rising in (`entering`).
 */
export function QuranPlainText({
  surah,
  surahName,
  ayahs,
  startAyah,
  range,
  playingWord,
  wordArea,
  mushaf,
  versePages,
  onLeave,
  onSettle,
  markedAyah = null,
  thisSurah,
  nextSurah,
  listHref,
  onNextSurah,
  entering = false,
}: {
  surah: number;
  surahName?: string;
  ayahs: PlainAyah[];
  startAyah: number;
  range: QuranWordRange | null;
  playingWord: QuranWord | null;
  wordArea: (element: HTMLElement | null) => void;
  /** The selected Mushaf and its pages of each ayah: the text is written as it writes it. */
  mushaf: QuranFoundationMushaf | null;
  versePages: Record<string, number[]> | null;
  onLeave: (ayah: number) => void;
  /** After a scroll of the reader's own: the ayahs that begin on screen. */
  onSettle?: (verseKeys: string[]) => void;
  /** An ayah to tint for as long as it is given. */
  markedAyah?: number | null;
  thisSurah?: Surah;
  nextSurah?: Surah;
  listHref: string;
  onNextSurah: () => void;
  entering?: boolean;
}) {
  const { locale, t } = useI18n();
  const [size, setSize] = useState(DEFAULT_SIZE);
  const [ayah, setAyah] = useState(startAyah);
  const [marked, setMarked] = useState<number | null>(startAyah);
  const [sizeOpen, setSizeOpen] = useState(false);
  const [leaving, setLeaving] = useState(false);
  const [scroller, setScroller] = useState<HTMLDivElement | null>(null);
  const [root, setRoot] = useState<HTMLDivElement | null>(null);
  const [lineWidth, setLineWidth] = useState(0);
  const [fontsReady, setFontsReady] = useState(false);
  const placing = useRef(true);
  const current = useRef(startAyah);
  const scrolled = useRef(false);
  const ayahScript = useMushafScript(mushaf, versePages, surah, ayahs.length, scroller, scroller);
  const pageOf = (item: PlainAyah) => versePages?.[`${surah}:${item.number}`]?.[0] ?? item.pages[0];
  const pageEnds = mushafPageEnds(ayahs.map(pageOf));

  useEffect(() => { setSize(readSize()); }, []);
  useEffect(() => {
    const timer = window.setTimeout(() => setMarked(null), 1500);
    return () => window.clearTimeout(timer);
  }, []);
  useEffect(() => {
    const overflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    return () => { document.body.style.overflow = overflow; };
  }, []);

  const word = useCallback(
    (key: string) => scroller?.querySelector<HTMLElement>(`[data-word-key="${key}"]`) ?? null,
    [scroller],
  );

  /** Brings the ayah's first word to the top of the screen. Measured inside
   * the text, not on screen: the sheet is still turning in at first. */
  const placeAt = useCallback((target: number) => {
    if (!scroller) return;
    placing.current = true;
    const first = target <= 1 ? null : word(`${surah}:${target}:1`);
    scroller.scrollTop = first ? first.offsetTop - 8 : 0;
    window.requestAnimationFrame(() => { placing.current = false; });
  }, [scroller, surah, word]);

  // Opened at the ayah, and kept there while the text reflows to a new size
  // or a turned screen.
  useLayoutEffect(() => { placeAt(current.current); }, [placeAt, size]);
  useEffect(() => {
    const body = scroller?.firstElementChild;
    if (!body) return;
    // The text reflows when the Arabic font arrives, the size changes or the
    // screen turns: the ayah at the top stays there.
    let width = body.clientWidth;
    const keep = new ResizeObserver(() => {
      setLineWidth(body.clientWidth);
      // Once the reader scrolls, the Mushaf's pages load ahead of the screen:
      // only a turned screen moves the text under them then.
      if (scrolled.current && body.clientWidth === width) return;
      width = body.clientWidth;
      placeAt(current.current);
    });
    keep.observe(body);
    void document.fonts?.ready.then(() => {
      setFontsReady(true);
      placeAt(current.current);
    });
    return () => keep.disconnect();
  }, [placeAt, scroller]);

  // The ayah the first line starts with, or the next one if it begins on
  // that line too: the line at the bottom shows it, the way back returns it.
  useEffect(() => {
    if (!scroller) return;
    const update = () => {
      if (placing.current) return;
      scrolled.current = true;
      const words = [...scroller.querySelectorAll<HTMLElement>("[data-word-key]")];
      const top = scroller.scrollTop + 4;
      let low = 0;
      let high = words.length - 1;
      while (low < high) {
        const middle = (low + high) >> 1;
        if (words[middle].offsetTop + words[middle].offsetHeight > top) high = middle;
        else low = middle + 1;
      }
      const first = words[low];
      if (!first) return;
      const [, ayahText, position] = (first.dataset.wordKey ?? "").split(":");
      let next = Number(ayahText);
      const following = word(`${surah}:${next + 1}:1`);
      if (Number(position) > 1 && following
        && following.offsetTop < first.offsetTop + first.offsetHeight - 1) {
        next += 1;
      }
      current.current = next;
      setAyah(next);
    };
    scroller.addEventListener("scroll", update, { passive: true });
    return () => scroller.removeEventListener("scroll", update);
  }, [scroller, surah, word]);

  // Once a scroll of the reader's own stops: the ayahs whose first word is
  // on screen. Placing the text at its ayah is not such a scroll.
  useEffect(() => {
    if (!scroller || !onSettle) return;
    let timer: number | undefined;
    const settle = () => {
      if (placing.current) return;
      window.clearTimeout(timer);
      timer = window.setTimeout(() => {
        const area = scroller.getBoundingClientRect();
        onSettle([...scroller.querySelectorAll<HTMLElement>('[data-word-key$=":1"]')]
          .filter((first) => {
            const rect = first.getBoundingClientRect();
            return rect.bottom > area.top && rect.top < area.bottom;
          })
          .map((first) => (first.dataset.wordKey ?? "").split(":").slice(0, 2).join(":")));
      }, 350);
    };
    scroller.addEventListener("scroll", settle, { passive: true });
    return () => {
      window.clearTimeout(timer);
      scroller.removeEventListener("scroll", settle);
    };
  }, [onSettle, scroller]);

  const leave = useCallback(() => {
    if (leaving) return;
    setLeaving(true);
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    window.setTimeout(() => {
      onLeave(current.current);
      // The history entry the open text added goes with it.
      if (window.history.state?.plainText) window.history.back();
    }, reduced ? 0 : 380);
  }, [leaving, onLeave]);

  // The whole layer: a swipe back while the sheet still turns in counts too.
  const swipe = useReaderSwipe(root, {
    enabled: !range && !leaving,
    right: false,
    left: true,
    onSwipe: (direction) => { if (direction === "left") leave(); },
  });

  // The back button of the phone, or Escape, leaves as the swipe does. The
  // entry keeps the page's own history state, so the router stays put.
  useEffect(() => {
    if (!window.history.state?.plainText) {
      window.history.pushState({ ...window.history.state, plainText: true }, "");
    }
    const back = () => {
      if (!window.history.state?.plainText) onLeave(current.current);
    };
    window.addEventListener("popstate", back);
    return () => window.removeEventListener("popstate", back);
  }, [onLeave]);
  useEffect(() => {
    const key = (event: KeyboardEvent) => { if (event.key === "Escape" && !range) leave(); };
    window.addEventListener("keydown", key);
    return () => window.removeEventListener("keydown", key);
  }, [leave, range]);

  const changeSize = (value: number) => {
    setSize(value);
    try {
      window.localStorage.setItem(PLAIN_TEXT_SIZE_KEY, String(value));
    } catch {
      // A private window keeps the size for this visit only.
    }
  };

  const pull = usePullToNext(scroller, {
    enabled: !range && !leaving && surah < LAST_SURAH,
    onNext: onNextSurah,
  });

  // Each ayah's lines, drawn out to both edges in the page's own font.
  const layouts = useMemo(() => {
    const body = scroller?.firstElementChild;
    const out = new Map<number, KashidaLayout>();
    if (!body || !lineWidth || !fontsReady) return out;
    const context = document.createElement("canvas").getContext("2d");
    if (!context) return out;
    context.font = `${size}px ${getComputedStyle(body).fontFamily}`;
    context.direction = "rtl";
    const widths = new Map<string, number>();
    const measure = (text: string) => {
      let width = widths.get(text);
      if (width === undefined) widths.set(text, width = context.measureText(text).width);
      return width;
    };
    for (const item of ayahs) {
      const words = ayahTextParts(surah, item.number, item.text_uthmani).flatMap((part) => part.words ?? []);
      out.set(item.number, kashidaLayout(words, lineWidth, measure, {
        marker: `\u00A0\uFD3F${arabicNumber.format(item.number)}\uFD3E`,
        fontSize: size,
      }));
    }
    return out;
  }, [ayahs, fontsReady, lineWidth, scroller, size, surah]);

  const first = ayahs[0];
  const opening = first ? ayahTextParts(surah, first.number, first.text_uthmani).find((part) => !part.words)?.text : undefined;
  const currentAyah = ayahs.find((item) => item.number === ayah);
  const page = currentAyah && pageOf(currentAyah);

  return (
    <div
      ref={setRoot}
      className={`plain-text-reader${leaving ? " is-leaving" : ""}${entering ? " is-next" : ""}`}
      role="dialog"
      aria-modal="true"
      aria-label={t("quran.plainText")}
      data-testid="plain-text-reader"
    >
      <ReaderSwipeReveal
        offset={swipe}
        left={{ icon: <TextIcon />, label: t("quran.plainTextBack") }}
      />
      <div className="plain-text-sheet" style={{ transform: swipe ? `translateX(${swipe}px)` : undefined }}>
        <div className="plain-text-top">
          <button
            type="button"
            className="plain-text-size-button"
            aria-label={t("quran.plainTextSize")}
            title={t("quran.plainTextSize")}
            aria-expanded={sizeOpen}
            onClick={() => setSizeOpen((open) => !open)}
            data-testid="plain-text-size"
          >
            <TuneIcon />
          </button>
        </div>
        <div className="plain-text-scroll" ref={setScroller}>
          <div className="plain-text-body" ref={wordArea} style={{ fontSize: size }}>
            {surahName && <p className="plain-text-surah" dir="rtl">{`سُورَةُ ${surahName}`}</p>}
            {opening && <p className="plain-text-opening" dir="rtl">{opening}</p>}
            {/* Each ayah a paragraph of its own, a blank line between them. */}
            {ayahs.map((item, itemIndex) => {
              const words = ayahTextParts(surah, item.number, item.text_uthmani).flatMap((part) => part.words ?? []);
              const script = ayahScript(item.number, words.length);
              // Glyphs of a Mushaf font are not letters to draw out.
              const layout = script ? undefined : layouts.get(item.number);
              const pageEnd = pageEnds[itemIndex];
              return (
              <Fragment key={item.id}>
              {pageEnd !== null && (
                <div className="reader-page-end is-paper" data-testid="plain-text-page-end">
                  <span>{t("common.page", { page: readerDigits(locale, pageEnd) })}</span>
                </div>
              )}
              <p className="plain-text-ayah quran-arabic-text" dir="rtl" data-ayah={item.number} data-script-ayah={item.number}>
                {words.map((original, index) => {
                    const at = { surah, ayah: item.number, position: index + 1 };
                    const selected = wordRangeContains(range, at);
                    const glyph = script?.words[index];
                    const text = layout?.words[index] ?? original;
                    return (
                      <span key={index}>
                        {index > 0 && (layout?.breaks.has(index - 1) ? <br /> : " ")}
                        <span
                          className={`quran-word${selected ? " is-word-selected" : ""}${selected && sameWord(at, playingWord) ? " is-word-playing" : ""}${marked === item.number || markedAyah === item.number ? " is-word-marked" : ""}`}
                          data-word-key={wordKey(at)}
                          style={glyph && mushafScriptWordStyle(glyph)}
                        >
                          <WordRangeHandles range={range} word={at} />
                          {glyph ? mushafScriptWordContent(glyph) : text}
                        </span>
                      </span>
                    );
                  })}
                {"\u00A0"}
                <span className="ayah-end-marker" aria-hidden="true" style={script?.end ? mushafScriptWordStyle(script.end) : undefined}>
                  {script?.end ? mushafScriptWordContent(script.end) : `\uFD3F${arabicNumber.format(item.number)}\uFD3E`}
                </span>
              </p>
              </Fragment>
              );
            })}
            {ayahs.length > 0 && (
              <div className="plain-text-end">
                {surah >= LAST_SURAH ? (
                  <QuranEnd surah={thisSurah} paper listHref={listHref} />
                ) : (
                  <NextSurahCard
                    number={surah + 1}
                    surah={nextSurah}
                    progress={pull}
                    onOpen={onNextSurah}
                    paper
                    disabled={Boolean(range)}
                  />
                )}
              </div>
            )}
          </div>
        </div>
        <p className="plain-text-place" data-testid="plain-text-place">
          {page ? t("quran.plainTextPlace", { ayah: readerDigits(locale, ayah), page: readerDigits(locale, page) }) : null}
        </p>
      </div>
      {sizeOpen && (
        <>
          <button type="button" className="plain-text-size-backdrop" aria-label={t("common.close")} onClick={() => setSizeOpen(false)} />
          <div className="plain-text-size-panel">
            <label className="plain-text-size-label" htmlFor="plain-text-size-range">
              <span>{t("quran.plainTextSize")}</span>
              <span>{size}</span>
            </label>
            <input
              id="plain-text-size-range"
              type="range"
              min={MIN_SIZE}
              max={MAX_SIZE}
              step={2}
              value={size}
              onChange={(event) => changeSize(Number(event.target.value))}
            />
            <button type="button" className="btn btn-sm btn-secondary" onClick={() => changeSize(DEFAULT_SIZE)}>
              {t("quran.plainTextReset")}
            </button>
          </div>
        </>
      )}
    </div>
  );
}

function TuneIcon() {
  return (
    <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
      <path d="M4 7h10M18 7h2M4 17h4M12 17h8" />
      <circle cx="16" cy="7" r="2" />
      <circle cx="10" cy="17" r="2" />
    </svg>
  );
}

export function TextIcon() {
  return (
    <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
      <path d="M4 6h16M4 12h16M4 18h10" />
    </svg>
  );
}
