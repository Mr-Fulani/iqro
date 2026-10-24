"use client";

import { useEffect, useRef, useState } from "react";

import { formatClock } from "../../lib/audio-content";
import { claimAudioFocus, registerAudioPlayer } from "../../lib/audio-focus";
import { useI18n } from "../../lib/i18n-context";
import { readVideoPositions, videoMegabytes, writeVideoPosition, type CourseVideo } from "../../lib/thematic-courses";
import { useVideoPosition } from "./CourseProgress";

const SAVE_EVERY_MS = 5_000;

/**
 * The lesson video behind a cover: nothing of the file loads until the visitor
 * presses ▶. Then the browser's own player starts where the video stopped last time.
 */
export function LessonVideo({
  courseSlug,
  lessonSlug,
  title,
  video,
}: {
  courseSlug: string;
  lessonSlug: string;
  title: string;
  video: CourseVideo;
}) {
  const { formatNumber, t } = useI18n();
  const [state, setState] = useState<"cover" | "playing" | "error">("cover");
  const [attempt, setAttempt] = useState(0);
  const cover = useRef<HTMLImageElement>(null);
  const player = useRef<HTMLVideoElement>(null);
  const [poster, setPoster] = useState(video.poster.url);
  const savedAt = useRef(0);
  const position = useVideoPosition(courseSlug, lessonSlug);
  const clock = (ms: number) => formatClock(ms, (value) => formatNumber(value));
  const duration = clock(video.duration_ms);
  const size = formatNumber(videoMegabytes(video.bytes), { style: "unit", unit: "megabyte", maximumFractionDigits: 0 });

  // Quran and du'a recitations pause while the video plays, and the video pauses for them.
  useEffect(() => {
    const element = player.current;
    if (state !== "playing" || !element) return;
    element.focus();
    const id = Symbol("lesson-video");
    const unregister = registerAudioPlayer(id, () => element.pause());
    const claim = () => claimAudioFocus(id);
    element.addEventListener("play", claim);
    if (!element.paused) claim();
    return () => {
      element.removeEventListener("play", claim);
      unregister();
    };
  }, [attempt, state]);

  function play() {
    // The poster is the cover already on screen, so the player shows no extra image download.
    setPoster(cover.current?.currentSrc || video.poster.url);
    setState("playing");
  }

  function retry() {
    setAttempt((value) => value + 1);
    setState("playing");
  }

  function save(element: HTMLVideoElement) {
    savedAt.current = element.currentTime * 1_000;
    writeVideoPosition(courseSlug, lessonSlug, savedAt.current);
  }

  if (state === "error") {
    return (
      <div className="lesson-video lesson-video-error" data-testid="lesson-video" data-state="error">
        <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.6"
          strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <path d="M3 3l18 18M10.5 6H14a2 2 0 0 1 2 2v3.5l5-3v7.5M16 16a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h1" />
        </svg>
        <p role="alert" className="lesson-video-error-title">{t("courses.videoError")}</p>
        <p>{t("courses.videoErrorHint")}</p>
        <button type="button" className="btn btn-secondary" onClick={retry}>{t("courses.videoRetry")}</button>
      </div>
    );
  }

  if (state === "playing") {
    return (
      <div className="lesson-video" data-testid="lesson-video" data-state="playing">
        <video
          key={attempt}
          ref={player}
          src={video.url}
          poster={poster}
          width={video.width}
          height={video.height}
          aria-label={t("courses.videoPlayer", { title })}
          controls
          playsInline
          preload="metadata"
          autoPlay
          onLoadedMetadata={(event) => {
            const element = event.currentTarget;
            const from = readVideoPositions(courseSlug)[lessonSlug]?.ms ?? 0;
            // A video stopped in its last second starts over.
            if (from > 0 && from < element.duration * 1_000 - 1_000) element.currentTime = from / 1_000;
            savedAt.current = from;
          }}
          onTimeUpdate={(event) => {
            const element = event.currentTarget;
            if (!element.paused && Math.abs(element.currentTime * 1_000 - savedAt.current) >= SAVE_EVERY_MS) save(element);
          }}
          onPause={(event) => {
            if (!event.currentTarget.ended) save(event.currentTarget);
          }}
          onEnded={() => writeVideoPosition(courseSlug, lessonSlug, null)}
          onError={() => setState("error")}
        />
      </div>
    );
  }

  const from = position ? clock(position) : null;
  return (
    <div className="lesson-video" data-testid="lesson-video" data-state="cover">
      <button
        type="button"
        className="lesson-video-cover"
        onClick={play}
        aria-label={from
          ? t("courses.watchVideoFrom", { title, duration, size, position: from })
          : t("courses.watchVideo", { title, duration, size })}
      >
        {/* eslint-disable-next-line @next/next/no-img-element -- a ready 16:9 WebP from the media host */}
        <img
          ref={cover}
          src={video.poster.small_url}
          srcSet={`${video.poster.small_url} 640w, ${video.poster.url} 1280w`}
          sizes="(max-width: 900px) 100vw, 880px"
          width={video.poster.width}
          height={video.poster.height}
          alt=""
          fetchPriority="high"
        />
        {from ? (
          <span className="lesson-video-chip lesson-video-resume" aria-hidden="true">
            {t("courses.resumeFrom", { position: from })}
          </span>
        ) : null}
        <span className="lesson-video-chip lesson-video-meta" aria-hidden="true">{duration} · {size}</span>
        <span className="lesson-video-play" aria-hidden="true">
          <svg width="28" height="28" viewBox="0 0 24 24"><path d="M7 4.5v15l12-7.5z" fill="currentColor" /></svg>
        </span>
      </button>
    </div>
  );
}
