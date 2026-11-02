"use client";

import Image, { ImageLoaderProps } from "next/image";
import { useEffect, useState } from "react";
import { DEFAULT_RECITER_PORTRAIT } from "../lib/reciter-portraits";
import { useHydrated } from "../lib/use-hydrated";

const passthroughLoader = ({ src }: ImageLoaderProps) => src;

function initials(name: string): string {
  return name
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => Array.from(part)[0] || "")
    .join("")
    .toLocaleUpperCase();
}

/** Marks a reciter who also plays in the Mushaf and Memorization. */
export function ReciterFullBadge() {
  return (
    <span className="reciter-full-badge" aria-hidden="true">
      <svg viewBox="0 0 24 24" width="62%" height="62%" fill="currentColor">
        <path d="M12 6.5C10.2 5 7.7 4.4 4 4.5a1 1 0 0 0-1 1V18a1 1 0 0 0 1 1c3.4-.1 6 .4 7.5 1.8h1c1.5-1.4 4.1-1.9 7.5-1.8a1 1 0 0 0 1-1V5.5a1 1 0 0 0-1-1c-3.7-.1-6.2.5-8 2Z" />
      </svg>
    </span>
  );
}

export function ReciterAvatar({
  name,
  portraitUrl,
  tone,
  full = false,
}: {
  name: string;
  portraitUrl?: string | null;
  tone: number;
  full?: boolean;
}) {
  const [failed, setFailed] = useState<readonly string[]>([]);
  // Portraits are decorative: request them after hydration so they do not
  // compete with the server-rendered text on slow connections.
  const hydrated = useHydrated();

  useEffect(() => setFailed([]), [portraitUrl]);
  // A portrait that does not load falls back to the default figure; initials
  // only when that is unreachable too.
  const src = [portraitUrl, DEFAULT_RECITER_PORTRAIT].find(
    (url): url is string => Boolean(url) && !failed.includes(url!),
  );

  return (
    <span
      className={`reciter-avatar reciter-avatar-tone-${tone % 4}`}
      aria-hidden="true"
      data-testid="reciter-avatar"
    >
      {!src && (
        <span className="reciter-avatar-initials">{initials(name)}</span>
      )}
      {src && hydrated && (
        <Image
          loader={passthroughLoader}
          unoptimized
          className="reciter-avatar-image"
          src={src}
          alt=""
          width={112}
          height={112}
          onError={() => setFailed((current) => [...current, src])}
        />
      )}
      <span className="reciter-avatar-play">▶</span>
      {full && <ReciterFullBadge />}
    </span>
  );
}
