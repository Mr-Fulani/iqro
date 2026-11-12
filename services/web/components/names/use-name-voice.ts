"use client";

import { useCallback, useMemo, useState } from "react";

import { api } from "@/lib/api";
import type { DivineName } from "@/lib/names";
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
  play: (name: DivineName) => Promise<void>;
  stop: () => void;
};

/** Plays a name's word in a reciter's voice; a name that is not one word of the Quran stays silent. */
export function useNameVoice(): NameVoice {
  const [slug, setSlug] = useState<string | null>(null);
  const [missing, setMissing] = useState<string | null>(null);
  const player = useClipPlayer();
  const { attach, play: playClip, stop: stopClip, playing } = player;

  const play = useCallback(async (name: DivineName) => {
    if (!name.ayah || name.ayah.word === null) return;
    const clip = await nameClip(name);
    if (!clip) {
      setMissing(name.slug);
      return;
    }
    setMissing(null);
    setSlug(name.slug);
    await playClip(clip, 1);
  }, [playClip]);

  return useMemo(
    () => ({ attach, playing: playing ? slug : null, missing, play, stop: stopClip }),
    [attach, missing, play, playing, slug, stopClip],
  );
}
