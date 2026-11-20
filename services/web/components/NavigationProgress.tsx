"use client";

import { usePathname, useSearchParams } from "next/navigation";
import { useEffect, useState } from "react";

/** Sent by instrumentation-client.ts when the router starts any navigation. */
const NAVIGATION_START_EVENT = "iqro:navigation-start";

const addressKey = (pathname: string, search: string) => `${pathname}?${new URLSearchParams(search)}`;

/**
 * A thin bar at the top of the window from the moment a link is pressed until
 * the next page is drawn. It is fixed over the page, so nothing moves under it.
 */
export function NavigationProgress() {
  const here = addressKey(usePathname(), useSearchParams().toString());
  // 0 while idle; otherwise the number of the navigation the bar is drawn for.
  const [run, setRun] = useState(0);
  const [drawnFor, setDrawnFor] = useState(here);
  if (drawnFor !== here) {
    setDrawnFor(here);
    setRun(0);
  }

  useEffect(() => {
    const start = (event: Event) => {
      const target = new URL((event as CustomEvent<string>).detail, window.location.href);
      // A link to the page itself or to a place on it changes no address to wait for.
      if (addressKey(target.pathname, target.search) === addressKey(window.location.pathname, window.location.search)) return;
      // The router calls this inside its own transition, where an update would
      // wait for the next page: the very wait the bar is there to show.
      queueMicrotask(() => setRun((current) => current + 1));
    };
    window.addEventListener(NAVIGATION_START_EVENT, start);
    return () => window.removeEventListener(NAVIGATION_START_EVENT, start);
  }, []);

  // A new key restarts the animation when one navigation replaces another.
  return run ? <div key={run} className="navigation-progress" data-testid="navigation-progress" aria-hidden="true" /> : null;
}
