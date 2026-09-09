"use client";

import { type ReactNode, useEffect, useLayoutEffect, useRef, useState } from "react";
import { useMushafReader } from "./MushafReaderLayout";

type PageFrame = { id: string; content: ReactNode };

/** Keep one outgoing sheet for the visual transition only. Page navigation and
 * preloading remain independent, so another swipe can interrupt this animation. */
export function MushafPageTurn({
  pageId,
  direction,
  children,
}: {
  pageId: string;
  direction: "next" | "previous";
  children: ReactNode;
}) {
  const immersive = useMushafReader()?.immersive ?? false;
  const lastFrame = useRef<PageFrame | null>(null);
  const [outgoing, setOutgoing] = useState<PageFrame | null>(null);

  useLayoutEffect(() => {
    const previous = lastFrame.current;
    lastFrame.current = { id: pageId, content: children };
    if (!immersive || window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      setOutgoing(null);
    } else if (previous && previous.id !== pageId) {
      setOutgoing(previous);
    }
  }, [pageId, children, immersive]);

  useEffect(() => {
    if (!outgoing) return;
    // Also release the snapshot if CSS animation events are cancelled by a
    // rotation, a motion preference change or leaving the reader.
    const timer = window.setTimeout(() => setOutgoing(null), 400);
    return () => window.clearTimeout(timer);
  }, [outgoing]);

  return (
    <div className="mushaf-page-transition" data-turning={outgoing ? direction : undefined}>
      {outgoing && (
        <div className="mushaf-page-outgoing" key={`out-${outgoing.id}`} inert aria-hidden="true">
          {outgoing.content}
        </div>
      )}
      <div
        className={`mushaf-page-turn is-${direction}`}
        data-page-turn={direction}
        key={pageId}
        onAnimationEnd={(event) => {
          if (event.target === event.currentTarget) setOutgoing(null);
        }}
      >
        {children}
      </div>
    </div>
  );
}
