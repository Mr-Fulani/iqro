// Visitor statistics: Google Analytics 4 and Yandex Metrica (docs/analytics.md).
// Both counters wait for the visitor's «Принять» in the cookie banner. Their IDs
// are inlined at build time; without them the banner is not shown and nothing
// is loaded. Even with consent the scripts load only after the page has
// finished loading, so they never compete with the first paint.

export const ANALYTICS_CONSENT_KEY = "iqro_analytics_consent_v1";
export const ANALYTICS_CONSENT_EVENT = "iqro:analytics-consent";

export type AnalyticsConsent = "granted" | "denied";
export type AnalyticsConfig = { gaId: string | null; metrikaId: number | null };

/** The events both counters receive; the app sends the same names. */
export type AnalyticsEventName =
  | "surah_open"
  | "audio_play"
  | "lesson_complete"
  | "share"
  | "login";
export type AnalyticsParams = Record<string, string | number>;

type AnalyticsWindow = Window & {
  dataLayer?: unknown[];
  gtag?: (...args: unknown[]) => void;
  ym?: ((...args: unknown[]) => void) & { a?: unknown[]; l?: number };
};

export function analyticsConfig(
  gaId = process.env.NEXT_PUBLIC_GA_MEASUREMENT_ID,
  metrikaId = process.env.NEXT_PUBLIC_YANDEX_METRIKA_ID,
): AnalyticsConfig {
  const ga = gaId?.trim() ?? "";
  const ym = metrikaId?.trim() ?? "";
  return {
    gaId: /^G-[A-Z0-9]+$/.test(ga) ? ga : null,
    metrikaId: /^[1-9]\d*$/.test(ym) ? Number(ym) : null,
  };
}

export function hasAnalytics(config: AnalyticsConfig): boolean {
  return config.gaId !== null || config.metrikaId !== null;
}

export function parseConsent(value: string | null | undefined): AnalyticsConsent | null {
  return value === "granted" || value === "denied" ? value : null;
}

/**
 * One gentle reminder for visitors who declined statistics: not sooner than
 * REMINDER_AFTER_DAYS days after the refusal, and only after visits on
 * REMINDER_ACTIVE_DAYS different days since then. The app keeps the same pair
 * in clients/iqro_mobile/lib/core/analytics/analytics.dart.
 */
export const REMINDER_AFTER_DAYS = 30;
export const REMINDER_ACTIVE_DAYS = 5;
export const ANALYTICS_REMINDER_KEY = "iqro_analytics_reminder_v1";

/**
 * What the reminder needs to know, kept in localStorage as JSON. Days are
 * local calendar days, "2026-11-21". `declinedOn` is the day of the refusal;
 * for a refusal made before the reminder existed, the first visit with it.
 * `done`: the reminder was answered and nothing asks again.
 */
export type AnalyticsReminder = { declinedOn: string | null; lastDay: string | null; days: number; done: boolean };

const NO_REMINDER: AnalyticsReminder = { declinedOn: null, lastDay: null, days: 0, done: false };

export function parseReminder(value: string | null | undefined): AnalyticsReminder {
  try {
    const json = JSON.parse(value ?? "") as Partial<AnalyticsReminder>;
    return {
      declinedOn: typeof json.declinedOn === "string" ? json.declinedOn : null,
      lastDay: typeof json.lastDay === "string" ? json.lastDay : null,
      days: typeof json.days === "number" ? json.days : 0,
      done: json.done === true,
    };
  } catch {
    return NO_REMINDER;
  }
}

function localDay(now: Date): string {
  const pad = (value: number) => String(value).padStart(2, "0");
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}

/** A visit on `now` while statistics are declined. */
export function noteReminderDay(reminder: AnalyticsReminder, now: Date): AnalyticsReminder {
  const today = localDay(now);
  if (reminder.done || reminder.lastDay === today) return reminder;
  return reminder.declinedOn === null
    ? { declinedOn: today, lastDay: today, days: 1, done: false }
    : { ...reminder, lastDay: today, days: reminder.days + 1 };
}

export function reminderDue(reminder: AnalyticsReminder, now: Date): boolean {
  if (reminder.done || reminder.declinedOn === null) return false;
  const declined = Date.parse(`${reminder.declinedOn}T00:00:00Z`);
  const today = Date.parse(`${localDay(now)}T00:00:00Z`);
  if (Number.isNaN(declined)) return false;
  return reminder.days >= REMINDER_ACTIVE_DAYS && (today - declined) / 86_400_000 >= REMINDER_AFTER_DAYS;
}

/**
 * The record after an answer given on `now`. Any answer to the reminder is
 * final; a refusal before it starts the count from that day.
 */
export function reminderAfterAnswer(reminder: AnalyticsReminder, consent: AnalyticsConsent, now: Date): AnalyticsReminder {
  if (reminder.done) return reminder;
  if (reminderDue(reminder, now)) return { ...reminder, done: true };
  return consent === "denied" ? noteReminderDay(NO_REMINDER, now) : reminder;
}

function readReminder(): AnalyticsReminder {
  try {
    return parseReminder(window.localStorage.getItem(ANALYTICS_REMINDER_KEY));
  } catch {
    return NO_REMINDER;
  }
}

function storeReminder(reminder: AnalyticsReminder): void {
  try {
    window.localStorage.setItem(ANALYTICS_REMINDER_KEY, JSON.stringify(reminder));
  } catch {
    // Without storage there is no reminder either.
  }
}

