"use client";

import { useEffect, useRef, type ReactNode } from "react";

/** Only the presentation changes at the mobile breakpoint. Children stay
 * mounted so collapsing a panel never resets forms, requests or playback. */
export function MobileDisclosure({ title, children, className = "" }: {
  title: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  const details = useRef<HTMLDetailsElement>(null);

  useEffect(() => {
    const mobile = window.matchMedia("(max-width: 768px)");
    const update = () => {
      if (details.current) details.current.open = !mobile.matches;
    };
    update();
    mobile.addEventListener("change", update);
    return () => mobile.removeEventListener("change", update);
  }, []);

  return (
    <details ref={details} open className={`mobile-disclosure ${className}`}>
      <summary>{title}<span aria-hidden="true">⌄</span></summary>
      <div className="mobile-disclosure-body">{children}</div>
    </details>
  );
}
