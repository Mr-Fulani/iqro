"use client";

import { useEffect, useState } from "react";

/** True once the page has loaded: heavy fonts below the first paint wait for it. */
export function usePageLoaded(): boolean {
  const [loaded, setLoaded] = useState(false);
  useEffect(() => {
    const done = () => setLoaded(true);
    if (document.readyState === "complete") {
      done();
      return;
    }
    window.addEventListener("load", done, { once: true });
    return () => window.removeEventListener("load", done);
  }, []);
  return loaded;
}
