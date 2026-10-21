"use client";

import { useCallback, useEffect, useId, useRef, useState, type CSSProperties } from "react";
import { api, type TajweedAyah, type TajweedFragment, type TajweedReference } from "../lib/api";
import { claimAudioFocus, registerAudioPlayer } from "../lib/audio-focus";
import { useI18n } from "../lib/i18n-context";
import {
  arabicParts,
  findTajweedWord,
  highlightRuns,
  joinedParts,
  joinedRuns,
  parseVerseKey,
  ruleOccurrences,
  ruleText,
  wordTiming,
  type TajweedPart,
  type TajweedSelection,
} from "../lib/tajweed";

type TajweedCardProps = {
  reference: TajweedReference;
  ayahs: TajweedAyah[];
  selection: TajweedSelection;
  /** Where the rule occurrences come from: the Mushaf page or one ayah. */
  scope: "page" | "ayah";
  recitationId: string | null;
  onSelect: (selection: TajweedSelection) => void;
  onClose: () => void;
};

type ColorStyle = CSSProperties & { "--tajweed-color": string };

function colorStyle(color: string): ColorStyle {
  return { "--tajweed-color": color };
}

function Letters({ parts, reference }: { parts: TajweedPart[]; reference: TajweedReference }) {
  return (
    <span className="tajweed-letters" dir="rtl" lang="ar">
      {parts.map((part, index) => (
        <span key={`${part.verseKey}-${part.word.position}`}>
          {index > 0 && " "}
          {joinedRuns(highlightRuns(part.word.text, [part.fragment])).map((run, runIndex) => run.code ? (
            <mark
              key={runIndex}
              style={colorStyle(reference.rules.find((rule) => rule.code === run.code)?.color ?? "currentColor")}
            >
              {run.text}
            </mark>
          ) : run.text)}
        </span>
      ))}
    </span>
  );
}

/** An explanation whose Arabic examples keep their own direction and font. */
function Explanation({ text }: { text: string }) {
  return (
    <p>
      {arabicParts(text).map((part, index) => part.arabic
        ? <bdi key={index} className="tajweed-inline-arabic" lang="ar">{part.text}</bdi>
        : part.text)}
    </p>
  );
}

function RuleHeading({ reference, code, variant }: { reference: TajweedReference; code: string; variant?: string }) {
  const { locale } = useI18n();
  const text = ruleText(reference, code, locale, variant);
  if (!text) return null;
  return (
    <>
      <h3 className="tajweed-rule-name">
        <span className="tajweed-dot" style={{ background: text.color }} aria-hidden="true" />
        {text.name}
        {text.variantName && <span className="tajweed-rule-variant"> · {text.variantName}</span>}
      </h3>
      {text.arabicName !== text.name && (
        <p className="tajweed-rule-arabic" dir="rtl" lang="ar">{text.arabicName}</p>
      )}
    </>
  );
}

const audioCache = new Map<string, Promise<{ url: string; words: [number, number, number][] } | null>>();

function loadAyahAudio(recitationId: string, verseKey: string) {
  const key = `${recitationId}|${verseKey}`;
  let request = audioCache.get(key);
  const reference = parseVerseKey(verseKey);
  if (!request && reference) {
    request = api.getAyahPlayback(recitationId, reference.surah, reference.ayah)
      .then(({ track, segment }) => ({ url: track.asset.url, words: segment.words ?? [] }))
      .catch(() => {
        audioCache.delete(key);
        return null;
      });
    audioCache.set(key, request);
  }
  return request ?? Promise.resolve(null);
}

