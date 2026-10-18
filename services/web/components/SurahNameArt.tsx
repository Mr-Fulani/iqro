"use client";

import { useEffect, useSyncExternalStore } from "react";

import { loadedSurahNameGlyph, loadSurahNameFont } from "../lib/surah-header";

const listeners = new Set<() => void>();
let requested = false;

function requestFont(): void {
  if (requested) return;
  requested = true;
  loadSurahNameFont().then(
    () => listeners.forEach((listener) => listener()),
    // An unreachable or changed font keeps the text names; a later page may retry.
    () => {
      requested = false;
    },
  );
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  requestFont();
  return () => {
    listeners.delete(listener);
  };
}

/**
 * A surah's name as the Mushaf prints it: the calligraphy inside the QUL
 * heading glyph, filled as a path. The server and the first client render show
 * `fallback` as text, so hydration matches; the drawing replaces it once the
 * heading font is in memory.
 */
export function SurahNameArt({
  surah,
  fallback,
  className = "",
}: {
  surah: number;
  fallback: string;
  className?: string;
}) {
  const glyph = useSyncExternalStore(
    subscribe,
    () => loadedSurahNameGlyph(surah),
    () => undefined,
  );
  if (!glyph) {
    return (
      <span className={`surah-name-art surah-name-text ${className}`} lang="ar" dir="rtl">
        {fallback}
      </span>
    );
  }
  return (
    <svg
      className={`surah-name-art ${className}`}
      viewBox={glyph.viewBox}
      role="img"
      aria-label={fallback}
    >
      <path d={glyph.d} fill="currentColor" />
    </svg>
  );
}

/** Fetches the heading font when the browser is idle after the first page. */
export function SurahNamePreload() {
  useEffect(() => {
    const idle = window.requestIdleCallback ?? ((callback: () => void) => window.setTimeout(callback, 1500));
    idle(() => requestFont());
  }, []);
  return null;
}
