"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { useI18n } from "../lib/i18n-context";
import {
  angleDifference,
  compassReadingFromOrientation,
  type CompassReading,
  distanceToKaabaMeters,
  facesQibla,
  headingFromOrientation,
  HeadingSmoother,
  KAABA_PROXIMITY_METERS,
  type OrientationSample,
  qiblaBearing,
} from "../lib/qibla";

type CompassState = "waiting" | "permission" | "live" | "unavailable" | "denied";
type OrientationEventName = "deviceorientationabsolute" | "deviceorientation";
type OrientationPermission = { requestPermission?: () => Promise<PermissionState> };

const screenAngle = () => window.screen.orientation?.angle ?? 0;

/** Best effort, like the app's haptic: Android browsers vibrate only after the user has interacted. */
function pulse() {
  if (navigator.userActivation?.hasBeenActive) navigator.vibrate?.(40);
}

/**
 * Live compass as in the app's Qibla sheet. Android browsers give an absolute orientation
 * without asking; iOS Safari asks once, from a tap on the button. Magnetic headings move to
 * true north with the WMM declination, whose model loads only once a heading arrives.
 */
function useLiveCompass(latitude: number, longitude: number, bearing: number, active: boolean) {
  const [state, setState] = useState<CompassState>("waiting");
  const [eventName, setEventName] = useState<OrientationEventName | null>(null);
  const [wantsDeclination, setWantsDeclination] = useState(false);
  const [declination, setDeclination] = useState<number | null>(null);
  const [heading, setHeading] = useState<number | null>(null);
  const [facing, setFacing] = useState(false);
  const [needsCalibration, setNeedsCalibration] = useState(false);
  const [accuracyKnown, setAccuracyKnown] = useState(false);
  // The sample that arrived before the declination did; kept across the listener's restart.
  const pending = useRef<OrientationSample | null>(null);
  const smoother = useRef<HeadingSmoother | null>(null);
  const facingRef = useRef(false);

  useEffect(() => {
    if (!active) return;
    if (!("DeviceOrientationEvent" in window)) {
      setState("unavailable");
      return;
    }
    const orientation = window.DeviceOrientationEvent as unknown as OrientationPermission;
    if (typeof orientation.requestPermission === "function") {
      setState((current) => (current === "waiting" ? "permission" : current));
      return;
    }
    setEventName("ondeviceorientationabsolute" in window ? "deviceorientationabsolute" : "deviceorientation");
  }, [active]);

  const enable = useCallback(() => {
    const orientation = window.DeviceOrientationEvent as unknown as OrientationPermission;
    // Safari grants motion access only from a user gesture, so the request runs in the click itself.
    orientation.requestPermission?.().then(
      (result) => {
        if (result !== "granted") return setState("denied");
        setState("waiting");
        setEventName("deviceorientation");
      },
      () => setState("denied"),
    );
  }, []);

  useEffect(() => {
    if (!wantsDeclination) return;
    let cancelled = false;
    import("../lib/geomag").then(
      ({ magneticDeclination }) => {
        if (!cancelled) setDeclination(magneticDeclination(latitude, longitude) ?? 0);
      },
      () => {
        if (!cancelled) setState("unavailable");
      },
    );
    return () => {
      cancelled = true;
    };
  }, [wantsDeclination, latitude, longitude]);

  useEffect(() => {
    if (!active || !eventName) return;
    const tracker = (smoother.current ??= new HeadingSmoother());
    let target: CompassReading | null = null;
    let frame: number | null = null;
    let lastTime: number | null = null;

    const step = (now: number) => {
      if (!target) return;
      const value = tracker.step(target.heading, lastTime === null ? 0 : now - lastTime);
      lastTime = now;
      const nextFacing = facesQibla(value, bearing, facingRef.current, target.needsCalibration);
      if (nextFacing && !facingRef.current) pulse();
      facingRef.current = nextFacing;
      setHeading(value);
      setFacing(nextFacing);
      // The dial has caught up; the next sample restarts the loop.
      if (Math.abs(angleDifference(value, target.heading)) < 0.05) {
        frame = null;
        lastTime = null;
      } else {
        frame = requestAnimationFrame(step);
      }
    };

    const apply = (sample: OrientationSample) => {
      if (declination === null) {
        pending.current = sample;
        setWantsDeclination(true);
        return;
      }
      const reading = compassReadingFromOrientation(sample, screenAngle(), declination);
      if (!reading) return;
      target = reading;
      setState("live");
      setNeedsCalibration(reading.needsCalibration);
      setAccuracyKnown(reading.accuracyKnown);
      frame ??= requestAnimationFrame(step);
    };

    const onOrientation = (event: Event) => {
      const sample = event as DeviceOrientationEvent & OrientationSample;
      if (headingFromOrientation(sample) !== null) return apply(sample);
      // Browsers without a compass fire an event with every angle null.
      if (sample.alpha === null && sample.webkitCompassHeading === undefined) {
        setState((current) => (current === "live" ? current : "unavailable"));
      }
    };

    const early = pending.current;
    pending.current = null;
    if (early) apply(early);
    window.addEventListener(eventName, onOrientation);
    return () => {
      window.removeEventListener(eventName, onOrientation);
      if (frame !== null) cancelAnimationFrame(frame);
    };
  }, [active, eventName, declination, bearing]);

  return { state, heading, facing, needsCalibration, accuracyKnown, enable };
}

