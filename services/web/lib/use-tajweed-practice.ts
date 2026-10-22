"use client";

import { useCallback, useEffect, useMemo, useSyncExternalStore } from "react";

import { api, ApiError } from "./api";
import { useAuth } from "./auth-context";
import { browserStorage } from "./course-progress";
import { TAJWEED_COURSE_SLUG } from "./tajweed-course";
import {
  applyPracticeSession,
  parsePracticeState,
  parsePracticeStore,
  practiceStorageKey,
  TAJWEED_PRACTICE_EVENT,
  type PracticeStore,
} from "./tajweed-practice";

export function readPracticeStore(courseSlug: string = TAJWEED_COURSE_SLUG): PracticeStore {
  try {
    return parsePracticeStore(browserStorage()?.getItem(practiceStorageKey(courseSlug)) ?? null);
  } catch {
    return parsePracticeStore(null);
  }
}

export function writePracticeStore(store: PracticeStore, courseSlug: string = TAJWEED_COURSE_SLUG): void {
  try {
    browserStorage()?.setItem(practiceStorageKey(courseSlug), JSON.stringify(store));
  } catch {
    // Practice stays best-effort when storage is blocked or full.
    return;
  }
  window.dispatchEvent(new Event(TAJWEED_PRACTICE_EVENT));
}

/** Local practice state and unsent sessions; `null` in server HTML and during hydration. */
export function usePracticeStore(courseSlug: string = TAJWEED_COURSE_SLUG): PracticeStore | null {
  const key = practiceStorageKey(courseSlug);
  const raw = useSyncExternalStore(
    (onChange) => {
      window.addEventListener("storage", onChange);
      window.addEventListener(TAJWEED_PRACTICE_EVENT, onChange);
      return () => {
        window.removeEventListener("storage", onChange);
        window.removeEventListener(TAJWEED_PRACTICE_EVENT, onChange);
      };
    },
    () => {
      try {
        return window.localStorage.getItem(key) ?? "";
      } catch {
        return "";
      }
    },
    () => null,
  );
  return useMemo(() => (raw === null ? null : parsePracticeStore(raw)), [raw]);
}

/**
 * For a signed-in visitor (a guest too): sends unsent sessions one by one and
 * keeps the account's state from the answer; with nothing to send, takes the
 * account's state, which other devices may have moved on. Runs on mount and
 * whenever the returned function is called.
 */
export function useTajweedPracticeSync(courseSlug: string = TAJWEED_COURSE_SLUG): () => Promise<void> {
  const { session, isLoading } = useAuth();
  const enabled = !isLoading && Boolean(session?.access_token) && session?.user.status !== "pending_deletion";
  const userId = session?.user.id;
  const sync = useCallback(async () => {
    if (!enabled || !userId) return;
    try {
      const { pending } = readPracticeStore(courseSlug);
      if (!pending.length) {
        const state = parsePracticeState(await api.getTajweedPracticeState(courseSlug));
        // Sessions finished while the request was out are counted on top of the account's state.
        const waiting = readPracticeStore(courseSlug).pending;
        if (state) writePracticeStore({ state: waiting.reduce(applyPracticeSession, state), pending: waiting }, courseSlug);
        return;
      }
      for (const sent of pending) {
        let state = null;
        try {
          state = parsePracticeState(await api.saveTajweedPracticeSession(sent));
        } catch (error) {
          // A session the account already holds with other answers cannot be sent again.
          if (!(error instanceof ApiError) || error.status !== 409) throw error;
        }
        const current = readPracticeStore(courseSlug);
        const waiting = current.pending.filter((item) => item.id !== sent.id);
        // The account's state counts the sent sessions; the rest are still counted locally.
        writePracticeStore({
          state: state ? waiting.reduce(applyPracticeSession, state) : current.state,
          pending: waiting,
        }, courseSlug);
      }
    } catch {
      return;
    }
  }, [courseSlug, enabled, userId]);
  useEffect(() => {
    void sync();
  }, [sync]);
  return sync;
}
