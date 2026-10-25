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

export function ReciterAvatar({
  name,
  portraitUrl,
  tone,
}: {
  name: string;
  portraitUrl?: string | null;
  tone: number;
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
    </span>
  );
}