export function PrayerQibla({ latitude, longitude }: { latitude: number; longitude: number }) {
  const { t, formatNumber } = useI18n();
  const bearing = qiblaBearing(latitude, longitude);
  // At the Kaaba itself atan2(0, 0) would point north; there is no direction to show.
  const atKaaba = (distanceToKaabaMeters(latitude, longitude) ?? Infinity) <= KAABA_PROXIMITY_METERS;
  const compass = useLiveCompass(latitude, longitude, bearing ?? 0, bearing !== null && !atKaaba);
  if (bearing === null) return null;
  // Rounded like the app, so 359.5°–360° reads as 360°.
  const degrees = formatNumber(Math.round(bearing));
  const heading = !atKaaba && compass.state === "live" ? compass.heading : null;
  const live = heading !== null;
  const calibrate = live && compass.needsCalibration;
  const facing = live && compass.facing;
  // With a live heading the dial turns so that its north matches the real north.
  const dialRotation = heading === null ? 0 : -heading;
  let hint = t("prayer.qiblaNorthHint");
  if (calibrate) hint = t("prayer.qiblaCalibrationHint");
  else if (live) hint = t("prayer.qiblaLiveHint");
  else if (compass.state === "unavailable") hint = `${t("prayer.qiblaCompassUnavailable")} ${hint}`;
  else if (compass.state === "denied") hint = `${t("prayer.qiblaCompassDenied")} ${hint}`;

  return (
    <section className={`surface prayer-qibla${facing ? " is-facing" : ""}`} data-testid="prayer-qibla">
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
          {/* A fixed mark at the top shows where the phone points. */}
          {live && <path d="M100 13 L93 0 L107 0 Z" className="prayer-qibla-phone" />}
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
        {live && (
          // Fixed height, so the text below does not jump when the status changes.
          <p className="prayer-qibla-status" aria-live="polite" data-testid="prayer-qibla-status">
            {calibrate ? (
              <span className="is-calibrate">
                <svg viewBox="0 0 24 24" aria-hidden="true">
                  <path d="M18.6 6.62c-1.44 0-2.8.56-3.77 1.53L12 10.66 10.48 12h.01L7.8 14.39c-.64.64-1.49.99-2.4.99-1.87 0-3.39-1.51-3.39-3.38S3.53 8.62 5.4 8.62c.91 0 1.76.35 2.44 1.03l1.13 1 1.51-1.34L9.22 8.2C8.2 7.18 6.84 6.62 5.4 6.62 2.42 6.62 0 9.04 0 12s2.42 5.38 5.4 5.38c1.44 0 2.8-.56 3.77-1.53l2.83-2.5.01.01L13.52 12h-.01l2.69-2.39c.64-.64 1.49-.99 2.4-.99 1.87 0 3.39 1.51 3.39 3.38s-1.52 3.38-3.39 3.38c-.9 0-1.76-.35-2.44-1.03l-1.14-1.01-1.51 1.34 1.27 1.12c1.02 1.01 2.37 1.57 3.82 1.57 2.98 0 5.4-2.41 5.4-5.38s-2.42-5.37-5.4-5.37z" />
                </svg>
                {t("prayer.qiblaCalibrationNeeded")}
              </span>
            ) : facing ? (
              <span className="is-facing">
                <svg viewBox="0 0 24 24" aria-hidden="true">
                  <path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20Zm-2 15-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9Z" />
                </svg>
                {t("prayer.qiblaFacing")}
              </span>
            ) : null}
          </p>
        )}
        <p className="kpi-desc">
          {t("prayer.qiblaCoordinates", {
            latitude: formatNumber(latitude, { maximumFractionDigits: 4 }),
            longitude: formatNumber(longitude, { maximumFractionDigits: 4 }),
          })}
        </p>
        {!atKaaba && compass.state === "permission" && (
          <button type="button" className="btn btn-primary btn-sm prayer-qibla-enable" onClick={compass.enable}>
            {t("prayer.qiblaCompassEnable")}
          </button>
        )}
        {!atKaaba && (
          <p className="kpi-desc" data-testid="prayer-qibla-hint">
            {hint}
          </p>
        )}
        {/* Only iOS reports compass accuracy; elsewhere the user decides whether to calibrate. */}
        {live && !calibrate && !compass.accuracyKnown && <p className="kpi-desc">{t("prayer.qiblaCalibrationTip")}</p>}
      </div>
    </section>
  );
}
