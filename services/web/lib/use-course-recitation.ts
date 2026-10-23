"use client";

import { useEffect, useState } from "react";

import { api } from "./api";
import { latestRecitationsByVariant } from "./reciter-catalog";
import { learningRecitation } from "./reciter-preference";

let courseRecitation: Promise<string | null> | null = null;

/**
 * The reciter of the tajweed course clips: the Mushaf's choice, else the
 * catalog's teaching reciter, else Mishary al-Afasy, else the first one.
 */
function loadCourseRecitation(): Promise<string | null> {
  courseRecitation ??= api.getAllRecitations({ quran_edition: "madani-hafs" })
    .then((catalog) => {
      const available = latestRecitationsByVariant(catalog, "ayah_playback");
      const fallback = available
        .filter((item) => item.code.startsWith("qf-7-"))
        .sort((left, right) => right.coverage.surah_count - left.coverage.surah_count)[0];
      return (learningRecitation(available, "mushaf") || fallback || available[0])?.id ?? null;
    })
    .catch(() => {
      courseRecitation = null;
      return null;
    });
  return courseRecitation;
}

/** The course reciter once something has to be played; `settled` once the lookup is over. */
export function useCourseRecitationState(needed: boolean): { id: string | null; settled: boolean } {
  const [state, setState] = useState<{ id: string | null; settled: boolean }>({ id: null, settled: false });
  useEffect(() => {
    if (!needed) return;
    let cancelled = false;
    void loadCourseRecitation().then((id) => {
      if (!cancelled) setState({ id, settled: true });
    });
    return () => { cancelled = true; };
  }, [needed]);
  return state;
}

/** The course reciter, looked up once something has to be played. */
export function useCourseRecitation(needed: boolean): string | null {
  return useCourseRecitationState(needed).id;
}
