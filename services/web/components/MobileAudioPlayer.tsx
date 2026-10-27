"use client";

import { useEffect, useRef, useState } from "react";
import type { CSSProperties, PointerEvent as ReactPointerEvent } from "react";
import { formatClock } from "../lib/audio-content";
import { DEFAULT_RECITER_PORTRAIT } from "../lib/reciter-portraits";
import { useI18n } from "../lib/i18n-context";
import { sheetDragOffset, swipeDismisses } from "../lib/mini-player";
import { playerBackgroundTitle } from "../lib/player-backgrounds";
import { PlayerBackgroundPicker } from "./PlayerBackground";
import { PlayerEqualizer } from "./PlayerEqualizer";
import { ListeningQueuePanel, QueueModeSelect, VariantSelect, queueSurahLabel } from "./ListeningQueue";
import type {
  MobilePlayerEngine,
  MobilePlayerHeaderProps,
  MobilePlayerPartProps,
  MobilePlayerParts,
} from "./SegmentedAudioPlayer";

/*
 * The phone player, as clients/iqro_mobile/lib/features/audio/mini_player.dart and
 * player_screen.dart draw it: a 66 px bar with the portrait, the collapse button,
 * the title and three transport buttons; a full-screen player with the 210 px
 * portrait, the seek bar, five transport buttons and a grid of option tiles.
 * SegmentedAudioPlayer keeps the <audio> element and the playback logic and
 * renders these parts in its slots; lib/audio-player-context loads this module
 * only on phone widths.
 */

// Material rounded icons, 24-unit grid.
const ICON_PATHS = {
  play: "M8 5v14l11-7z",
  pause: "M6 19h4V5H6v14zm8-14v14h4V5h-4z",
  previous: "M6 6h2v12H6zm3.5 6 8.5 6V6z",
  next: "M6 18l8.5-6L6 6v12zM16 6v12h2V6h-2z",
  collapse: "M18 6.41 16.59 5 12 9.58 7.41 5 6 6.41l6 6zM18 13l-1.41-1.41L12 16.17l-4.59-4.58L6 13l6 6z",
  back: "M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z",
  chevron: "M16.59 8.59 12 13.17 7.41 8.59 6 10l6 6 6-6z",
  person: "M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z",
  replay: "M12 5V1L7 6l5 5V7c3.31 0 6 2.69 6 6s-2.69 6-6 6-6-2.69-6-6H4c0 4.42 3.58 8 8 8s8-3.58 8-8-3.58-8-8-8z",
  forward: "M12 5V1l5 5-5 5V7c-3.31 0-6 2.69-6 6s2.69 6 6 6 6-2.69 6-6h2c0 4.42-3.58 8-8 8s-8-3.58-8-8 3.58-8 8-8z",
  speed: "M20.38 8.57l-1.23 1.85a8 8 0 0 1-.22 7.58H5.07A8 8 0 0 1 15.58 6.85l1.85-1.23A10 10 0 0 0 3.35 19a2 2 0 0 0 1.72 1h13.85a2 2 0 0 0 1.74-1 10 10 0 0 0-.27-10.44zm-9.79 6.84a2 2 0 0 0 2.83 0l5.66-8.49-8.49 5.66a2 2 0 0 0 0 2.83z",
  timer: "M15 1H9v2h6V1zm-4 13h2V8h-2v6zm8.03-6.61 1.42-1.42c-.43-.51-.9-.99-1.41-1.41l-1.42 1.42A8.962 8.962 0 0 0 12 4c-4.97 0-9 4.03-9 9s4.02 9 9 9 9-4.03 9-9c0-2.12-.74-4.07-1.97-5.61zM12 20c-3.87 0-7-3.13-7-7s3.13-7 7-7 7 3.13 7 7-3.13 7-7 7z",
  layers: "M11.99 18.54l-7.37-5.73L3 14.07l9 7 9-7-1.63-1.27-7.38 5.74zM12 16l7.36-5.73L21 9l-9-7-9 7 1.63 1.27L12 16zm0-11.47L17.74 9 12 13.47 6.26 9 12 4.53z",
  repeat: "M7 7h10v3l4-4-4-4v3H5v6h2V7zm10 10H7v-3l-4 4 4 4v-3h12v-6h-2v4z",
  pauseBetween: "M9 16h2V8H9v8zm3-14C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8zm1-4h2V8h-2v8z",
  queue: "M3 6h12v2H3zm0 5h12v2H3zm0 5h8v2H3zm13-1v6l5-3z",
  afterSurah: "M12 4V1L8 5l4 4V6c3.31 0 6 2.69 6 6 0 1.01-.25 1.97-.7 2.8l1.46 1.46A7.93 7.93 0 0 0 20 12c0-4.42-3.58-8-8-8zm0 14c-3.31 0-6-2.69-6-6 0-1.01.25-1.97.7-2.8L5.24 7.74A7.93 7.93 0 0 0 4 12c0 4.42 3.58 8 8 8v3l4-4-4-4v3z",
  wallpaper: "M4 4h7V2H4c-1.1 0-2 .9-2 2v7h2V4zm6 9-4 5h12l-3-4-2.03 2.71L10 13zm7-4.5c0-.83-.67-1.5-1.5-1.5S14 7.67 14 8.5s.67 1.5 1.5 1.5S17 9.33 17 8.5zM20 2h-7v2h7v7h2V4c0-1.1-.9-2-2-2zm0 18h-7v2h7c1.1 0 2-.9 2-2v-7h-2v7zM4 13H2v7c0 1.1.9 2 2 2h7v-2H4v-7z",
} as const;

