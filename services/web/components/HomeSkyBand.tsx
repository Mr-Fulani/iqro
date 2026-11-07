"use client";

import { useEffect, useRef, useState, useSyncExternalStore } from "react";
import type { PrayerCalculationResponse } from "../lib/api";
import { useI18n } from "../lib/i18n-context";
import { localizedPath } from "../lib/routing";
import {
  countdown,
  easeInOutCubic,
  FALLBACK_TIMELINE,
  minutesInZone,
  nextStop,
  SKY_STOPS,
  skyInk,
  skyPalette,
  skyStart,
  skyTimeline,
  skyX,
  spreadLabels,
  type SkyTimeline,
} from "../lib/sky-band";
import { useOpenReplay } from "../lib/use-open-replay";
import { IntentPrefetchLink } from "./IntentPrefetchLink";

// Star positions on a 361-wide band, as in the app.
const STARS: [number, number, number][] = [
  [22, 14, 1.2], [58, 30, 0.9], [96, 10, 1], [132, 40, 0.8], [170, 18, 1.3], [214, 34, 0.9], [250, 12, 1],
  [292, 28, 1.1], [330, 16, 0.8], [118, 62, 0.7], [196, 58, 0.8], [46, 54, 0.9], [270, 52, 0.7], [344, 48, 1],
];
const SKY_HEIGHT = 82;
const GROUND_HEIGHT = 46;
const GOLD = "#F4C24E";
/** The sun travels for the first 80%, then its glow breathes once. */
const DURATION = 3000;

const subscribe = () => () => {};

type Props = { prayer: PrayerCalculationResponse | null };

/**
 * The home page's prayer card: the sky of the day with the sun on its arc
 * from sunrise to maghrib, and the day's prayers on the ground. On every
 * opening the sun rises from the horizon to the present time, as in the app.
 */
