"use client";

import { useEffect, useRef, useState } from "react";
import type { Surah } from "../lib/api";
import { useI18n } from "../lib/i18n-context";

/** How far past the end of a surah a finger pulls to open the next one. */
export const NEXT_SURAH_PULL = 120;
export const LAST_SURAH = 114;

const arabicNumber = new Intl.NumberFormat("ar-EG");

function atEnd(scroller: HTMLElement | null) {
  if (!scroller) {
    const root = document.scrollingElement ?? document.documentElement;
    return root.scrollTop + window.innerHeight >= root.scrollHeight - 2;
  }
  return scroller.scrollTop + scroller.clientHeight >= scroller.scrollHeight - 2;
}

/**
 * A finger pulling on past the end of a surah, on a touch screen: the
 * progress fills as it pulls, and letting go with it full opens the next
 * surah. `scroller` is the element that scrolls, or null for the page.
 * Nothing while `enabled` is false: selected words keep the end where it is.
 */
export function usePullToNext(
  scroller: HTMLElement | null,
  { enabled, onNext }: { enabled: boolean; onNext: () => void },
) {
  const [progress, setProgress] = useState(0);
  const latest = useRef({ enabled, onNext });
  useEffect(() => { latest.current = { enabled, onNext }; });

  useEffect(() => {
    const target: HTMLElement | Window = scroller ?? window;
    let base: number | null = null;
    let value = 0;
    const set = (next: number) => {
      if (next >= 1 && value < 1) navigator.vibrate?.(10);
      value = next;
      setProgress(next);
    };
    const move = (event: Event) => {
      const touch = (event as TouchEvent).touches[0];
      if (!touch || !latest.current.enabled || document.documentElement.dataset.wordSelecting === "true") {
        base = null;
        if (value) set(0);
        return;
      }
      if (!atEnd(scroller)) {
        base = null;
        if (value) set(0);
        return;
      }
      base ??= touch.clientY;
      set(Math.max(0, Math.min(1, (base - touch.clientY) / NEXT_SURAH_PULL)));
    };
    const end = () => {
      const full = value >= 1;
      base = null;
      if (value) set(0);
      if (full && latest.current.enabled) latest.current.onNext();
    };
    target.addEventListener("touchmove", move, { passive: true });
    target.addEventListener("touchend", end, { passive: true });
    target.addEventListener("touchcancel", end, { passive: true });
    return () => {
      target.removeEventListener("touchmove", move);
      target.removeEventListener("touchend", end);
      target.removeEventListener("touchcancel", end);
    };
  }, [scroller]);

  return progress;
}

/** The card after the last ayah: the next surah, opened by a tap or a pull. */
export function NextSurahCard({
  number,
  surah,
  progress,
  onOpen,
  paper = false,
  disabled = false,
}: {
  number: number;
  surah?: Surah;
  progress: number;
  onOpen: () => void;
  paper?: boolean;
  disabled?: boolean;
}) {
  const { t, locale } = useI18n();
  const ready = progress >= 1;
  const name = surah ? (locale === "ru" ? surah.name_ru : locale === "ar" ? surah.name_ar : surah.name_en) : "";
  const circumference = 2 * Math.PI * 22;
  return (
    <button
      type="button"
      className={`next-surah-card${paper ? " is-paper" : ""}${ready ? " is-ready" : ""}`}
      onClick={onOpen}
      disabled={disabled}
      data-testid="next-surah-card"
    >
      <span className="next-surah-kicker">
        {paper ? `${t("quran.nextSurah")} · ${arabicNumber.format(number)}` : t("quran.nextSurah")}
      </span>
      {!paper && <span className="next-surah-name">{number}. {name}</span>}
      {surah && <span className="next-surah-arabic" dir="rtl">{`سُورَةُ ${surah.name_ar}`}</span>}
      {surah && (
        <span className="next-surah-meta">
          {paper ? `${name} · ` : ""}
          {t("quran.nextSurahAyahs", { count: surah.ayah_count })}
          {paper ? "" : ` · ${surah.revelation_type === "meccan" ? t("home.meccan") : t("home.medinan")}`}
        </span>
      )}
      {/* A tap is enough on a computer: the pull is for a finger. */}
      <span className="next-surah-ring" aria-hidden="true">
        <svg width="52" height="52" viewBox="0 0 52 52">
          <circle cx="26" cy="26" r="22" fill="none" strokeWidth="3.5" className="track" />
          <circle
            cx="26"
            cy="26"
            r="22"
            fill="none"
            strokeWidth="3.5"
            strokeLinecap="round"
            className="fill"
            strokeDasharray={circumference}
            strokeDashoffset={circumference * (1 - progress)}
            transform="rotate(-90 26 26)"
          />
          {ready
            ? <path d="M18 26l6 6 11-12" fill="none" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round" className="arrow" />
            : <path d="M26 35V17M20 23l6-6 6 6" fill="none" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round" className="arrow" />}
        </svg>
      </span>
      <span className="next-surah-hint">
        {ready ? t("quran.nextSurahRelease", { number }) : t("quran.nextSurahHint")}
      </span>
    </button>
  );
}

/** After an-Nas: no next surah, and plainly so. */
export function QuranEnd({ surah, paper = false, listHref }: { surah?: Surah; paper?: boolean; listHref: string }) {
  const { t, locale } = useI18n();
  const name = surah ? (locale === "ru" ? surah.name_ru : locale === "ar" ? surah.name_ar : surah.name_en) : "";
  return (
    <div className={`quran-end${paper ? " is-paper" : ""}`} data-testid="quran-end">
      <span className="quran-end-mark" aria-hidden="true">۞</span>
      <strong>{t("quran.quranEnd")}</strong>
      <span>{t("quran.quranEndNote", { surah: `${LAST_SURAH}. ${name}`.trim() })}</span>
      <a className="btn btn-secondary" href={listHref}>{t("quran.toSurahList")}</a>
    </div>
  );
}