/** Whether the banner should ask once more. */
export function readReminderDue(now = new Date()): boolean {
  return readConsent() === "denied" && reminderDue(readReminder(), now);
}

/** Counts today's visit for a visitor who declined. */
export function noteAnalyticsVisit(now = new Date()): void {
  if (readConsent() !== "denied") return;
  const before = readReminder();
  const next = noteReminderDay(before, now);
  if (next === before) return;
  storeReminder(next);
  window.dispatchEvent(new Event(ANALYTICS_CONSENT_EVENT));
}

export function readConsent(): AnalyticsConsent | null {
  try {
    return parseConsent(window.localStorage.getItem(ANALYTICS_CONSENT_KEY));
  } catch {
    return null;
  }
}

/**
 * Remembers the choice. Withdrawing consent also removes the counters' cookies;
 * the caller reloads the page so their scripts stop too.
 */
export function writeConsent(consent: AnalyticsConsent, now = new Date()): void {
  const before = readReminder();
  const next = reminderAfterAnswer(before, consent, now);
  if (next !== before) storeReminder(next);
  try {
    window.localStorage.setItem(ANALYTICS_CONSENT_KEY, consent);
  } catch {
    // Without storage the banner simply asks again on the next visit.
  }
  if (consent === "denied") removeAnalyticsData();
  window.dispatchEvent(new Event(ANALYTICS_CONSENT_EVENT));
}

/** Cookie names the counters set: GA's _ga, _ga_<stream>, Metrica's _ym_*. */
export function isAnalyticsCookie(name: string): boolean {
  return name === "_ga" || name.startsWith("_ga_") || name.startsWith("_ym_");
}

/**
 * Removes what the counters left on this device. Metrica also writes a few
 * localStorage keys while the page unloads, so a later visit without consent
 * clears them again.
 */
export function removeAnalyticsData(): void {
  const host = window.location.hostname;
  const domains = ["", host, `.${host}`, `.${host.split(".").slice(-2).join(".")}`];
  for (const cookie of document.cookie.split(";")) {
    const name = cookie.split("=")[0]?.trim() ?? "";
    if (!isAnalyticsCookie(name)) continue;
    for (const domain of domains) {
      document.cookie = `${name}=; Max-Age=0; Path=/${domain ? `; Domain=${domain}` : ""}`;
    }
  }
  try {
    for (const key of Object.keys(window.localStorage)) {
      if (key.startsWith("_ym")) window.localStorage.removeItem(key);
    }
  } catch {
    // Nothing more to remove.
  }
}

let active: AnalyticsConfig | null = null;
let lastHitUrl: string | null = null;

/** Queues the counters at once and loads their scripts after the page load. */
export function startAnalytics(config: AnalyticsConfig): void {
  if (active || !hasAnalytics(config)) return;
  active = config;
  const w = window as AnalyticsWindow;
  lastHitUrl = window.location.href;
  if (config.gaId) {
    w.dataLayer = w.dataLayer || [];
    w.gtag = function gtag() {
      // gtag.js reads the Arguments objects, not arrays.
      // eslint-disable-next-line prefer-rest-params
      w.dataLayer!.push(arguments);
    };
    w.gtag("js", new Date());
    // Religion is a sensitive category: no Google signals, no ad personalization.
    w.gtag("config", config.gaId, { allow_google_signals: false, allow_ad_personalization_signals: false });
  }
  if (config.metrikaId) {
    w.ym = w.ym || Object.assign(function ym() {
      // eslint-disable-next-line prefer-rest-params
      (w.ym!.a = w.ym!.a || []).push(arguments);
    }, { l: Date.now() });
    w.ym(config.metrikaId, "init", {
      clickmap: true,
      trackLinks: true,
      accurateTrackBounce: true,
      webvisor: true,
    });
  }
  const load = () => {
    if (config.gaId) appendScript(`https://www.googletagmanager.com/gtag/js?id=${config.gaId}`);
    if (config.metrikaId) appendScript("https://mc.yandex.ru/metrika/tag.js");
  };
  const whenIdle = () => ("requestIdleCallback" in window ? window.requestIdleCallback(load, { timeout: 4_000 }) : setTimeout(load, 1));
  if (document.readyState === "complete") whenIdle();
  else window.addEventListener("load", whenIdle, { once: true });
}

function appendScript(src: string): void {
  const script = document.createElement("script");
  script.async = true;
  script.src = src;
  document.head.appendChild(script);
}

/**
 * A page view after a client-side navigation. GA4 counts these itself from the
 * history API; Metrica is told the new address.
 */
export function trackPageView(): void {
  if (!active?.metrikaId) return;
  const url = window.location.href;
  if (url === lastHitUrl) return;
  const referer = lastHitUrl;
  lastHitUrl = url;
  (window as AnalyticsWindow).ym?.(active.metrikaId, "hit", url, { referer, title: document.title });
}

/** Sends an event to both counters; before consent it is dropped. */
export function trackEvent(name: AnalyticsEventName, params: AnalyticsParams = {}): void {
  if (!active) return;
  const w = window as AnalyticsWindow;
  if (active.gaId) w.gtag?.("event", name, params);
  if (active.metrikaId) w.ym?.(active.metrikaId, "reachGoal", name, params);
}