type IconName = keyof typeof ICON_PATHS;

/** Directional icons flip with the reading direction, as Flutter's matchTextDirection does. */
function Icon({ name, size, directional = false, label }: { name: IconName; size: number; directional?: boolean; label?: string }) {
  return (
    <svg className="mobile-player-icon" width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <g className={directional ? "is-directional" : undefined}><path d={ICON_PATHS[name]} /></g>
      {label && (
        <text x="12" y="15.4" textAnchor="middle" fontSize="7.2" fontWeight="700" fill="currentColor">{label}</text>
      )}
    </svg>
  );
}

function initialsOf(name: string): string {
  return name.trim().split(/\s+/).filter(Boolean).slice(0, 2)
    .map((part) => Array.from(part)[0] || "").join("").toLocaleUpperCase();
}

/**
 * The reciter's portrait in the app's framed circle, the default figure when there is none;
 * initials or a person only when even that does not load.
 */
function PlayerArtwork({ url, name, size, selected = false }: { url: string | null; name?: string; size: number; selected?: boolean }) {
  const [failed, setFailed] = useState<readonly string[]>([]);
  useEffect(() => setFailed([]), [url]);
  const src = [url, DEFAULT_RECITER_PORTRAIT].find(
    (candidate): candidate is string => Boolean(candidate) && !failed.includes(candidate!),
  );
  const initials = name ? initialsOf(name) : "";
  return (
    <span
      className={`mobile-player-artwork${selected ? " is-selected" : ""}`}
      style={{ "--artwork-size": `${size}px` } as CSSProperties}
      aria-hidden="true"
    >
      {src ? (
        // eslint-disable-next-line @next/next/no-img-element -- static WebP portraits and admin CDN URLs, already sized for this slot.
        <img
          src={src}
          alt=""
          width={size}
          height={size}
          decoding="async"
          onError={() => setFailed((current) => [...current, src])}
        />
      ) : (
        <span className="mobile-player-artwork-fallback">
          {initials || <Icon name="person" size={Math.round(size * 0.48)} />}
        </span>
      )}
    </span>
  );
}

