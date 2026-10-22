"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { api } from "../lib/api";
import { claimAudioFocus, registerAudioPlayer } from "../lib/audio-focus";
import { useI18n } from "../lib/i18n-context";
import { parseVerseKey, wordTiming } from "../lib/tajweed";

/** One ayah in the reciter's surah track, with its word timings. */
export type AyahAudio = { url: string; startMs: number; endMs: number; words: [number, number, number][] };

export type Clip = { url: string; startMs: number; endMs: number };

const audioCache = new Map<string, Promise<AyahAudio | null>>();

export function loadAyahAudio(recitationId: string, verseKey: string): Promise<AyahAudio | null> {
  const key = `${recitationId}|${verseKey}`;
  let request = audioCache.get(key);
  const reference = parseVerseKey(verseKey);
  if (!request && reference) {
    request = api.getAyahPlayback(recitationId, reference.surah, reference.ayah)
      .then(({ track, segment }) => ({
        url: track.asset.url,
        startMs: segment.start_ms,
        endMs: segment.end_ms,
        words: segment.words ?? [],
      }))
      .catch(() => {
        audioCache.delete(key);
        return null;
      });
    audioCache.set(key, request);
  }
  return request ?? Promise.resolve(null);
}

/** The ayah's audio for the current reciter; null while it loads or when there is none. */
export function useAyahAudio(recitationId: string | null, verseKey: string): AyahAudio | null {
  const key = recitationId ? `${recitationId}|${verseKey}` : "";
  const [state, setState] = useState<{ key: string; audio: AyahAudio | null }>({ key: "", audio: null });
  useEffect(() => {
    if (!recitationId) return;
    let cancelled = false;
    void loadAyahAudio(recitationId, verseKey).then((audio) => {
      if (!cancelled) setState({ key: `${recitationId}|${verseKey}`, audio });
    });
    return () => { cancelled = true; };
  }, [recitationId, verseKey]);
  return state.key === key ? state.audio : null;
}

export type ClipPlayer = {
  /** The ref of the player's `<audio>` element. */
  attach: (element: HTMLAudioElement | null) => void;
  playing: boolean;
  error: boolean;
  play: (clip: Clip, rate: number) => Promise<void>;
  /** Stops the clip; the next play starts it from its beginning. */
  stop: () => void;
  setRate: (rate: number) => void;
};

/**
 * Plays one stretch of a surah track and stops at its end. Another player
 * taking audio focus stops it, and so does leaving the component. `onTime`
 * follows the position in milliseconds of the track, and gets null on stop.
 */
export function useClipPlayer(onTime?: (ms: number | null) => void): ClipPlayer {
  const ref = useRef<HTMLAudioElement | null>(null);
  const frame = useRef(0);
  // A stop while a clip is still loading must keep it from starting afterwards.
  const generation = useRef(0);
  const time = useRef(onTime);
  const [focusId] = useState(() => Symbol("tajweed-clip"));
  const [playing, setPlaying] = useState(false);
  const [error, setError] = useState(false);

  useEffect(() => { time.current = onTime; });

  const stop = useCallback(() => {
    generation.current += 1;
    cancelAnimationFrame(frame.current);
    ref.current?.pause();
    setPlaying(false);
    time.current?.(null);
  }, []);

  useEffect(() => {
    const unregister = registerAudioPlayer(focusId, stop);
    return () => { unregister(); stop(); };
  }, [focusId, stop]);

  const play = useCallback(async (clip: Clip, rate: number) => {
    const element = ref.current;
    if (!element) return;
    stop();
    const current = generation.current;
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
      if (current !== generation.current) return;
      claimAudioFocus(focusId);
      element.currentTime = clip.startMs / 1000;
      element.playbackRate = rate;
      await element.play();
      if (current !== generation.current) {
        element.pause();
        return;
      }
      setPlaying(true);
      // timeupdate fires about four times a second: too coarse to end on one word.
      const watch = () => {
        if (element.paused || current !== generation.current) return;
        const ms = element.currentTime * 1000;
        if (ms >= clip.endMs) {
          stop();
          return;
        }
        time.current?.(ms);
        frame.current = requestAnimationFrame(watch);
      };
      frame.current = requestAnimationFrame(watch);
    } catch {
      if (current !== generation.current) return;
      stop();
      setError(true);
    }
  }, [focusId, stop]);

  const setRate = useCallback((rate: number) => {
    if (ref.current) ref.current.playbackRate = rate;
  }, []);

  const attach = useCallback((element: HTMLAudioElement | null) => {
    ref.current = element;
  }, []);

  return { attach, playing, error, play, stop, setRate };
}

/** «Listen» (or «Stop») and the 0.75× switch for one clip. */
export function ClipButtons({
  player,
  clip,
  slow,
  onSlowChange,
  listenLabel,
}: {
  player: ClipPlayer;
  clip: Clip;
  slow: boolean;
  onSlowChange: (slow: boolean) => void;
  listenLabel?: string;
}) {
  const { t } = useI18n();
  const { attach, playing, error, play, stop, setRate } = player;
  return (
    <div className="tajweed-audio">
      <audio ref={attach} preload="none" onEnded={stop} />
      <button
        type="button"
        className="btn btn-primary btn-sm"
        onClick={() => (playing ? stop() : void play(clip, slow ? 0.75 : 1))}
        data-testid="tajweed-listen"
      >
        {playing ? t("tajweed.stop") : listenLabel ?? t("tajweed.listen")}
      </button>
      <button
        type="button"
        className={`btn btn-secondary btn-sm tajweed-speed${slow ? " is-active" : ""}`}
        aria-pressed={slow}
        aria-label={t("tajweed.slowLabel")}
        onClick={() => {
          onSlowChange(!slow);
          setRate(slow ? 1 : 0.75);
        }}
      >
        {t("tajweed.slow")}
      </button>
      {error && <p className="error-text" role="alert">{t("tajweed.audioError")}</p>}
    </div>
  );
}

/** Plays exactly one word of the current reciter's surah track. */
export function WordAudio({ recitationId, verseKey, position }: { recitationId: string; verseKey: string; position: number }) {
  const audio = useAyahAudio(recitationId, verseKey);
  const player = useClipPlayer();
  const [slow, setSlow] = useState(false);
  const { stop } = player;
  const timing = audio ? wordTiming(audio.words, position) : null;

  // Leaving this word stops its clip.
  useEffect(() => stop, [position, stop, verseKey]);

  if (!audio || !timing) return null;
  return <ClipButtons player={player} clip={{ url: audio.url, ...timing }} slow={slow} onSlowChange={setSlow} />;
}
