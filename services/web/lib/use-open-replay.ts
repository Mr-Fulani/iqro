"use client";

import { useEffect, useState } from "react";

/** Back after this long in another tab or app counts as opening the page again. */
export const OPEN_REPLAY_AFTER_MS = 60_000;

/**
 * A number that grows when the visitor returns to the page after a while:
 * used as a React key or effect dependency to replay the home page's opening
 * animations, as the app does when it is opened again.
 */
export function useOpenReplay(): number {
  const [count, setCount] = useState(0);
  useEffect(() => {
    let hiddenAt: number | null = null;
    const onVisibility = () => {
      if (document.visibilityState === "hidden") {
        hiddenAt = Date.now();
      } else if (hiddenAt !== null) {
        if (Date.now() - hiddenAt >= OPEN_REPLAY_AFTER_MS) setCount((value) => value + 1);
        hiddenAt = null;
      }
    };
    document.addEventListener("visibilitychange", onVisibility);
    return () => document.removeEventListener("visibilitychange", onVisibility);
  }, []);
  return count;
}
