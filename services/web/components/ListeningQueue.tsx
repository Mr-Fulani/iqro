"use client";

import { useEffect, useId, useRef } from "react";
import { useI18n } from "../lib/i18n-context";
import type { Locale } from "../lib/i18n";
import { QUEUE_MODES, SURAH_COUNT, currentVariant, isQueueMode, queueRows } from "../lib/listening-queue";
import type { QueueMode } from "../lib/listening-queue";
import { surahName } from "../lib/quran-content";
import type { ListeningQueueControls } from "../lib/use-listening-queue";
import { SurahNameArt } from "./SurahNameArt";

/*
 * The queue controls of the global player (docs/audio-listening-queue.md):
 * the "after the surah" mode, the switch between a reciter's recordings and
 * the list of held surahs. The desktop dock shows them as a row under the
 * player; the phone player (MobileAudioPlayer) places the same pieces in its
 * full screen, as the app's player_screen.dart does.
 */

const MODE_KEYS = {
  stop: "player.queueMode.stop",
  next: "player.queueMode.next",
  loop: "player.queueMode.loop",
} as const;

const ICONS = {
  previous: "M6 6h2v12H6zm3.5 6 8.5 6V6z",
  next: "M6 18l8.5-6L6 6v12zM16 6v12h2V6h-2z",
  queue: "M3 6h12v2H3zm0 5h12v2H3zm0 5h8v2H3zm13-1v6l5-3z",
  playing: "M4 10h3v4H4zM10.5 6h3v12h-3zM17 8h3v8h-3z",
  play: "M8 5v14l11-7z",
} as const;

function QueueIcon({ name, size = 20 }: { name: keyof typeof ICONS; size?: number }) {
  return (
    <svg className="listening-queue-icon" width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
      <path d={ICONS[name]} />
    </svg>
  );
}

/** "36 · Ya-Sin", or "Surah 36" until the edition's names arrive. */
export function queueSurahLabel(
  controls: ListeningQueueControls,
  surah: number,
  locale: Locale,
  t: ReturnType<typeof useI18n>["t"],
): string {
  const known = controls.surahs.get(surah);
  return known
    ? t("player.queueSurah", { surah, name: surahName(known, locale) })
    : t("common.surah", { surah });
}

export function QueueModeSelect({ controls, id }: { controls: ListeningQueueControls; id?: string }) {
  const { t } = useI18n();
  return (
    <select
      id={id}
      className="listening-queue-mode-select"
      value={controls.mode}
      aria-label={t("player.afterSurah")}
      onChange={(event) => {
        if (isQueueMode(event.target.value)) controls.setMode(event.target.value);
      }}
    >
      {QUEUE_MODES.map((mode) => <option key={mode} value={mode}>{t(MODE_KEYS[mode])}</option>)}
    </select>
  );
}

/** The reciter's recordings; nothing to choose with only one. */
export function VariantSelect({ controls, className }: { controls: ListeningQueueControls; className?: string }) {
  const { t } = useI18n();
  const { variants, variantId } = controls.queue;
  if (variants.length < 2) return null;
  return (
    <select
      className={className}
      value={variantId}
      aria-label={t("player.variant")}
      disabled={controls.busy}
      onChange={(event) => controls.chooseVariant(event.target.value)}
    >
      {variants.map((variant) => <option key={variant.id} value={variant.id}>{variant.label}</option>)}
    </select>
  );
}

