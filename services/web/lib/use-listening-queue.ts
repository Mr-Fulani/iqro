"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { Dispatch, MutableRefObject, SetStateAction } from "react";
import type { AudioPlaybackRequest } from "../components/SegmentedAudioPlayer";
import { api } from "./api";
import type { Surah, SurahPlayback } from "./api";
import type { Translate } from "./i18n";
import {
  DEFAULT_QUEUE_MODE,
  adjacentQueueSurah,
  currentVariant,
  heldSurahs,
  loadListeningSnapshot,
  nearestHeldSurah,
  saveListeningSnapshot,
  surahAfter,
  wholeQuranMode,
} from "./listening-queue";
import type { ListeningQueue, ListeningSnapshot, QueueMode } from "./listening-queue";

/** How often a playing surah writes its place down; pauses and page hides write at once. */
const SAVE_INTERVAL_MS = 5000;
/** The saved place comes back once the page has settled, away from its first paint. */
const RESTORE_DELAY_MS = 1200;
const PREFETCH_LIMIT = 6;

export type QueueStart = { autoPlay?: boolean; wholeQuran?: boolean };

/** What the player's queue controls read and call. */
export type ListeningQueueControls = {
  queue: ListeningQueue;
  mode: QueueMode;
  setMode: (mode: QueueMode) => void;
  /** The held surahs of the current recording. */
  held: number[];
  current: number | null;
  /** What plays after the current surah under the mode; null in the stop mode or at the end. */
  upNext: number | null;
  previous: number | null;
  next: number | null;
  /** Surah names by number, once the edition's list has arrived. */
  surahs: ReadonlyMap<number, Surah>;
  busy: boolean;
  error: string | null;
  changeSurah: (direction: -1 | 1) => void;
  playSurah: (surah: number) => void;
  playFromStart: () => void;
  chooseVariant: (variantId: string) => void;
};

type Options = {
  request: AudioPlaybackRequest | null;
  setRequest: Dispatch<SetStateAction<AudioPlaybackRequest | null>>;
  requestRef: MutableRefObject<AudioPlaybackRequest | null>;
  isPlaying: boolean;
  isPlayingRef: MutableRefObject<boolean>;
  nextRequestId: () => number;
  hydrated: boolean;
  t: Translate;
};

const playbackKey = (variantId: string, surah: number) => `${variantId}:${surah}`;

/**
 * The global player's queue: the surah after this one, the previous and next
 * buttons, the switch between a reciter's recordings and the saved place.
 * Requests it makes carry the queue on, so whatever page started playback,
 * the player keeps moving through the same recordings.
 */
