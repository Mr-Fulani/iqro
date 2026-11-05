"use client";

import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { useI18n } from "../lib/i18n-context";
import { ayahTextParts, sameWord, wordKey, wordRangeContains, type QuranWord, type QuranWordRange } from "../lib/word-range";
import { ReaderSwipeReveal, useReaderSwipe } from "./ReaderSwipe";
import { WordRangeHandles } from "./WordSelection";

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
 * as in the text: the page passes its words area in `wordArea`.
 */
export function QuranPlainText({
  surah,
  surahName,
  ayahs,
  startAyah,
  range,
  playingWord,
  wordArea,
  onLeave,
}: {
  surah: number;
  surahName?: string;
  ayahs: PlainAyah[];
  startAyah: number;
  range: QuranWordRange | null;
  playingWord: QuranWord | null;
  wordArea: (element: HTMLElement | null) => void;
  onLeave: (ayah: number) => void;
}) {
  const { t } = useI18n();
  const [size, setSize] = useState(DEFAULT_SIZE);
  const [ayah, setAyah] = useState(startAyah);
  const [marked, setMarked] = useState<number | null>(startAyah);
  const [sizeOpen, setSizeOpen] = useState(false);
  const [leaving, setLeaving] = useState(false);
  const [scroller, setScroller] = useState<HTMLDivElement | null>(null);
  const [root, setRoot] = useState<HTMLDivElement | null>(null);
  const placing = useRef(true);
  const current = useRef(startAyah);

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
    const keep = new ResizeObserver(() => placeAt(current.current));
    keep.observe(body);
    void document.fonts?.ready.then(() => placeAt(current.current));
    return () => keep.disconnect();
  }, [placeAt, scroller]);

  // The ayah the first line starts with, or the next one if it begins on
  // that line too: the line at the bottom shows it, the way back returns it.
  useEffect(() => {
    if (!scroller) return;
    const update = () => {
      if (placing.current) return;
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

  const first = ayahs[0];
  const opening = first ? ayahTextParts(surah, first.number, first.text_uthmani).find((part) => !part.words)?.text : undefined;
  const page = ayahs.find((item) => item.number === ayah)?.pages[0];

  return (
    <div
      ref={setRoot}
      className={`plain-text-reader${leaving ? " is-leaving" : ""}`}
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
            {ayahs.map((item) => (
              <p className="plain-text-ayah quran-arabic-text" dir="rtl" key={item.id} data-ayah={item.number}>
                {ayahTextParts(surah, item.number, item.text_uthmani)
                  .flatMap((part) => part.words ?? [])
                  .map((text, index) => {
                    const at = { surah, ayah: item.number, position: index + 1 };
                    const selected = wordRangeContains(range, at);
                    return (
                      <span key={index}>
                        {index > 0 && " "}
                        <span
                          className={`quran-word${selected ? " is-word-selected" : ""}${selected && sameWord(at, playingWord) ? " is-word-playing" : ""}${marked === item.number ? " is-word-marked" : ""}`}
                          data-word-key={wordKey(at)}
                        >
                          <WordRangeHandles range={range} word={at} />
                          {text}
                        </span>
                      </span>
                    );
                  })}
                {"\u00A0"}
                <span className="ayah-end-marker" aria-hidden="true">
                  {`\uFD3F${arabicNumber.format(item.number)}\uFD3E`}
                </span>
              </p>
            ))}
          </div>
        </div>
        <p className="plain-text-place" data-testid="plain-text-place">
          {page ? t("quran.plainTextPlace", { ayah: arabicNumber.format(ayah), page: arabicNumber.format(page) }) : null}
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
