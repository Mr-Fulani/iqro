// The home page's sky of prayers. The same moments, colours and geometry as
// the app (clients/iqro_mobile/lib/features/home/home_sky_card.dart), so the
// sun stands in the same place on the site and on the phone.

export const SKY_STOPS = ["fajr", "sunrise", "dhuhr", "asr", "maghrib", "isha"] as const;
export type SkyStop = (typeof SKY_STOPS)[number];

/** Minutes after local midnight of the six stops, in order. */
export type SkyTimeline = readonly [number, number, number, number, number, number];

export type SkyPalette = {
  top: string;
  middle: string;
  horizon: string;
  /** rgba */
  ground: string;
  /** 0 under a dark sky (white text), 1 under the day sky (deep ink text). */
  darkness: number;
  stars: number;
};

type Rgba = readonly [number, number, number, number];
type Key = { top: string; middle: string; horizon: string; ground: Rgba; darkness: number; stars: number };

const NIGHT: Key = { top: "#060E23", middle: "#101B40", horizon: "#24315F", ground: [0, 0, 0, 0.32], darkness: 0, stars: 1 };
const DAWN: Key = { top: "#1E2A58", middle: "#6B5A90", horizon: "#F0A06C", ground: [24, 18, 46, 0.3], darkness: 0, stars: 0.55 };
const DAY: Key = { top: "#3C8DCB", middle: "#8CC6EA", horizon: "#DCEFF8", ground: [255, 255, 255, 0.52], darkness: 1, stars: 0 };
const SUNSET: Key = { top: "#3B3974", middle: "#C7607A", horizon: "#F6B067", ground: [48, 16, 34, 0.3], darkness: 0, stars: 0.15 };
const DUSK: Key = { top: "#211D4A", middle: "#5A3E73", horizon: "#B0627A", ground: [20, 10, 30, 0.32], darkness: 0, stars: 0.5 };

/** Typical times, for the sky before a schedule arrives. */
export const FALLBACK_TIMELINE: SkyTimeline = [300, 390, 750, 930, 1080, 1170];

/** "2026-11-06T05:52:00+03:00" → 352: the wall clock of the city. */
export function wallMinutes(local: string | undefined): number | null {
  const match = local?.match(/T(\d{2}):(\d{2})(?::(\d{2}))?/);
  if (!match) return null;
  return Number(match[1]) * 60 + Number(match[2]) + Number(match[3] ?? 0) / 60;
}

/** The six stops from a schedule; null when one is missing or out of order. */
export function skyTimeline(times: Partial<Record<SkyStop, { local?: string } | undefined>> | undefined): SkyTimeline | null {
  if (!times) return null;
  const stops: number[] = [];
  for (const code of SKY_STOPS) {
    const minute = wallMinutes(times[code]?.local);
    if (minute === null || (stops.length && minute <= stops[stops.length - 1])) return null;
    stops.push(minute);
  }
  return stops as unknown as SkyTimeline;
}

/** Minutes after midnight now, in the schedule's time zone. */
export function minutesInZone(timezone: string, now = new Date()): number {
  try {
    const parts = new Intl.DateTimeFormat("en-GB", {
      timeZone: timezone,
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hourCycle: "h23",
    }).formatToParts(now);
    const value = (type: string) => Number(parts.find((part) => part.type === type)?.value ?? 0);
    return value("hour") * 60 + value("minute") + value("second") / 60;
  } catch {
    return now.getHours() * 60 + now.getMinutes();
  }
}

/** Index of the next prayer (never sunrise) and whether it is tomorrow's fajr. */
export function nextStop(timeline: SkyTimeline, now: number): { index: number; tomorrow: boolean } {
  for (let index = 0; index < SKY_STOPS.length; index++) {
    if (index !== 1 && timeline[index] > now) return { index, tomorrow: false };
  }
  return { index: 0, tomorrow: true };
}

/** A minute of the clock, wrapped into 0..1440. */
export const wrapMinute = (minute: number) => ((minute % 1440) + 1440) % 1440;

/**
 * The sun's angle on the orbit it shares with the moon: 0 on the left
 * horizon at sunrise, π/2 overhead, π on the right horizon at maghrib, and
 * the night half under the ground until the next sunrise. The moon stands
 * opposite, at angle + π, so it rises at maghrib and sets at sunrise.
 */
export function orbitAngle(timeline: SkyTimeline, minute: number): number {
  const [, sunrise, , , maghrib] = timeline;
  const day = maghrib - sunrise;
  const since = wrapMinute(minute - sunrise);
  return since <= day ? Math.PI * (since / day) : Math.PI + Math.PI * ((since - day) / (1440 - day));
}

