"use client";

import { useEffect, useState } from "react";
import { useI18n } from "../lib/i18n-context";
import {
  distanceToKaabaMeters,
  headingFromOrientation,
  KAABA_PROXIMITY_METERS,
  qiblaBearing,
} from "../lib/qibla";

type OrientationEventWithCompass = DeviceOrientationEvent & { webkitCompassHeading?: number };

/**
 * Live heading from the device compass, only where the browser exposes it without a
 * permission prompt (e.g. Chrome on Android). Safari's `requestPermission` flow is skipped.
 */
function useDeviceHeading(): number | null {
  const [heading, setHeading] = useState<number | null>(null);
  useEffect(() => {
    if (typeof window === "undefined" || !("DeviceOrientationEvent" in window)) return;
    const orientationEvent = window.DeviceOrientationEvent as unknown as { requestPermission?: unknown };
    if (typeof orientationEvent.requestPermission === "function") return;
    const handleOrientation = (event: Event) => {
      const next = headingFromOrientation(
        event as OrientationEventWithCompass,
        window.screen.orientation?.angle ?? 0,
      );
      if (next !== null) setHeading(Math.round(next));
    };
    window.addEventListener("deviceorientationabsolute", handleOrientation);
    return () => window.removeEventListener("deviceorientationabsolute", handleOrientation);
  }, []);
  return heading;
}

export function PrayerQibla({ latitude, longitude }: { latitude: number; longitude: number }) {
  const { t, formatNumber } = useI18n();
  const heading = useDeviceHeading();
  const bearing = qiblaBearing(latitude, longitude);
  if (bearing === null) return null;
  // At the Kaaba itself atan2(0, 0) would point north; there is no direction to show.
  const atKaaba = (distanceToKaabaMeters(latitude, longitude) ?? Infinity) <= KAABA_PROXIMITY_METERS;
  // Rounded like the app, so 359.5°–360° reads as 360°.
  const degrees = formatNumber(Math.round(bearing));
  // With a live heading the dial turns so that its north matches the real north.
  const dialRotation = heading === null ? 0 : -heading;

  return (
    <section className="surface prayer-qibla" data-testid="prayer-qibla">
      <div className="prayer-qibla-compass" dir="ltr">
        <svg
          viewBox="0 0 200 200"
          role="img"
          aria-label={atKaaba ? t("prayer.qiblaAtKaaba") : t("prayer.qiblaCompassAria", { degrees })}
        >
          <circle cx="100" cy="100" r="92" className="prayer-qibla-ring" />
          <g transform={`rotate(${dialRotation} 100 100)`} data-testid="prayer-qibla-dial">
            {Array.from({ length: 36 }, (_, index) => (
              <line
                key={index}
                x1="100"
                y1="12"
                x2="100"
                y2={index % 9 === 0 ? 24 : 18}
                className="prayer-qibla-tick"
                transform={`rotate(${index * 10} 100 100)`}
              />
            ))}
            <text x="100" y="40" textAnchor="middle" className="prayer-qibla-north">
              {t("prayer.qiblaNorth")}
            </text>
            {!atKaaba && (
              <g transform={`rotate(${bearing} 100 100)`} data-testid="prayer-qibla-arrow">
                <path d="M100 30 L114 104 L100 94 L86 104 Z" className="prayer-qibla-arrow" />
                <path d="M100 170 L108 106 L100 112 L92 106 Z" className="prayer-qibla-tail" />
                <rect x="93" y="18" width="14" height="14" rx="2" className="prayer-qibla-kaaba" />
              </g>
            )}
          </g>
          {atKaaba ? (
            <rect x="82" y="82" width="36" height="36" rx="4" className="prayer-qibla-kaaba" />
          ) : (
            <circle cx="100" cy="100" r="5" className="prayer-qibla-hub" />
          )}
        </svg>
      </div>
      <div className="prayer-qibla-copy">
        <p className="eyebrow">{t("prayer.qibla")}</p>
        <h2 className="surface-title">{t("prayer.qiblaDirection")}</h2>
        <p className="prayer-qibla-bearing" data-testid="prayer-qibla-bearing">
          {atKaaba ? t("prayer.qiblaAtKaaba") : t("prayer.qiblaBearing", { degrees })}
        </p>
        <p className="kpi-desc">
          {t("prayer.qiblaCoordinates", {
            latitude: formatNumber(latitude, { maximumFractionDigits: 4 }),
            longitude: formatNumber(longitude, { maximumFractionDigits: 4 }),
          })}
        </p>
        {!atKaaba && (
          <p className="kpi-desc">{heading === null ? t("prayer.qiblaNorthHint") : t("prayer.qiblaLiveHint")}</p>
        )}
      </div>
    </section>
  );
}
