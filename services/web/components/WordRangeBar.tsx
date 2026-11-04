"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useI18n } from "../lib/i18n-context";
import { wordTiming } from "../lib/tajweed";
import { compareWords, sameWord, wordRangeContains, type QuranWord, type QuranWordRange } from "../lib/word-range";
import { loadAyahAudio, useClipPlayer, type AyahAudio, type Clip } from "./TajweedAudio";

type Repeat = "once" | "three" | "forever";

/**
 * The bar under a reader with selected words: plays them from the start of
 * the first to the end of the last in the reciter's surah track, with a
 * repeat, and reports the word that sounds.
 */
export default function WordRangeBar({
  range,
  wordCount,
  recitationId,
  reciterName,
  fallbackVoices = [],
  onClear,
  onPlayingWord,
}: {
  range: QuranWordRange;
  wordCount: number;
  recitationId: string | null;
  reciterName?: string;
  /** The voices, in order, for words the chosen reciter has no timings of, and what each says. */
  fallbackVoices?: { id: string; name: string; note: string }[];
  onClear: () => void;
  onPlayingWord: (word: QuranWord | null) => void;
}) {
  const { t } = useI18n();
  const [available, setAvailable] = useState<boolean | null>(null);
  /** The voice standing in for the chosen reciter, if one does. */
  const [standIn, setStandIn] = useState<{ id: string; name: string; note: string } | null>(null);
  const [repeat, setRepeat] = useState<Repeat>("once");
  const [round, setRound] = useState(1);
  const [loading, setLoading] = useState(false);
  /** The sounding word's number in the range, once its ayahs' timings are known. */
  const [ordinal, setOrdinal] = useState<number | null>(null);
  const timings = useRef(new Map<number, AyahAudio>());
  const clip = useRef<Clip | null>(null);
  const rounds = useRef(1);
  const repeatRef = useRef(repeat);
  const reported = useRef<QuranWord | null>(null);
  const report = useRef(onPlayingWord);
  useEffect(() => {
    repeatRef.current = repeat;
    report.current = onPlayingWord;
  });

  const onTime = useCallback((ms: number | null) => {
    let found: QuranWord | null = null;
    if (ms !== null) {
      for (let ayah = range.start.ayah; ayah <= range.end.ayah && !found; ayah += 1) {
        const row = timings.current.get(ayah)?.words.find(([, start, end]) => ms >= start && ms < end);
        const word = row ? { surah: range.start.surah, ayah, position: row[0] } : null;
        if (word && wordRangeContains(range, word)) found = word;
      }
    }
    if (sameWord(found, reported.current) || found === reported.current) return;
    reported.current = found;
    let number: number | null = found ? 0 : null;
    for (let ayah = range.start.ayah; found && number !== null && ayah <= found.ayah; ayah += 1) {
      const audio = timings.current.get(ayah);
      number = audio ? number + audio.words.filter(([position]) => {
        const word = { surah: range.start.surah, ayah, position };
        return wordRangeContains(range, word) && compareWords(word, found) <= 0;
      }).length : null;
    }
    setOrdinal(number);
    report.current(found);
  }, [range]);

  const replay = useRef<() => void>(() => {});
  const player = useClipPlayer(onTime, () => replay.current());
  const { attach, playing, error, play, stop } = player;

  useEffect(() => {
    replay.current = () => {
      const next = clip.current;
      if (!next) return;
      if (repeatRef.current === "forever" || (repeatRef.current === "three" && rounds.current < 3)) {
        rounds.current += 1;
        setRound(rounds.current);
        void play(next, 1);
      }
    };
  }, [play]);

  const startKey = `${range.start.surah}:${range.start.ayah}`;
  const rangeKey = `${startKey}:${range.start.position}-${range.end.ayah}:${range.end.position}`;

  // The bar never covers the selected words: the page scrolls them above it,
  // and where it cannot (the phone's full-screen Mushaf) the bar goes up.
  const barRef = useRef<HTMLElement>(null);
  const [onTop, setOnTop] = useState(false);
  useEffect(() => {
    const place = () => {
      if (document.documentElement.dataset.wordSelecting) return;
      const bar = barRef.current;
      const words = [...document.querySelectorAll<HTMLElement>(".is-word-selected[data-word-key]")];
      if (!bar || words.length === 0) return;
      const bounds = () => words.map((word) => word.getBoundingClientRect());
      const barHeight = bar.getBoundingClientRect().height;
      const bottomTop = window.innerHeight - 12 - barHeight;
      const overlap = Math.max(...bounds().map((box) => box.bottom)) + 12 - bottomTop;
      if (overlap <= 0) {
        setOnTop(false);
        return;
      }
      const before = window.scrollY;
      window.scrollBy({ top: overlap, behavior: "instant" });
      if (window.scrollY - before >= overlap - 1) {
        setOnTop(false);
        return;
      }
      setOnTop(Math.min(...bounds().map((box) => box.top)) > 12 + barHeight + 8);
    };
    const timer = window.setTimeout(place);
    // A finger that lets go of the selection places the bar again.
    const observer = new MutationObserver(place);
    observer.observe(document.documentElement, { attributes: true, attributeFilter: ["data-word-selecting"] });
    return () => {
      window.clearTimeout(timer);
      observer.disconnect();
    };
  }, [rangeKey]);

  // Another selection stops this one.
  useEffect(() => {
    clip.current = null;
    rounds.current = 1;
    setRound(1);
    stop();
  }, [rangeKey, recitationId, stop]);

  // The voice of the range: the chosen reciter when it has the timings of the
  // first and last words, else the teaching al-Husary; null when neither has them.
  const resolveVoice = useCallback(async () => {
    const surah = range.start.surah;
    const candidates = [
      ...(recitationId ? [{ id: recitationId, name: "", note: "" }] : []),
      ...fallbackVoices.filter((voice) => voice.id !== recitationId),
    ];
    for (const candidate of candidates) {
      const { id } = candidate;
      const [first, last] = await Promise.all([
        loadAyahAudio(id, `${surah}:${range.start.ayah}`),
        loadAyahAudio(id, `${surah}:${range.end.ayah}`),
      ]);
      const from = first ? wordTiming(first.words, range.start.position) : null;
      const to = last ? wordTiming(last.words, range.end.position) : null;
      if (first && last && from && to && to.endMs > from.startMs) {
        return { id, first, last, from, to, standIn: id !== recitationId ? candidate : null };
      }
    }
    return null;
  }, [fallbackVoices, range, recitationId]);

  useEffect(() => {
    let cancelled = false;
    // Moving the last word keeps the answer on screen while the voice is checked again.
    void resolveVoice().then((voice) => {
      if (cancelled) return;
      setAvailable(Boolean(voice));
      setStandIn(voice?.standIn ?? null);
    });
    return () => { cancelled = true; };
  }, [resolveVoice]);
  useEffect(() => { setAvailable(null); }, [recitationId, startKey]);

  const start = useCallback(async () => {
    if (loading) return;
    setLoading(true);
    try {
      const voice = await resolveVoice();
      if (!voice) {
        setAvailable(false);
        return;
      }
      setStandIn(voice.standIn);
      const { id, first, last, from, to } = voice;
      const surah = range.start.surah;
      timings.current = new Map([[range.start.ayah, first], [range.end.ayah, last]]);
      for (let ayah = range.start.ayah + 1; ayah < range.end.ayah && ayah <= range.start.ayah + 40; ayah += 1) {
        void loadAyahAudio(id, `${surah}:${ayah}`).then((audio) => {
          if (audio) timings.current.set(ayah, audio);
        });
      }
      clip.current = { url: first.url, startMs: from.startMs, endMs: to.endMs };
      rounds.current = 1;
      setRound(1);
      await play(clip.current, 1);
    } finally {
      setLoading(false);
    }
  }, [loading, play, range, resolveVoice]);

  const toggle = useCallback(() => {
    if (playing) stop();
    else void start();
  }, [playing, start, stop]);

  useEffect(() => {
    const keyDown = (event: KeyboardEvent) => {
      const target = event.target instanceof Element ? event.target : null;
      if (target?.closest("input, textarea, select, [contenteditable='true']")) return;
      if (event.key === "Escape") {
        onClear();
      } else if (event.key === " " && !target?.closest("button, a")) {
        event.preventDefault();
        if (available) toggle();
      }
    };
    window.addEventListener("keydown", keyDown);
    return () => window.removeEventListener("keydown", keyDown);
  }, [available, onClear, toggle]);

  const label = (word: QuranWord) => t("wordRange.wordAt", { ayah: `${word.surah}:${word.ayah}`, position: word.position });
  const single = sameWord(range.start, range.end);
  const title = single ? label(range.start) : `${label(range.start)} — ${label(range.end)}`;
  const shownOrdinal = playing ? ordinal : null;
  const subtitle = [
    shownOrdinal ? t("wordRange.progress", { number: shownOrdinal, count: wordCount }) : t("wordRange.count", { count: wordCount }),
    !shownOrdinal ? (standIn ? standIn.name : reciterName) || null : null,
    playing && repeat === "three" ? t("wordRange.round", { round, total: 3 }) : null,
  ].filter(Boolean).join(" · ");

  return (
    <section
      ref={barRef}
      className={`word-range-bar${onTop ? " is-top" : ""}`}
      aria-label={t("wordRange.label")}
      data-testid="word-range-bar"
    >
      <audio ref={attach} preload="none" onEnded={() => { stop(); replay.current(); }} />
      <div className="word-range-bar-head">
        <div className="word-range-bar-title">
          <strong data-testid="word-range-title">{title}</strong>
          <small>{subtitle}</small>
        </div>
        <button type="button" className="word-range-bar-close" onClick={onClear} aria-label={t("wordRange.clear")} title={`${t("wordRange.clear")} (Esc)`}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18" /></svg>
        </button>
      </div>
      {available && standIn && (
        <p className="word-range-bar-note is-teaching" data-testid="word-range-teaching-voice">{standIn.note}</p>
      )}
      {available === false && (
        <p className="word-range-bar-note" data-testid="word-range-unavailable">{t("wordRange.unavailable")}</p>
      )}
      {error && <p className="error-text" role="alert">{t("wordRange.error")}</p>}
      <div className="word-range-bar-actions">
        <button
          type="button"
          className="btn btn-primary word-range-bar-play"
          onClick={toggle}
          disabled={!available || loading}
          aria-busy={loading || available === null}
          data-testid="word-range-play"
        >
          <span aria-hidden="true">{playing ? "⏸" : "▶"}</span>{" "}
          {playing ? t("wordRange.pause") : single ? t("wordRange.listenWord") : t("wordRange.listenSelection")}
        </button>
        <div className="word-range-bar-repeat" role="group" aria-label={t("wordRange.repeat")}>
          {(["once", "three", "forever"] as const).map((value) => (
            <button
              type="button"
              key={value}
              aria-pressed={repeat === value}
              className={repeat === value ? "is-active" : undefined}
              onClick={() => {
                setRepeat(value);
                rounds.current = 1;
                setRound(1);
              }}
            >
              {t(value === "once" ? "wordRange.repeatOnce" : value === "three" ? "wordRange.repeatThree" : "wordRange.repeatForever")}
            </button>
          ))}
        </div>
      </div>
      <p className="word-range-bar-hint">
        <span className="is-pointer">{t("wordRange.hintPointer")}</span>
        <span className="is-touch">{t("wordRange.hintTouch")}</span>
      </p>
    </section>
  );
}
