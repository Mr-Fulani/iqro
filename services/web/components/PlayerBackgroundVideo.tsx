"use client";

import { useEffect, useRef } from "react";

/**
 * A silent looping video over its poster, mirroring _PlayerBackgroundVideo in
 * the app. It stays transparent until it actually plays, so the poster shows
 * while it loads or if the browser refuses to play it.
 */
export default function PlayerBackgroundVideo({ src }: { src: string }) {
  const videoRef = useRef<HTMLVideoElement>(null);

  useEffect(() => {
    videoRef.current?.play().catch(() => {
      // Autoplay can be refused, for example in a battery saver mode.
    });
  }, []);

  return (
    <video
      ref={videoRef}
      src={src}
      muted
      loop
      playsInline
      preload="none"
      disablePictureInPicture
      disableRemotePlayback
      onPlaying={(event) => {
        event.currentTarget.dataset.loaded = "true";
      }}
    />
  );
}
