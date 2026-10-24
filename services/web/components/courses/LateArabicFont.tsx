"use client";

import type { ReactNode } from "react";

import { usePageLoaded } from "../../lib/use-page-loaded";

/**
 * On a phone the Quran font (Amiri, about 130 KB per face) waits until the page has
 * loaded, so the notes paint first in the system Arabic font (courses.css, .has-arabic-font).
 */
export function LateArabicFont({ children }: { children: ReactNode }) {
  const loaded = usePageLoaded();
  return <div className={loaded ? "has-arabic-font" : undefined}>{children}</div>;
}
