"use client";

import { useId, useState } from "react";
import type { SyntheticEvent } from "react";
import { useI18n } from "../lib/i18n-context";
import {
  PLAYER_BACKGROUND_SCRIM,
  playerBackgroundTitle,
} from "../lib/player-backgrounds";
import type { PlayerBackground } from "../lib/player-backgrounds";

function markLoaded(event: SyntheticEvent<HTMLImageElement>) {
  event.currentTarget.dataset.loaded = "true";
}

/** The chosen image behind the expanded player, under a dark scrim for legible text. */
export function PlayerBackdrop({ background }: { background: PlayerBackground }) {
  if (!background.image) return null;
  return (
    <div className="global-audio-player-backdrop" aria-hidden="true">
      {/* eslint-disable-next-line @next/next/no-img-element -- static WebP files and admin CDN URLs are already sized for this slot. */}
      <img
        key={background.id}
        src={background.image.src}
        srcSet={background.image.srcSet}
        sizes="min(1160px, 100vw)"
        alt=""
        loading="lazy"
        decoding="async"
        onLoad={markLoaded}
      />
      <span className="global-audio-player-scrim" style={{ backgroundImage: PLAYER_BACKGROUND_SCRIM }} />
    </div>
  );
}

export function PlayerBackgroundPicker({
  options,
  value,
  onChange,
}: {
  options: readonly PlayerBackground[];
  value: string;
  onChange: (id: string) => void;
}) {
  const { locale, t } = useI18n();
  const [open, setOpen] = useState(false);
  const panelId = useId();
  const label = t("player.background");

  return (
    <div className="player-background-picker">
      <button
        className="btn btn-secondary btn-sm player-background-toggle"
        type="button"
        aria-expanded={open}
        aria-controls={panelId}
        title={label}
        onClick={() => setOpen((current) => !current)}
      >
        <span aria-hidden="true">🖼</span>
        <span className="player-background-toggle-label">{label}</span>
      </button>
      {open && (
        <fieldset className="player-background-options" id={panelId}>
          <legend className="sr-only">{label}</legend>
          {options.map((option) => {
            const title = playerBackgroundTitle(option, locale);
            return (
              <label key={option.id} className="player-background-option">
                <input
                  className="sr-only"
                  type="radio"
                  name={`${panelId}-choice`}
                  value={option.id}
                  checked={option.id === value}
                  onChange={() => onChange(option.id)}
                />
                <span className="player-background-thumb" aria-hidden="true">
                  {option.image && (
                    // eslint-disable-next-line @next/next/no-img-element -- thumbnails are pre-sized WebP files.
                    <img
                      src={option.image.thumbnailSrc}
                      srcSet={option.image.srcSet}
                      sizes="96px"
                      alt=""
                      width={96}
                      height={64}
                      loading="lazy"
                      decoding="async"
                    />
                  )}
                </span>
                <span className="player-background-name">{title}</span>
              </label>
            );
          })}
        </fieldset>
      )}
    </div>
  );
}