export function HomeSkyBand({ prayer }: Props) {
  const { t, locale, formatDate } = useI18n();
  const times = prayer?.times || prayer?.prayer_times;
  const timeline = skyTimeline(times);
  const timezone = prayer?.timezone;
  const box = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(361);
  const [now, setNow] = useState<number | null>(null);
  // Animation progress 0..1; null until the schedule arrives.
  const [progress, setProgress] = useState<number | null>(null);
  const replay = useOpenReplay();
  const painted = useSyncExternalStore(subscribe, () => true, () => false);

  useEffect(() => {
    const element = box.current;
    if (!element) return;
    const observer = new ResizeObserver(([entry]) => setWidth(Math.max(240, Math.round(entry.contentRect.width))));
    observer.observe(element);
    return () => observer.disconnect();
  }, []);

  // The clock of the schedule's city, refreshed every half minute.
  useEffect(() => {
    if (!timezone) return;
    const tick = () => setNow(minutesInZone(timezone));
    tick();
    const id = window.setInterval(tick, 30_000);
    return () => window.clearInterval(id);
  }, [timezone]);

  const ready = timeline !== null;
  useEffect(() => {
    if (!ready) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      setProgress(1);
      return;
    }
    let frame = 0;
    const start = performance.now();
    const step = (time: number) => {
      const value = Math.min(1, (time - start) / DURATION);
      setProgress(value);
      if (value < 1) frame = requestAnimationFrame(step);
    };
    frame = requestAnimationFrame(step);
    return () => cancelAnimationFrame(frame);
  }, [ready, replay]);

  const rtl = locale === "ar";
  const drawn: SkyTimeline = timeline ?? FALLBACK_TIMELINE;
  // The schedule only arrives in the browser, so the city clock is safe to read here.
  const present = now ?? (timezone ? minutesInZone(timezone) : 720);
  // While the schedule loads the sky waits at dawn, where the sun will rise from.
  const travel = timeline ? easeInOutCubic(Math.min(1, (progress ?? 0) / 0.8)) : prayer ? 1 : 0;
  const start = skyStart(drawn, present);
  const minute = start + (present - start) * travel;
  const palette = skyPalette(drawn, minute);
  const ink = skyInk(palette.darkness);
  const next = timeline ? nextStop(timeline, present) : null;
  const evenly = width < 330;

  const timeOf = (code: (typeof SKY_STOPS)[number]) => {
    const local = times?.[code]?.local;
    if (!local) return "—";
    // 24-hour clock in every language, as in the app: "17:12", never "05:12 م".
    return formatDate(local, { hour: "2-digit", minute: "2-digit", hourCycle: "h23", timeZone: timezone });
  };
  const nameOf = (code: (typeof SKY_STOPS)[number]) => t(`prayer.${code}`);
  const title = !timeline
    ? prayer
      ? t("home.prayers")
      : t("common.loading")
    : `${nameOf(SKY_STOPS[next?.index ?? 0])} ${timeOf(SKY_STOPS[next?.index ?? 0])}`;
  const subtitle = timeline ? t("home.prayerIn", { time: countdown(timeline, present) }) : "";
  const summary = [
    title,
    subtitle,
    ...(timeline ? SKY_STOPS.map((code) => `${nameOf(code)} ${timeOf(code)}`) : []),
  ]
    .filter(Boolean)
    .join(", ");

  // Geometry, drawn left to right and mirrored for Arabic.
  const height = SKY_HEIGHT + GROUND_HEIGHT;
  const horizon = SKY_HEIGHT;
  const x = (value: number) => skyX(drawn, value, width, evenly);
  const x0 = x(drawn[1]);
  const x1 = x(drawn[4]);
  const cx = (x0 + x1) / 2;
  const rx = (x1 - x0) / 2;
  const ry = Math.min(60, horizon - 14);
  const scale = width / 361;
  let sun: { x: number; y: number; opacity: number; trail: string } | null = null;
  if (timeline) {
    if (minute > drawn[1] && minute < drawn[4]) {
      const sx = x(minute);
      const dx = Math.max(-1, Math.min(1, (sx - cx) / rx));
      const sy = horizon - ry * Math.sqrt(1 - dx * dx);
      sun = { x: sx, y: sy, opacity: 1, trail: `M${x0} ${horizon} A${rx} ${ry} 0 0 1 ${sx.toFixed(1)} ${sy.toFixed(1)}` };
    } else {
      const before = minute <= drawn[1];
      const depth = before
        ? Math.min(1, Math.max(0, (drawn[1] - minute) / 120))
        : Math.min(1, Math.max(0, (minute - drawn[4]) / 70));
      sun = {
        x: before ? x0 : x1,
        y: horizon + 2 + depth * 18,
        opacity: 1 - depth,
        trail: before ? "" : `M${x0} ${horizon} A${rx} ${ry} 0 0 1 ${x1} ${horizon}`,
      };
    }
  }
  const moon =
    minute > drawn[4] + 42 ? Math.min(1, (minute - drawn[4] - 42) / 90) : minute < drawn[0] - 20 ? 1 : 0;
  const breath = (progress ?? 0) > 0.8 ? 1 + 0.45 * Math.sin((Math.PI * ((progress ?? 0) - 0.8)) / 0.2) : 1;
  const moonX = width - 64;
  const allPassed = next?.tomorrow === true && minute > drawn[5];
  const labelXs = spreadLabels(SKY_STOPS.map((_, index) => x(drawn[index])), width, evenly ? 0 : 46);

  const background = `linear-gradient(180deg, ${palette.top} 0%, ${palette.middle} 42%, ${palette.horizon} 70%, ${palette.horizon} 100%)`;
  // The schedule only arrives in the browser, so the HTML carries just the
  // empty sky at its full height: leaving the loading band out keeps the home
  // page within the first network round trip (the Lighthouse LCP budget).
  if (!painted) {
    return <section className="home-sky home-sky-placeholder" data-testid="home-sky" style={{ background }} />;
  }

  return (
    <section
      className="home-sky"
      data-testid="home-sky"
      style={{
        background,
        color: ink,
      }}
    >
      <IntentPrefetchLink href={localizedPath(locale, "/prayer")} className="home-sky-link" aria-label={summary} />
      <div className="home-sky-head">
        <div className="home-sky-copy" aria-hidden="true">
          <span className="home-sky-label">{t("home.nextPrayer")}</span>
          <strong className="home-sky-title">{title}</strong>
          {/* The line is kept while the schedule loads, so the band does not grow. */}
          <span className="home-sky-subtitle">{subtitle || "\u00a0"}</span>
        </div>
        <IntentPrefetchLink
          href={`${localizedPath(locale, "/prayer")}#qibla`}
          className="home-sky-button"
          aria-label={t("prayer.qibla")}
          title={t("prayer.qibla")}
          style={{ background: `rgba(255, 255, 255, ${0.18 + 0.37 * palette.darkness})`, color: ink }}
        >
          <svg viewBox="0 0 24 24" aria-hidden="true">
            <circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" strokeWidth="1.8" />
            <path d="M15.5 8.5 13.4 13.4 8.5 15.5 10.6 10.6Z" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinejoin="round" />
          </svg>
        </IntentPrefetchLink>
        <IntentPrefetchLink
          href={`${localizedPath(locale, "/prayer")}#prayer-reminders`}
          className="home-sky-button"
          aria-label={t("reminder.prayerCenterTitle")}
          title={t("reminder.prayerCenterTitle")}
          style={{ background: `rgba(255, 255, 255, ${0.18 + 0.37 * palette.darkness})`, color: ink }}
        >
          <svg viewBox="0 0 24 24" aria-hidden="true">
            <path
              d="M6 16V11a6 6 0 0 1 12 0v5l1.5 2h-15ZM10 20.5a2.2 2.2 0 0 0 4 0"
              fill="none"
              stroke="currentColor"
              strokeWidth="1.8"
              strokeLinejoin="round"
              strokeLinecap="round"
            />
          </svg>
        </IntentPrefetchLink>
      </div>
      <div ref={box} className="home-sky-art" aria-hidden="true">
        <svg viewBox={`0 0 ${width} ${height}`} width="100%" height={height}>
          <defs>
            <radialGradient id="home-sky-glow">
              <stop offset="0" stopColor="#FFF4C8" stopOpacity=".95" />
              <stop offset=".35" stopColor="#FFE08A" stopOpacity=".45" />
              <stop offset="1" stopColor="#FFE08A" stopOpacity="0" />
            </radialGradient>
            <radialGradient id="home-sky-moon">
              <stop offset="0" stopColor="#FFF6DA" stopOpacity=".35" />
              <stop offset="1" stopColor="#FFF6DA" stopOpacity="0" />
            </radialGradient>
            <mask id="home-sky-crescent">
              <rect x={moonX - 14} y={12} width={28} height={28} fill="#fff" />
              <circle cx={moonX + 5} cy={22} r={9.5} fill="#000" />
            </mask>
          </defs>
          <g transform={rtl ? `translate(${width} 0) scale(-1 1)` : undefined}>
            {palette.stars > 0.01 &&
              STARS.map(([sx, sy, r]) => (
                <circle key={`${sx}-${sy}`} cx={sx * scale} cy={sy} r={r} fill="#fff" opacity={Math.min(1, palette.stars * (0.45 + r / 3))} />
              ))}
            <path
              d={`M${x0} ${horizon} A${rx} ${ry} 0 0 1 ${x1} ${horizon}`}
              fill="none"
              stroke={ink}
              strokeOpacity=".38"
              strokeWidth="1.4"
              strokeDasharray="3 5"
            />
            {moon > 0 && (
              <g opacity={moon}>
                <circle cx={moonX} cy={26} r={24} fill="url(#home-sky-moon)" />
                <circle cx={moonX} cy={26} r={11} fill="#F3E7C4" mask="url(#home-sky-crescent)" />
              </g>
            )}
            {sun && sun.trail && (
              <path d={sun.trail} fill="none" stroke={GOLD} strokeWidth="2.4" strokeLinecap="round" opacity={sun.opacity * 0.95} />
            )}
            {sun && sun.opacity > 0.02 && (
              <g opacity={sun.opacity}>
                <circle cx={sun.x} cy={sun.y} r={30 * breath} fill="url(#home-sky-glow)" />
                <circle cx={sun.x} cy={sun.y} r={10.5} fill="#FFD55E" stroke="#FFF3C4" strokeWidth="2" />
              </g>
            )}
            <rect x={0} y={horizon} width={width} height={GROUND_HEIGHT} fill={palette.ground} />
            <line x1={0} x2={width} y1={horizon} y2={horizon} stroke={ink} strokeOpacity=".35" />
          </g>
          {timeline &&
            SKY_STOPS.map((code, index) => {
              const left = x(drawn[index]);
              const at = rtl ? width - left : left;
              const labelLeft = labelXs[index];
              const labelAt = rtl ? width - labelLeft : labelLeft;
              const isNext = next?.index === index;
              const sunrise = index === 1;
              const passed = allPassed ? index !== 0 : minute >= drawn[index];
              const opacity = isNext ? 1 : passed ? 0.6 : 0.9;
              const fill = isNext && palette.darkness < 0.5 ? "#FFD98A" : ink;
              return (
                <g key={code}>
                  {isNext ? (
                    <circle cx={at} cy={horizon} r={6.5} fill={GOLD} stroke={ink} strokeOpacity=".5" strokeWidth="1.5" />
                  ) : (
                    <circle
                      cx={at}
                      cy={horizon}
                      r={sunrise ? 2.6 : 3.6}
                      fill={passed ? ink : "none"}
                      stroke={ink}
                      strokeWidth="1.3"
                      opacity={opacity}
                    />
                  )}
                  {!(evenly && sunrise) && (
                    <>
                      <text x={labelAt} y={horizon + 18} textAnchor="middle" fontSize="10.5" fill={fill} opacity={opacity} fontWeight={isNext ? 700 : 400}>
                        {nameOf(code)}
                      </text>
                      <text
                        x={labelAt}
                        y={horizon + 33}
                        textAnchor="middle"
                        fontSize="12.5"
                        fill={fill}
                        opacity={opacity}
                        fontWeight={isNext ? 700 : 600}
                        direction="ltr"
                        className="home-sky-time"
                      >
                        {timeOf(code)}
                      </text>
                    </>
                  )}
                </g>
              );
            })}
        </svg>
      </div>
    </section>
  );
}
