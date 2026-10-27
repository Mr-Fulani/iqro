"use client";

import { useEffect, useRef } from "react";
import type { CSSProperties } from "react";
import styles from "./PlayerEqualizer.module.css";

// Ported from _EqualizerPainter in clients/iqro_mobile/lib/features/audio/player_screen.dart.
// Taller in the middle, like the audio quality icon.
const ENVELOPE = [0.44, 0.64, 0.84, 0.7, 1, 0.7, 0.84, 0.64, 0.44];
const LOOP_MS = 3600;
const FRAMES = 72;
// The opacity transition in PlayerEqualizer.module.css.
const FADE_MS = 400;

function swayFrames(bar: number): Keyframe[] {
  return Array.from({ length: FRAMES + 1 }, (_, frame) => {
    const t = (frame / FRAMES) * 2 * Math.PI;
    // Whole cycles per loop keep the repeat seamless.
    const level =
      0.64 +
      0.22 * Math.sin(t * 3 + bar * 1.7) +
      0.1 * Math.sin(t * 5 - bar * 2.3) +
      0.04 * Math.sin(t * 8 + bar * 0.9);
    return { transform: `scaleY(${Math.min(1, Math.max(0.28, level)).toFixed(3)})` };
  });
}

/**
 * Sound bars in the expanded player, as in the app: they fade in and sway while
 * the recitation plays and fade out on pause or while buffering, the sway
 * stopping once they are gone. Transform-only animations run off the main
 * thread. They sway with reduced motion too: the owner wants them, like the
 * chosen video background, whatever the system setting.
 */
export function PlayerEqualizer({ playing }: { playing: boolean }) {
  const rootRef = useRef<HTMLSpanElement>(null);
  const animationsRef = useRef<Animation[]>([]);

  useEffect(() => {
    const root = rootRef.current;
    if (!root) return;
    const animations = Array.from(root.children, (bar, index) =>
      bar.animate(swayFrames(index), { duration: LOOP_MS, iterations: Infinity }),
    );
    animationsRef.current = animations;
    return () => {
      for (const animation of animations) animation.cancel();
      animationsRef.current = [];
    };
  }, []);

  useEffect(() => {
    const animations = animationsRef.current;
    if (playing) {
      for (const animation of animations) animation.play();
      return;
    }
    const timer = window.setTimeout(() => {
      for (const animation of animations) animation.pause();
    }, FADE_MS);
    return () => window.clearTimeout(timer);
  }, [playing]);

  return (
    <span
      ref={rootRef}
      className={playing ? `${styles.equalizer} ${styles.playing}` : styles.equalizer}
      aria-hidden="true"
      data-testid="player-equalizer"
    >
      {ENVELOPE.map((height, index) => (
        <span key={index} className={styles.bar} style={{ "--bar-envelope": height } as CSSProperties} />
      ))}
    </span>
  );
}