function Summary({ engine, mobile }: MobilePlayerPartProps) {
  const { t } = useI18n();
  const { request, activeAyah } = engine;
  const title = request ? engine.title : t("player.listenTitle");
  const artist = request?.artist || t("player.chooseRecording");
  const problem = mobile.surah.error ?? engine.error;

  if (engine.presentation === "mini") {
    return (
      <div className="mobile-player-summary">
        <button
          type="button"
          className="mobile-player-open"
          onClick={mobile.onOpen}
          disabled={!request}
          aria-label={t("player.openFull")}
        >
          <PlayerArtwork url={mobile.artworkUrl} name={request?.artist} size={44} />
          <span className="mobile-player-titles">
            <strong>{title}</strong>
            <span className={problem ? "is-error" : undefined}>{problem ?? artist}</span>
          </span>
        </button>
        <button type="button" className="mobile-player-collapse" onClick={mobile.onCollapse} aria-label={t("player.hideBar")}>
          <Icon name="collapse" size={24} />
        </button>
        <span className="sr-only" aria-live="polite">{engine.statusLabel}</span>
      </div>
    );
  }

  const reciter = mobile.reciterControls;
  return (
    <div className="mobile-player-summary is-full">
      <PlayerArtwork url={mobile.artworkUrl} name={request?.artist} size={210} selected />
      <div className="mobile-player-copy" inert={mobile.controlsHidden || undefined}>
      <p className="eyebrow mobile-player-eyebrow">
        {/* Some recordings have no ayah timings yet; a dash that never changes read as a frozen counter. */}
        {request && request.segments.length === 0
          ? t("player.surahUntimed", { surah: request.track.surah_number ?? "—" })
          : t("player.surahAyah", { surah: request?.track.surah_number ?? "—", ayah: activeAyah?.ayah_number ?? "—" })}
      </p>
      <h2 className="mobile-player-title">{title}</h2>
      {reciter && reciter.options.length > 0 ? (
        <span className="mobile-player-reciter">
          <select
            value={reciter.value}
            onChange={(event) => reciter.onChange(event.target.value)}
            disabled={reciter.disabled}
            aria-label={t("player.reciterSwitch")}
          >
            {reciter.options.map((option) => (
              <option key={option.value} value={option.value}>{option.label}</option>
            ))}
          </select>
          <Icon name="chevron" size={22} />
        </span>
      ) : (
        <p className="mobile-player-artist">{artist}</p>
      )}
      {mobile.queue && (
        <span className="mobile-player-variant">
          <VariantSelect controls={mobile.queue} />
          <Icon name="chevron" size={18} />
        </span>
      )}
      <p className={`mobile-player-status${problem ? " is-error" : ""}`} aria-live="polite">{problem ?? engine.statusLabel}</p>
      </div>
    </div>
  );
}

const SEEK_COMMIT_DELAY_MS = 120;

/** The timeline of the active range; the sound follows once the thumb rests. */
function SeekBar({ engine }: { engine: MobilePlayerEngine }) {
  const { t } = useI18n();
  const { audio, plan, request } = engine;
  const [position, setPosition] = useState(0);
  const [preview, setPreview] = useState<number | null>(null);
  const commitTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const startMs = plan?.startMs ?? 0;
  const duration = Math.max(0, (plan?.endMs ?? 0) - startMs);

  useEffect(() => {
    if (!audio) return;
    const sync = () => setPosition(Math.round(audio.currentTime * 1000));
    sync();
    const events = ["timeupdate", "seeked", "loadedmetadata", "emptied", "play", "pause"];
    for (const type of events) audio.addEventListener(type, sync);
    return () => {
      for (const type of events) audio.removeEventListener(type, sync);
    };
  }, [audio, plan]);

  useEffect(() => () => {
    if (commitTimer.current !== null) clearTimeout(commitTimer.current);
  }, []);

  const value = Math.min(duration, Math.max(0, (preview ?? position) - startMs));
  const disabled = !request || duration <= 0;
  const commit = (relativeMs: number) => {
    const absolute = startMs + relativeMs;
    setPreview(null);
    setPosition(absolute);
    engine.seekToMs(absolute);
  };

  return (
    <div className="mobile-player-seek" style={{ "--seek-progress": `${duration > 0 ? (value / duration) * 100 : 0}%` } as CSSProperties}>
      <input
        type="range"
        min={0}
        max={duration || 1}
        step={250}
        value={value}
        disabled={disabled}
        aria-label={t("player.seek")}
        aria-valuetext={`${formatClock(value)} / ${formatClock(duration)}`}
        onChange={(event) => {
          const relativeMs = Number(event.target.value);
          setPreview(startMs + relativeMs);
          if (commitTimer.current !== null) clearTimeout(commitTimer.current);
          commitTimer.current = setTimeout(() => {
            commitTimer.current = null;
            commit(relativeMs);
          }, SEEK_COMMIT_DELAY_MS);
        }}
      />
      <div className="mobile-player-times" aria-hidden="true">
        <span>{formatClock(value)}</span>
        <span>{formatClock(duration)}</span>
      </div>
    </div>
  );
}