/** Plays exactly one word of the current reciter's surah track. */
function WordAudio({ recitationId, verseKey, position }: { recitationId: string; verseKey: string; position: number }) {
  const { t } = useI18n();
  const [clip, setClip] = useState<{ key: string; url: string; startMs: number; endMs: number } | null>(null);
  const [playing, setPlaying] = useState(false);
  const [slow, setSlow] = useState(false);
  const [error, setError] = useState(false);
  const audio = useRef<HTMLAudioElement | null>(null);
  const frame = useRef(0);
  const focusId = useRef(Symbol("tajweed-word"));
  const clipKey = `${recitationId}|${verseKey}|${position}`;

  useEffect(() => {
    let cancelled = false;
    void loadAyahAudio(recitationId, verseKey).then((playback) => {
      if (cancelled) return;
      const timing = playback ? wordTiming(playback.words, position) : null;
      setClip(playback && timing ? { key: clipKey, url: playback.url, ...timing } : null);
    });
    return () => { cancelled = true; };
  }, [clipKey, position, recitationId, verseKey]);

  const stop = useCallback(() => {
    cancelAnimationFrame(frame.current);
    audio.current?.pause();
    setPlaying(false);
  }, []);

  useEffect(() => {
    // Another player taking audio focus, or leaving this word, stops the clip.
    const unregister = registerAudioPlayer(focusId.current, stop);
    return () => { unregister(); stop(); };
  }, [clipKey, stop]);

  if (!clip || clip.key !== clipKey) return null;

  const play = async () => {
    const element = audio.current;
    if (!element) return;
    setError(false);
    try {
      if (element.getAttribute("src") !== clip.url) {
        element.src = clip.url;
        await new Promise<void>((resolve, reject) => {
          element.addEventListener("loadedmetadata", () => resolve(), { once: true });
          element.addEventListener("error", () => reject(new Error("audio")), { once: true });
          element.load();
        });
      }
      claimAudioFocus(focusId.current);
      element.currentTime = clip.startMs / 1000;
      element.playbackRate = slow ? 0.75 : 1;
      await element.play();
      setPlaying(true);
      // timeupdate fires about four times a second: too coarse to end on one word.
      const watch = () => {
        if (element.paused) return;
        if (element.currentTime * 1000 >= clip.endMs) {
          stop();
          return;
        }
        frame.current = requestAnimationFrame(watch);
      };
      frame.current = requestAnimationFrame(watch);
    } catch {
      stop();
      setError(true);
    }
  };

  return (
    <div className="tajweed-audio">
      <audio ref={audio} preload="none" onEnded={stop} />
      <button
        type="button"
        className="btn btn-primary btn-sm"
        onClick={() => (playing ? stop() : void play())}
        data-testid="tajweed-listen"
      >
        {playing ? t("tajweed.stop") : t("tajweed.listen")}
      </button>
      <button
        type="button"
        className={`btn btn-secondary btn-sm tajweed-speed${slow ? " is-active" : ""}`}
        aria-pressed={slow}
        aria-label={t("tajweed.slowLabel")}
        onClick={() => {
          setSlow((value) => !value);
          if (audio.current) audio.current.playbackRate = slow ? 1 : 0.75;
        }}
      >
        {t("tajweed.slow")}
      </button>
      {error && <p className="error-text" role="alert">{t("tajweed.audioError")}</p>}
    </div>
  );
}