export function useListeningQueue({
  request,
  setRequest,
  requestRef,
  isPlaying,
  isPlayingRef,
  nextRequestId,
  hydrated,
  t,
}: Options) {
  const [mode, setModeState] = useState<QueueMode>(DEFAULT_QUEUE_MODE);
  const modeRef = useRef<QueueMode>(DEFAULT_QUEUE_MODE);
  const [change, setChange] = useState<{ busy: boolean; error: string | null }>({ busy: false, error: null });
  const [surahsByEdition, setSurahsByEdition] = useState<Record<string, ReadonlyMap<number, Surah>>>({});
  const attemptRef = useRef(0);
  const pendingRef = useRef(new Map<string, Promise<SurahPlayback>>());
  // Resolved playbacks, so the end of a surah swaps the source without waiting on the network.
  const readyRef = useRef(new Map<string, SurahPlayback>());
  const positionRef = useRef(0);
  const savedAtRef = useRef(0);
  const restoredRef = useRef(false);

  const queue = request?.kind === "surah" ? request.queue ?? null : null;
  const variant = queue ? currentVariant(queue) : undefined;
  const held = useMemo(() => heldSurahs(variant?.surahNumbers), [variant?.surahNumbers]);
  const current = queue ? request?.track.surah_number ?? null : null;

  const setMode = useCallback((next: QueueMode) => {
    modeRef.current = next;
    setModeState(next);
  }, []);

  const fetchPlayback = useCallback((variantId: string, surah: number): Promise<SurahPlayback> => {
    const key = playbackKey(variantId, surah);
    const ready = readyRef.current.get(key);
    if (ready) return Promise.resolve(ready);
    const pending = pendingRef.current.get(key);
    if (pending) return pending;
    const promise = api.getSurahPlayback(variantId, surah).then((playback) => {
      if (readyRef.current.size >= PREFETCH_LIMIT) {
        readyRef.current.delete(readyRef.current.keys().next().value as string);
      }
      readyRef.current.set(key, playback);
      return playback;
    }).finally(() => {
      pendingRef.current.delete(key);
    });
    pendingRef.current.set(key, promise);
    return promise;
  }, []);

  const buildRequest = useCallback((
    nextQueue: ListeningQueue,
    playback: SurahPlayback,
    surah: number,
    autoPlay: boolean,
    startPositionMs?: number,
  ): AudioPlaybackRequest => ({
    requestId: nextRequestId(),
    track: playback.track,
    segments: playback.segments || [],
    kind: "surah",
    title: t("common.surah", { surah }),
    artist: nextQueue.artist,
    album: currentVariant(nextQueue)?.label,
    artworkUrl: nextQueue.artworkUrl,
    autoPlay,
    startPositionMs,
    queue: nextQueue,
  }), [nextRequestId, t]);

  /** Plays a surah of a queue; rejects when the recording has no such surah. */
  const startQueue = useCallback(async (
    nextQueue: ListeningQueue,
    surah: number,
    { autoPlay = true, wholeQuran = false }: QueueStart = {},
  ): Promise<void> => {
    if (wholeQuran) setMode(wholeQuranMode(modeRef.current));
    const attempt = ++attemptRef.current;
    const ready = readyRef.current.get(playbackKey(nextQueue.variantId, surah));
    if (ready) {
      setChange({ busy: false, error: null });
      setRequest(buildRequest(nextQueue, ready, surah, autoPlay));
      return;
    }
    setChange({ busy: true, error: null });
    try {
      const playback = await fetchPlayback(nextQueue.variantId, surah);
      if (attempt !== attemptRef.current) return;
      setChange({ busy: false, error: null });
      setRequest(buildRequest(nextQueue, playback, surah, autoPlay));
    } catch (reason) {
      if (attempt === attemptRef.current) setChange({ busy: false, error: t("player.surahUnavailable") });
      throw reason;
    }
  }, [buildRequest, fetchPlayback, setMode, setRequest, t]);

  const playInQueue = useCallback((surah: number | null, autoPlay = isPlayingRef.current, variantId?: string) => {
    const active = requestRef.current?.queue;
    if (!active || surah === null) return;
    const nextQueue = variantId ? { ...active, variantId } : active;
    startQueue(nextQueue, surah, { autoPlay }).catch(() => undefined);
  }, [isPlayingRef, requestRef, startQueue]);

  const changeSurah = useCallback((direction: -1 | 1) => {
    playInQueue(adjacentQueueSurah(held, current, direction, modeRef.current));
  }, [current, held, playInQueue]);

  const chooseVariant = useCallback((variantId: string) => {
    const active = requestRef.current?.queue;
    const target = active?.variants.find((item) => item.id === variantId);
    if (!active || !target || variantId === active.variantId || current === null) return;
    playInQueue(nearestHeldSurah(heldSurahs(target.surahNumbers), current), isPlayingRef.current, variantId);
  }, [current, isPlayingRef, playInQueue, requestRef]);

  /** The player reached the end of a surah: true when the queue goes on. */
  const onPlanEnd = useCallback((): boolean => {
    const active = requestRef.current;
    if (!active?.queue || active.kind !== "surah" || !active.track.surah_number) return false;
    const activeVariant = currentVariant(active.queue);
    const after = surahAfter(heldSurahs(activeVariant?.surahNumbers), active.track.surah_number, modeRef.current);
    if (after === null) return false;
    startQueue(active.queue, after, { autoPlay: true }).catch(() => undefined);
    return true;
  }, [requestRef, startQueue]);

  // The surah that follows is fetched while this one plays.
  const upNext = queue && current !== null ? surahAfter(held, current, mode) : null;
  useEffect(() => {
    if (!queue || upNext === null) return;
    fetchPlayback(queue.variantId, upNext).catch(() => undefined);
  }, [fetchPlayback, queue, upNext]);

  const editionCode = variant?.editionCode;
  useEffect(() => {
    if (!editionCode || surahsByEdition[editionCode]) return;
    let cancelled = false;
    api.getSurahs(editionCode)
      .then((items) => {
        if (cancelled) return;
        setSurahsByEdition((known) => ({
          ...known,
          [editionCode]: new Map(items.map((item) => [item.number, item])),
        }));
      })
      .catch(() => undefined);
    return () => {
      cancelled = true;
    };
  }, [editionCode, surahsByEdition]);

  const save = useCallback(() => {
    const active = requestRef.current;
    if (!active?.queue || active.kind !== "surah" || !active.track.surah_number) return;
    savedAtRef.current = Date.now();
    saveListeningSnapshot({
      queue: active.queue,
      surah: active.track.surah_number,
      positionMs: positionRef.current,
      mode: modeRef.current,
      savedAt: new Date().toISOString(),
    });
  }, [requestRef]);

  const onPositionChange = useCallback((positionMs: number) => {
    positionRef.current = positionMs;
    if (isPlayingRef.current && Date.now() - savedAtRef.current >= SAVE_INTERVAL_MS) save();
  }, [isPlayingRef, save]);

  // A new surah starts from its own place; the mode is kept with it.
  useEffect(() => {
    positionRef.current = request?.startPositionMs ?? 0;
    save();
  }, [mode, request, save]);

  useEffect(() => {
    if (!isPlaying) save();
  }, [isPlaying, save]);

  useEffect(() => {
    const onHide = () => {
      if (document.visibilityState === "hidden") save();
    };
    window.addEventListener("pagehide", save);
    document.addEventListener("visibilitychange", onHide);
    return () => {
      window.removeEventListener("pagehide", save);
      document.removeEventListener("visibilitychange", onHide);
    };
  }, [save]);

  // The saved place comes back paused, once, unless something already plays.
  const [restore, setRestore] = useState<ListeningSnapshot | null>(null);
  useEffect(() => {
    if (!hydrated || restoredRef.current) return;
    restoredRef.current = true;
    const snapshot = loadListeningSnapshot();
    if (!snapshot) return;
    setMode(snapshot.mode);
    setRestore(snapshot);
  }, [hydrated, setMode]);

  useEffect(() => {
    if (!restore) return;
    let cancelled = false;
    const timer = setTimeout(() => {
      if (requestRef.current) {
        setRestore(null);
        return;
      }
      fetchPlayback(restore.queue.variantId, restore.surah)
        .then((playback) => {
          if (cancelled || requestRef.current) return;
          setRequest(buildRequest(restore.queue, playback, restore.surah, false, restore.positionMs));
        })
        .catch(() => undefined)
        .finally(() => {
          if (!cancelled) setRestore(null);
        });
    }, RESTORE_DELAY_MS);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [buildRequest, fetchPlayback, requestRef, restore, setRequest]);

  const resetChange = useCallback(() => setChange({ busy: false, error: null }), []);
  /** Playback was cleared or replaced from outside: a surah still loading must not land. */
  const cancel = useCallback(() => {
    attemptRef.current += 1;
  }, []);

  const controls: ListeningQueueControls | null = queue
    ? {
        queue,
        mode,
        setMode,
        held,
        current,
        upNext,
        previous: adjacentQueueSurah(held, current, -1, mode),
        next: adjacentQueueSurah(held, current, 1, mode),
        surahs: (editionCode && surahsByEdition[editionCode]) || EMPTY_SURAHS,
        busy: change.busy,
        error: change.error,
        changeSurah,
        playSurah: (surah) => playInQueue(surah, true),
        playFromStart: () => {
          setMode(wholeQuranMode(modeRef.current));
          playInQueue(held[0] ?? null, true);
        },
        chooseVariant,
      }
    : null;

  return { controls, change, resetChange, cancel, startQueue, onPlanEnd, onPositionChange, changeSurah };
}

const EMPTY_SURAHS: ReadonlyMap<number, Surah> = new Map();
