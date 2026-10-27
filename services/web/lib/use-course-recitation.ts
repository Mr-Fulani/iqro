"use client";

import { useEffect, useState } from "react";

import { api } from "./api";
import { latestRecitationsByVariant, tajweedCourseRecitation } from "./reciter-catalog";

let courseRecitation: Promise<string | null> | null = null;

/** The reciter of the tajweed course clips: al-Husary's Muallim, see `tajweedCourseRecitation`. */
function loadCourseRecitation(): Promise<string | null> {
  courseRecitation ??= api.getAllRecitations({ quran_edition: "madani-hafs" })
    .then((catalog) => tajweedCourseRecitation(latestRecitationsByVariant(catalog, "ayah_playback"))?.id ?? null)
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
