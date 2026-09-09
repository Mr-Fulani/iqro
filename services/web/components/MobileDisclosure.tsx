"use client";

import { useEffect, useRef, type ReactNode } from "react";

/** Only the presentation changes at the mobile breakpoint. Children stay
 * mounted so collapsing a panel never resets forms, requests or playback. */
export function MobileDisclosure({ title, children, className = "", mediaQuery = "(max-width: 768px)", expanded = false }: {
  title: ReactNode;
  children: ReactNode;
  className?: string;
  mediaQuery?: string;
  expanded?: boolean;
}) {
  const details = useRef<HTMLDetailsElement>(null);

  useEffect(() => {
    const mobile = window.matchMedia(mediaQuery);
    const update = () => {
      if (details.current) details.current.open = !mobile.matches;
    };
    update();
    mobile.addEventListener("change", update);
    return () => mobile.removeEventListener("change", update);
  }, [mediaQuery]);

  useEffect(() => {
    if (expanded && details.current) details.current.open = true;
  }, [expanded, mediaQuery]);

  return (
    <details ref={details} open className={`mobile-disclosure ${className}`}>
      <summary>{title}<span aria-hidden="true">⌄</span></summary>
      <div className="mobile-disclosure-body">{children}</div>
    </details>
  );
}