function Transport({ engine, mobile }: MobilePlayerPartProps) {
  const { t } = useI18n();
  const { request, isPlaying } = engine;
  const changing = mobile.surah.busy;
  const spinning = changing || (mobile.buffering && isPlaying);
  const playLabel = isPlaying ? t("player.pausePlayback") : t("player.play");
  const full = engine.presentation === "full";

  const previousButton = (
    <button
      type="button"
      className="mobile-player-control"
      aria-label={t("player.previousSurah")}
      onClick={() => mobile.surah.change(-1)}
      disabled={!request || changing || mobile.surah.previous === null}
    >
      <Icon name="previous" size={23} directional />
    </button>
  );
  const nextButton = (
    <button
      type="button"
      className="mobile-player-control"
      aria-label={t("player.nextSurah")}
      onClick={() => mobile.surah.change(1)}
      disabled={!request || changing || mobile.surah.next === null}
    >
      <Icon name="next" size={23} directional />
    </button>
  );
  const playButton = (
    <button
      type="button"
      className={`mobile-player-control is-play${full ? " is-large" : ""}`}
      aria-label={playLabel}
      onClick={engine.togglePlayback}
      disabled={!request || changing}
    >
      {spinning
        ? <span className="mobile-player-spinner" aria-hidden="true" />
        : <Icon name={isPlaying ? "pause" : "play"} size={full ? 38 : 25} directional />}
    </button>
  );

  if (!full) {
    return (
      <div className="mobile-player-transport">
        {previousButton}
        {playButton}
        {nextButton}
      </div>
    );
  }

  return (
    <div className="mobile-player-transport is-full">
      {mobile.equalizer.enabled && <PlayerEqualizer playing={mobile.equalizer.playing} />}
      <div className="mobile-player-controls" inert={mobile.controlsHidden || undefined}>
      <SeekBar engine={engine} />
      <div className="mobile-player-buttons">
        <button type="button" className="mobile-player-control" aria-label={t("player.replay10")} onClick={() => engine.seekBy(-10)} disabled={!request}>
          <Icon name="replay" size={28} label="10" directional />
        </button>
        {previousButton}
        {playButton}
        {nextButton}
        <button type="button" className="mobile-player-control" aria-label={t("player.forward10")} onClick={() => engine.seekBy(10)} disabled={!request}>
          <Icon name="forward" size={28} label="10" directional />
        </button>
      </div>
      {mobile.queue && <UpNext mobile={mobile} />}
      </div>
    </div>
  );
}

/** "Up next" under the buttons; it opens the queue over the full player. */
function UpNext({ mobile }: { mobile: MobilePlayerPartProps["mobile"] }) {
  const { t, locale } = useI18n();
  const [open, setOpen] = useState(false);
  const queue = mobile.queue;
  if (!queue) return null;
  return (
    <>
      <button type="button" className="mobile-player-up-next" aria-expanded={open} onClick={() => setOpen(true)}>
        <Icon name="queue" size={22} />
        <span className="mobile-player-up-next-copy">
          <span>{queue.upNext !== null ? t("player.upNext") : t("player.afterSurah")}</span>
          <strong>
            {queue.upNext !== null
              ? queueSurahLabel(queue, queue.upNext, locale, t)
              : t("player.queueMode.stop")}
          </strong>
        </span>
        <span className="mobile-player-up-next-action">{t("player.queue")}</span>
      </button>
      {open && (
        <div className="mobile-player-queue-sheet">
          <ListeningQueuePanel controls={queue} onClose={() => setOpen(false)} className="is-sheet" />
        </div>
      )}
    </>
  );
}

const TILE_ICONS = { speed: "speed", sleep: "timer", repeat: "repeat", pause: "pauseBetween" } as const;
// The app's order: after the surah, speed, sleep timer, range, repeat, (audio quality,) background.
const TILE_ORDER = ["queue", "speed", "sleep", "range", "repeat", "pause", "background"] as const;

