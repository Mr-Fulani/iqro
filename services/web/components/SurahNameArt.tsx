"use client";

import { useEffect, useRef, useSyncExternalStore } from "react";

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
  return () => {
    listeners.delete(listener);
  };
}

/**
 * A surah's name as the Mushaf prints it: the calligraphy inside the QUL
 * heading glyph, filled as a path. The server and the first client render show
 * `fallback` as text, so hydration matches; the drawing replaces it once the
 * heading font is in memory. The font (≈190 KB) is fetched only when a name
 * comes near the screen, so pages whose names stay below the fold do not pay
 * for it; the browser cache serves it afterwards.
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
  const textRef = useRef<HTMLSpanElement>(null);
  useEffect(() => {
    const element = textRef.current;
    if (glyph || !element) return;
    if (typeof IntersectionObserver === "undefined") {
      requestFont();
      return;
    }
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries.some((entry) => entry.isIntersecting)) {
          observer.disconnect();
          requestFont();
        }
      },
      { rootMargin: "800px 0px" },
    );
    observer.observe(element);
    return () => observer.disconnect();
  }, [glyph]);
  if (!glyph) {
    return (
      <span ref={textRef} className={`surah-name-art surah-name-text ${className}`} lang="ar" dir="rtl">
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
