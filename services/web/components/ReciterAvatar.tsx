"use client";

import Image, { ImageLoaderProps } from "next/image";
import { useEffect, useState } from "react";

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
  const [imageFailed, setImageFailed] = useState(false);

  useEffect(() => setImageFailed(false), [portraitUrl]);

  return (
    <span
      className={`reciter-avatar reciter-avatar-tone-${tone % 4}`}
      aria-hidden="true"
      data-testid="reciter-avatar"
    >
      <span className="reciter-avatar-initials">{initials(name)}</span>
      {portraitUrl && !imageFailed && (
        <Image
          loader={passthroughLoader}
          unoptimized
          className="reciter-avatar-image"
          src={portraitUrl}
          alt=""
          width={112}
          height={112}
          onError={() => setImageFailed(true)}
        />
      )}
      <span className="reciter-avatar-play">▶</span>
    </span>
  );
}
