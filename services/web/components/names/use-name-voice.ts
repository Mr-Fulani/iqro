"use client";

import { useCallback, useMemo, useRef, useState } from "react";

import { api } from "@/lib/api";
import type { DivineName } from "@/lib/names";
import { NAME_ONLY, RECORDED_NAMES } from "@/lib/names-audio";
import { latestRecitationsByVariant, tajweedCourseRecitation, wordTimingFallbackRecitations } from "@/lib/reciter-catalog";
import { wordTiming } from "@/lib/tajweed";
import { loadAyahAudio, useClipPlayer, type Clip } from "../TajweedAudio";

let voices: Promise<string[]> | null = null;

/** The reciters to ask for a word, in order: the teaching voice first, then those with word timings. */
function loadVoices(): Promise<string[]> {
  voices ??= api.getAllRecitations({ quran_edition: "madani-hafs" })
    .then((catalog) => {
      const available = latestRecitationsByVariant(catalog, "ayah_playback");
      const ids = [tajweedCourseRecitation(available)?.id, ...wordTimingFallbackRecitations(available).map((item) => item.id)];
      return [...new Set(ids.filter((id): id is string => Boolean(id)))];
    })
    .catch(() => {
      voices = null;
      return [];
    });
  return voices;
}

const clips = new Map<string, Promise<Clip | null>>();

/** The name as a reciter says it in its ayah: the same word the Mushaf plays by «Прослушать слово». */
function nameClip(name: DivineName): Promise<Clip | null> {
  const { ayah } = name;
  if (!ayah || ayah.word === null) return Promise.resolve(null);
  const key = `${ayah.surah}:${ayah.ayah}:${ayah.word}`;
  let request = clips.get(key);
  if (!request) {
    request = (async () => {
      for (const id of await loadVoices()) {
        const audio = await loadAyahAudio(id, `${ayah.surah}:${ayah.ayah}`);
        const timing = audio ? wordTiming(audio.words, ayah.word ?? 0) : null;
        if (audio && timing) return { url: audio.url, ...timing };
      }
      // Nothing found may be a lost connection: the next press asks again.
      clips.delete(key);
      return null;
    })();
    clips.set(key, request);
  }
  return request;
}

export type NameVoice = {
  /** The ref of the page's one `<audio>` element. */
  attach: (element: HTMLAudioElement | null) => void;
  /** The slug of the name that sounds now. */
  playing: string | null;
  /** The slug of a name no reciter has a recording of, once it was asked for. */
  missing: string | null;
  /** Whether the card has «Слушать» for the name. */
  canSay: (name: DivineName) => boolean;
  /** Says the name with its meaning in `language`; `ar` is the name alone. */
  play: (name: DivineName, language?: string) => Promise<void>;
  stop: () => void;
};

/**
 * Says a name from the recordings in `public/names-audio/<language>/`: the name
 * with its meaning in the interface language, or the name alone. A name without
 * a recording is said by a reciter, as a word of its ayah; a name with neither
 * stays silent.
 */
export function useNameVoice(): NameVoice {
  const [slug, setSlug] = useState<string | null>(null);
  const [missing, setMissing] = useState<string | null>(null);
  const [recording, setRecording] = useState(false);
  const element = useRef<HTMLAudioElement | null>(null);
  const player = useClipPlayer();
  const { attach: attachClip, play: playClip, stop: stopClip, playing } = player;

  const attach = useCallback((node: HTMLAudioElement | null) => {
    element.current = node;
    attachClip(node);
  }, [attachClip]);

  const stop = useCallback(() => {
    stopClip();
    element.current?.pause();
    setRecording(false);
  }, [stopClip]);

  const play = useCallback(async (name: DivineName, language: string = NAME_ONLY) => {
    const audio = element.current;
    if (RECORDED_NAMES.has(name.slug) && audio) {
      stopClip();
      setMissing(null);
      setSlug(name.slug);
      setRecording(true);
      audio.src = `/names-audio/${language}/${name.slug}.mp3`;
      audio.playbackRate = 1;
      try {
        await audio.play();
      } catch {
        // A new name interrupted this one, or the browser refused sound.
        if (audio.paused) setRecording(false);
      }
      return;
    }
    if (!name.ayah || name.ayah.word === null) return;
    const clip = await nameClip(name);
    if (!clip) {
      setMissing(name.slug);
      return;
    }
    setMissing(null);
    setRecording(false);
    setSlug(name.slug);
    await playClip(clip, 1);
  }, [playClip, stopClip]);

  return useMemo(
    () => ({ attach, playing: playing || recording ? slug : null, missing, canSay, play, stop }),
    [attach, missing, play, playing, recording, slug, stop],
  );
}

function canSay(name: DivineName): boolean {
  return RECORDED_NAMES.has(name.slug) || Boolean(name.ayah && name.ayah.word !== null);
}