function Options({ engine, mobile }: MobilePlayerPartProps) {
  const { t, locale } = useI18n();
  const [rangeOpen, setRangeOpen] = useState(false);
  const settings = new Map(engine.settings.map((setting) => [setting.key, setting]));

  return (
    <div className="mobile-player-options" inert={mobile.controlsHidden || undefined}>
      <div className="mobile-player-tiles">
        {TILE_ORDER.map((key) => {
          if (key === "queue") {
            return mobile.queue ? (
              <label key={key} className="mobile-player-tile">
                <Icon name="afterSurah" size={24} />
                <span className="mobile-player-tile-label">{t("player.afterSurah")}</span>
                <QueueModeSelect controls={mobile.queue} />
              </label>
            ) : null;
          }
          if (key === "range") {
            return (
              <button
                key={key}
                type="button"
                className="mobile-player-tile"
                aria-expanded={rangeOpen}
                onClick={() => setRangeOpen((current) => !current)}
                disabled={engine.range.disabled}
              >
                <Icon name="layers" size={24} />
                <span className="mobile-player-tile-label">{t("player.range")}</span>
                <strong className="mobile-player-tile-value">{engine.range.label ?? "—"}</strong>
              </button>
            );
          }
          if (key === "background") {
            return (
              <PlayerBackgroundPicker
                key={key}
                options={mobile.background.options}
                value={mobile.background.value.id}
                onChange={mobile.background.onChange}
                tile={{ icon: <Icon name="wallpaper" size={24} />, value: playerBackgroundTitle(mobile.background.value, locale) }}
              />
            );
          }
          const setting = settings.get(key);
          if (!setting) return null;
          return (
            <label key={key} className="mobile-player-tile">
              <Icon name={TILE_ICONS[key]} size={24} />
              <span className="mobile-player-tile-label">{setting.label}</span>
              {setting.control}
              {setting.note && <span className="mobile-player-tile-note">{setting.note}</span>}
            </label>
          );
        })}
      </div>
      {rangeOpen && (
        <div className="segmented-audio-range mobile-player-range" aria-label={t("player.rangeAria")}>
          {engine.range.start}
          {engine.range.end}
          <button className="btn btn-primary btn-sm" type="button" onClick={engine.range.play} disabled={engine.range.disabled}>
            {t("player.playRange")}
          </button>
        </div>
      )}
    </div>
  );
}

type Drag = { pointerId: number; startY: number; startedAt: number };

/** The app bar of the full player; dragging it down closes the sheet. */
function FullHeader({ subtitle, hidden, onClose, onDragOffset, onDismiss }: MobilePlayerHeaderProps) {
  const { t } = useI18n();
  const backRef = useRef<HTMLButtonElement>(null);
  const drag = useRef<Drag | null>(null);

  useEffect(() => {
    backRef.current?.focus({ preventScroll: true });
  }, []);

  const finish = (event: ReactPointerEvent<HTMLElement>) => {
    const current = drag.current;
    if (!current || event.pointerId !== current.pointerId) return;
    drag.current = null;
    const deltaY = event.clientY - current.startY;
    const durationMs = performance.now() - current.startedAt;
    if (swipeDismisses({ deltaY, durationMs })) onDismiss();
    else onDragOffset(0);
  };

  return (
    <header
      className="mobile-player-full-head"
      inert={hidden || undefined}
      onPointerDown={(event) => {
        if (event.button !== 0 || (event.target as Element).closest("button")) return;
        drag.current = { pointerId: event.pointerId, startY: event.clientY, startedAt: performance.now() };
        try {
          event.currentTarget.setPointerCapture(event.pointerId);
        } catch {
          // Synthetic pointers have no capture.
        }
      }}
      onPointerMove={(event) => {
        const current = drag.current;
        if (!current || event.pointerId !== current.pointerId) return;
        onDragOffset(sheetDragOffset(event.clientY - current.startY));
      }}
      onPointerUp={finish}
      onPointerCancel={finish}
    >
      <span className="mobile-player-grabber" aria-hidden="true" />
      <button ref={backRef} type="button" className="mobile-player-back" aria-label={t("common.back")} onClick={onClose}>
        <Icon name="back" size={24} directional />
      </button>
      <div className="mobile-player-full-title">
        <strong>{t("player.nowPlaying")}</strong>
        {subtitle && <span>{subtitle}</span>}
      </div>
    </header>
  );
}

/** The 60 px round button the bar collapses to; a tap brings the bar back. */
function CollapsedButton({ playing, onExpand }: { playing: boolean; onExpand: () => void }) {
  const { t } = useI18n();
  return (
    <button type="button" className="mobile-player-fab" aria-label={t("player.showBar")} onClick={onExpand}>
      <Icon name={playing ? "pause" : "play"} size={playing ? 34 : 38} directional />
    </button>
  );
}

export const mobilePlayerParts: MobilePlayerParts = { Summary, Transport, Options, FullHeader, CollapsedButton };