/** Minutes before the last sunrise or maghrib at which the opening starts. */
export const ORBIT_LEAD = 40;

/**
 * Where the opening animation starts: shortly before the last sunrise (by
 * day) or maghrib (by night), so the sun and the moon change places on
 * screen. After midnight that maghrib was yesterday's, a negative minute.
 */
export function orbitStart(timeline: SkyTimeline, now: number): number {
  const [, sunrise, , , maghrib] = timeline;
  if (now >= sunrise && now < maghrib) return sunrise - ORBIT_LEAD;
  return maghrib - ORBIT_LEAD - (now < sunrise ? 1440 : 0);
}

const hex = (value: string) => [1, 3, 5].map((index) => parseInt(value.slice(index, index + 2), 16));
const mix = (a: readonly number[], b: readonly number[], f: number) => a.map((value, index) => value + (b[index] - value) * f);
const rgb = (value: readonly number[]) => `rgb(${value.map((part) => Math.round(part)).join(", ")})`;

export function skyPalette(timeline: SkyTimeline, at: number): SkyPalette {
  const minute = wrapMinute(at);
  const [fajr, sunrise, , , maghrib, isha] = timeline;
  const raw: [number, Key][] = [
    [fajr - 52, NIGHT],
    [sunrise - 61, DAWN],
    [sunrise + 59, DAY],
    [maghrib - 98, DAY],
    [maghrib - 33, SUNSET],
    [maghrib + 52, DUSK],
    [isha + 48, NIGHT],
  ];
  let previous = -Infinity;
  const keys = raw.map(([at, key]) => {
    previous = Math.max(previous + 1, at);
    return [previous, key] as const;
  });
  let a = keys[0];
  let b = keys[0];
  let f = 0;
  if (minute > keys[keys.length - 1][0]) {
    a = b = keys[keys.length - 1];
  } else if (minute > keys[0][0]) {
    for (let index = 0; index < keys.length - 1; index++) {
      if (minute <= keys[index + 1][0]) {
        a = keys[index];
        b = keys[index + 1];
        f = (minute - a[0]) / (b[0] - a[0]);
        break;
      }
    }
  }
  const [ka, kb] = [a[1], b[1]];
  const ground = mix(ka.ground, kb.ground, f);
  return {
    top: rgb(mix(hex(ka.top), hex(kb.top), f)),
    middle: rgb(mix(hex(ka.middle), hex(kb.middle), f)),
    horizon: rgb(mix(hex(ka.horizon), hex(kb.horizon), f)),
    ground: `rgba(${ground.slice(0, 3).map(Math.round).join(", ")}, ${ground[3].toFixed(3)})`,
    darkness: ka.darkness + (kb.darkness - ka.darkness) * f,
    stars: ka.stars + (kb.stars - ka.stars) * f,
  };
}

export function skyInk(darkness: number): string {
  return rgb(mix([255, 255, 255], hex("#08293A"), darkness));
}

export const easeInOutCubic = (x: number) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2);

/** x of a minute on a band of `width`: proportional, or evenly per stop. */
export function skyX(timeline: SkyTimeline, minute: number, width: number, evenly = false, pad = 28): number {
  const span = width - 2 * pad;
  if (!evenly) return pad + ((minute - timeline[0]) / (timeline[5] - timeline[0])) * span;
  let index = 0;
  while (index < 4 && minute > timeline[index + 1]) index++;
  const f = Math.min(1, Math.max(0, (minute - timeline[index]) / (timeline[index + 1] - timeline[index])));
  return pad + ((index + f) * span) / 5;
}

/** "1:10" until the next prayer, as in the app. */
export function countdown(timeline: SkyTimeline, now: number): string {
  const { index, tomorrow } = nextStop(timeline, now);
  const minutes = Math.max(0, Math.floor(timeline[index] + (tomorrow ? 1440 : 0) - now));
  return `${Math.floor(minutes / 60)}:${String(minutes % 60).padStart(2, "0")}`;
}

/**
 * Label centres for the six stops: at their marks, pushed apart where two
 * times are close (fajr and sunrise in Mecca) so that names never overlap.
 */
export function spreadLabels(marks: readonly number[], width: number, gap: number, edge = 22): number[] {
  const xs = [...marks];
  for (let index = 1; index < xs.length; index++) xs[index] = Math.max(xs[index], xs[index - 1] + gap);
  xs[xs.length - 1] = Math.min(xs[xs.length - 1], width - edge);
  for (let index = xs.length - 2; index >= 0; index--) xs[index] = Math.min(xs[index], xs[index + 1] - gap);
  xs[0] = Math.max(xs[0], edge);
  return xs;
}