function fragmentGroups(fragments: readonly TajweedFragment[]): TajweedFragment[] {
  const seen = new Set<string>();
  return fragments.filter((fragment) => {
    const key = `${fragment.code}|${fragment.variant ?? ""}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

/**
 * The tajweed card: a bottom sheet on a phone, a dialog on a wide screen. It
 * explains a tapped word (every rule in it, the letters, how to read, the
 * word's audio) or one rule from the legend with its occurrences.
 */
export default function TajweedCard({
  reference,
  ayahs,
  selection,
  scope,
  recitationId,
  onSelect,
  onClose,
}: TajweedCardProps) {
  const { direction, locale, t } = useI18n();
  const dialog = useRef<HTMLDialogElement | null>(null);
  const title = useRef<HTMLHeadingElement | null>(null);
  const opener = useRef<Element | null>(null);
  const titleId = useId();
  const selectionKey = selection.kind === "word" ? `${selection.verseKey}#${selection.position}` : selection.code;

  useEffect(() => {
    const element = dialog.current;
    opener.current = document.activeElement;
    if (element && !element.open) element.showModal();
    return () => {
      const previous = opener.current;
      if (previous instanceof HTMLElement && previous.isConnected) previous.focus({ preventScroll: true });
    };
  }, []);

  useEffect(() => {
    title.current?.focus({ preventScroll: true });
  }, [selectionKey]);

  const found = selection.kind === "word" ? findTajweedWord(ayahs, selection.verseKey, selection.position) : null;
  const rule = selection.kind === "rule" ? ruleText(reference, selection.code, locale) : null;

  return (
    <dialog
      ref={dialog}
      className="tajweed-sheet"
      lang={locale}
      dir={direction}
      aria-labelledby={titleId}
      onClose={onClose}
      onClick={(event) => {
        if (event.target === event.currentTarget) dialog.current?.close();
      }}
      // The card opens after its lazy chunk loads, so the click's activation has
      // expired and Chrome would spend the first Esc on a cancel request.
      onKeyDown={(event) => {
        if (event.key !== "Escape") return;
        event.preventDefault();
        dialog.current?.close();
      }}
      data-testid="tajweed-card"
    >
      <div className="tajweed-sheet-head">
        <span className="tajweed-sheet-handle" aria-hidden="true" />
        <button
          type="button"
          className="tajweed-sheet-close"
          onClick={() => dialog.current?.close()}
          aria-label={t("common.close")}
        >
          ×
        </button>
      </div>
      <h2 id={titleId} ref={title} tabIndex={-1} className="tajweed-sheet-title">
        {selection.kind === "word" ? t("tajweed.wordTitle") : t("tajweed.ruleTitle")}
      </h2>

      {found && (
        <>
          <p className="tajweed-word">
            <span dir="rtl" lang="ar">
              {joinedRuns(highlightRuns(found.word.text, found.word.rules)).map((run, index) => run.code ? (
                <mark key={index} style={colorStyle(reference.rules.find((item) => item.code === run.code)?.color ?? "currentColor")}>
                  {run.text}
                </mark>
              ) : run.text)}
            </span>
            <small dir="ltr">{found.ayah.verse_key}</small>
          </p>
          {fragmentGroups(found.word.rules).map((fragment) => {
            const text = ruleText(reference, fragment.code, locale, fragment.variant);
            if (!text) return null;
            return (
              <section className="tajweed-rule" key={`${fragment.code}-${fragment.variant ?? ""}`} data-rule={fragment.code}>
                <RuleHeading reference={reference} code={fragment.code} variant={fragment.variant} />
                <h4>{t("tajweed.whyHere")}</h4>
                <p><Letters parts={joinedParts(found.ayah, found.word, fragment)} reference={reference} /></p>
                <Explanation text={text.why} />
                <h4>{t("tajweed.howToRead")}</h4>
                <Explanation text={text.how} />
              </section>
            );
          })}
          {recitationId && (
            <WordAudio recitationId={recitationId} verseKey={found.ayah.verse_key} position={found.word.position} />
          )}
        </>
      )}

      {selection.kind === "rule" && rule && (
        <section className="tajweed-rule" data-rule={rule.code}>
          <RuleHeading reference={reference} code={rule.code} />
          <h4>{t("tajweed.whenApplies")}</h4>
          <Explanation text={rule.why} />
          <h4>{t("tajweed.howToRead")}</h4>
          <Explanation text={rule.how} />
          <h4>{scope === "page" ? t("tajweed.occurrencesPage") : t("tajweed.occurrencesAyah")}</h4>
          <ul className="tajweed-occurrences">
            {ruleOccurrences(ayahs, rule.code).map((parts) => (
              <li key={`${parts[0].verseKey}-${parts[0].word.position}`}>
                <button
                  type="button"
                  onClick={() => onSelect({ kind: "word", verseKey: parts[0].verseKey, position: parts[0].word.position })}
                >
                  <Letters parts={parts} reference={reference} />
                  <small>{parts[0].verseKey}</small>
                </button>
              </li>
            ))}
          </ul>
        </section>
      )}

      {reference.review_status === "pending_teacher_review" && (
        <p className="tajweed-review-note">{t("tajweed.reviewNote")}</p>
      )}
    </dialog>
  );
}
