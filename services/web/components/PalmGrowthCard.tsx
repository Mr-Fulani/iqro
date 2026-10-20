"use client";

import { useId, useState } from "react";
import { useI18n } from "../lib/i18n-context";
import { type PalmGrowth, palmStageImage } from "../lib/palm-growth";

// The app's resting tint (palm_growth_view.dart): a resting palm keeps its
// growth; the photograph only softens its colour.
const RESTING_MATRIX = "0.70 0.25 0.05 0 0 0.15 0.80 0.05 0 0 0.15 0.25 0.60 0 0 0 0 0 1 0";
const RESTING_FILTER_ID = "palm-resting-tint";

/**
 * The date palm in the Today card: the stage's photograph, its name and the
 * way to the next stage. The explanation waits behind the info button, as in
 * the app. A new stage grows in; reduced motion keeps it still (CSS).
 */
export function PalmGrowthCard({ growth }: { growth: PalmGrowth }) {
  const { t } = useI18n();
  const [infoOpen, setInfoOpen] = useState(false);
  const infoId = useId();
  // Only a stage reached while the card is open animates, like the app's
  // AnimatedSwitcher; the first stage shown simply appears.
  const [shownStage, setShownStage] = useState(growth.stage);
  const [grew, setGrew] = useState(false);
  if (shownStage !== growth.stage) {
    setShownStage(growth.stage);
    setGrew(true);
  }

  const image = palmStageImage(growth.stage);
  const resting = growth.mood === "resting";
  const next = growth.nextStage;
  const nextLabel = next
    ? t("palm.nextStage", { stage: t(`palm.stage.${next}`) })
    : t("palm.fullyGrown");
  const percent = Math.round(growth.progressToNext * 100);

  return (
    <figure
      className="today-palm"
      data-testid="palm-growth"
      data-stage={growth.stage}
      data-mood={growth.mood}
      aria-label={t("palm.title")}
    >
      {resting && (
        <svg className="today-palm-filter" aria-hidden="true" focusable="false">
          <filter id={RESTING_FILTER_ID} colorInterpolationFilters="sRGB">
            <feColorMatrix type="matrix" values={RESTING_MATRIX} />
          </filter>
        </svg>
      )}
      {/* eslint-disable-next-line @next/next/no-img-element -- static WebP files are already sized for this card. */}
      <img
        key={growth.stage}
        className={grew ? "today-palm-photo is-growing" : "today-palm-photo"}
        src={image.src}
        srcSet={image.srcSet}
        sizes="(min-width: 1100px) 320px, min(420px, calc(100vw - 60px))"
        width={960}
        height={700}
        alt=""
        loading="lazy"
        decoding="async"
        style={resting ? { filter: `url(#${RESTING_FILTER_ID})` } : undefined}
      />
      <figcaption className="today-palm-copy">
        <span className="today-palm-head">
          <strong>{t(`palm.stage.${growth.stage}`)}</strong>
          <button
            type="button"
            className="today-palm-info-toggle"
            aria-label={t("palm.about")}
            aria-expanded={infoOpen}
            aria-controls={infoId}
            onClick={() => setInfoOpen((open) => !open)}
          >
            i
          </button>
        </span>
        <span className="today-palm-next">
          <span>{nextLabel}</span>
          {next && (
            <span
              className="today-palm-track"
              role="progressbar"
              aria-valuemin={0}
              aria-valuemax={100}
              aria-valuenow={percent}
              aria-label={nextLabel}
            >
              <span style={{ width: `${percent}%` }} />
            </span>
          )}
        </span>
        <span id={infoId} className="today-palm-info" hidden={!infoOpen}>
          <span>{t(`palm.mood.${growth.mood}`)}</span>
          <span>{t("palm.howItGrows")}</span>
        </span>
      </figcaption>
    </figure>
  );
}