/** The held surahs in order, missing runs folded, the playing one marked. */
export function ListeningQueuePanel({
  controls,
  onClose,
  className = "",
}: {
  controls: ListeningQueueControls;
  onClose: () => void;
  className?: string;
}) {
  const { t, locale } = useI18n();
  const titleId = useId();
  const listRef = useRef<HTMLOListElement>(null);
  const closeRef = useRef<HTMLButtonElement>(null);
  const variant = currentVariant(controls.queue);
  const rows = queueRows(controls.held);
  const incomplete = controls.held.length < SURAH_COUNT;

  // The playing surah is in view when the list opens, and the keyboard starts inside it.
  useEffect(() => {
    const list = listRef.current;
    const playing = list?.querySelector<HTMLElement>("[aria-current='true']");
    // The list scrolls itself only: the page and the dock stay where they are.
    if (list && playing) list.scrollTop = playing.offsetTop - (list.clientHeight - playing.offsetHeight) / 2;
    closeRef.current?.focus({ preventScroll: true });
  }, []);

  return (
    <section
      className={`listening-queue-panel ${className}`.trim()}
      aria-labelledby={titleId}
      data-testid="listening-queue"
      onKeyDown={(event) => {
        // Escape closes the list first; the full player stays open.
        if (event.key !== "Escape") return;
        event.preventDefault();
        onClose();
      }}
    >
      <header className="listening-queue-head">
        <div>
          <h2 id={titleId}>{t("player.queue")}</h2>
          <p>{[controls.queue.artist, variant?.label].filter(Boolean).join(" · ")}</p>
        </div>
        {incomplete && (
          <span className="listening-queue-held">{t("player.heldSurahs", { count: controls.held.length })}</span>
        )}
        <button ref={closeRef} type="button" className="listening-queue-close" onClick={onClose} aria-label={t("player.closeQueue")}>
          <svg width="20" height="20" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true">
            <path d="M19 6.41 17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z" />
          </svg>
        </button>
      </header>

      <fieldset className="listening-queue-modes">
        <legend>{t("player.afterSurah")}</legend>
        <div className="listening-queue-segments">
          {QUEUE_MODES.map((mode: QueueMode) => (
            <button
              key={mode}
              type="button"
              aria-pressed={controls.mode === mode}
              onClick={() => controls.setMode(mode)}
            >
              {t(MODE_KEYS[mode])}
            </button>
          ))}
        </div>
        <p>{t("player.queueModeHint")}</p>
      </fieldset>

      <div className="listening-queue-actions">
        <button type="button" className="listening-queue-whole" onClick={controls.playFromStart} disabled={controls.busy}>
          <QueueIcon name="play" size={18} />
          {t("player.wholeQuranFromStart")}
        </button>
        <VariantSelect controls={controls} className="listening-queue-variant" />
      </div>

      <ol ref={listRef} className="listening-queue-list">
        {rows.map((row) => {
          if (row.kind === "gap") {
            return (
              <li key={`gap-${row.from}`} className="listening-queue-gap">
                <span>
                  {row.from === row.to
                    ? t("player.missingSurah", { surah: row.from })
                    : t("player.missingSurahs", { from: row.from, to: row.to })}
                </span>
              </li>
            );
          }
          const playing = row.surah === controls.current;
          const surah = controls.surahs.get(row.surah);
          return (
            <li key={row.surah}>
              <button
                type="button"
                className="listening-queue-row"
                aria-current={playing ? "true" : undefined}
                onClick={() => controls.playSurah(row.surah)}
                disabled={controls.busy}
              >
                <span className="listening-queue-number">
                  {playing ? <QueueIcon name="playing" size={18} /> : row.surah}
                </span>
                <span className="listening-queue-name">
                  {surah ? surahName(surah, locale) : t("common.surah", { surah: row.surah })}
                </span>
                {/* The Mushaf's lettering needs only the number, so it shows before the names arrive. */}
                <SurahNameArt surah={row.surah} fallback={surah?.name_ar ?? ""} className="listening-queue-arabic" />
              </button>
            </li>
          );
        })}
      </ol>
    </section>
  );
}

/**
 * The desktop dock's queue controls. Compact, the dock's action cell gets the
 * previous and next surah and the queue button; expanded, a row of its own
 * adds what plays next, the mode and the recording. The list itself is a
 * full-width part of the dock (ListeningQueuePanel).
 */
export function ListeningQueueBar({
  controls,
  compact,
  open,
  onToggle,
  panelId,
}: {
  controls: ListeningQueueControls;
  compact: boolean;
  open: boolean;
  onToggle: () => void;
  panelId: string;
}) {
  const { t, locale } = useI18n();
  const modeId = useId();

  const steps = (
    <>
      <button
        type="button"
        className="btn btn-secondary btn-sm listening-queue-step"
        aria-label={t("player.previousSurah")}
        title={t("player.previousSurah")}
        onClick={() => controls.changeSurah(-1)}
        disabled={controls.busy || controls.previous === null}
      >
        <QueueIcon name="previous" />
      </button>
      <button
        type="button"
        className="btn btn-secondary btn-sm listening-queue-step"
        aria-label={t("player.nextSurah")}
        title={t("player.nextSurah")}
        onClick={() => controls.changeSurah(1)}
        disabled={controls.busy || controls.next === null}
      >
        <QueueIcon name="next" />
      </button>
    </>
  );
  const toggle = (
    <button
      type="button"
      className={`btn btn-sm listening-queue-toggle ${open ? "btn-primary" : "btn-secondary"}`}
      aria-expanded={open}
      aria-controls={panelId}
      aria-label={compact ? t("player.queue") : undefined}
      title={compact ? t("player.queue") : undefined}
      onClick={onToggle}
    >
      <QueueIcon name="queue" size={18} />
      {!compact && t("player.queue")}
    </button>
  );

  if (compact) {
    return (
      <>
        {steps}
        {toggle}
      </>
    );
  }

  return (
    <div className="global-audio-player-queue listening-queue-bar">
      {steps}
      <span className="listening-queue-up-next" aria-live="polite">
        {controls.error ?? (controls.upNext !== null
          ? `${t("player.upNext")}: ${queueSurahLabel(controls, controls.upNext, locale, t)}`
          : null)}
      </span>
      <label className="listening-queue-mode" htmlFor={modeId}>
        <span>{t("player.afterSurah")}</span>
        <QueueModeSelect controls={controls} id={modeId} />
      </label>
      <VariantSelect controls={controls} className="listening-queue-variant" />
      {toggle}
    </div>
  );
}
