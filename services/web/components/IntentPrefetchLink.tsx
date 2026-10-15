"use client";

import Link from "next/link";
import { useState, type ComponentProps } from "react";

// Section pages are prerendered, so viewport prefetching of the navigation would
// download every section's RSC payload and JS on each page view. Prefetch a link
// only once the visitor points at, focuses or touches it.
export function IntentPrefetchLink(props: ComponentProps<typeof Link>) {
  const [intent, setIntent] = useState(false);
  const showIntent = () => setIntent(true);
  return (
    <Link
      {...props}
      prefetch={intent ? null : false}
      onMouseEnter={(event) => {
        showIntent();
        props.onMouseEnter?.(event);
      }}
      onFocus={(event) => {
        showIntent();
        props.onFocus?.(event);
      }}
      onTouchStart={(event) => {
        showIntent();
        props.onTouchStart?.(event);
      }}
    />
  );
}
