import assert from "node:assert/strict";
import test from "node:test";

import {
  analyticsConfig,
  hasAnalytics,
  isAnalyticsCookie,
  noteAnalyticsVisit,
  noteReminderDay,
  parseConsent,
  parseReminder,
  readReminderDue,
  REMINDER_ACTIVE_DAYS,
  REMINDER_AFTER_DAYS,
  reminderAfterAnswer,
  reminderDue,
  writeConsent,
  startAnalytics,
  trackEvent,
  trackPageView,
} from "./analytics.ts";

test("counter IDs are taken only in their own formats", () => {
  assert.deepEqual(analyticsConfig("G-TKV2YGN4KZ", "113787874"), { gaId: "G-TKV2YGN4KZ", metrikaId: 113787874 });
  assert.deepEqual(analyticsConfig(" G-ABC123 ", ""), { gaId: "G-ABC123", metrikaId: null });
  assert.deepEqual(analyticsConfig("UA-123-1", "12ab"), { gaId: null, metrikaId: null });
  assert.equal(hasAnalytics(analyticsConfig("", "")), false);
  assert.equal(hasAnalytics(analyticsConfig(undefined, "1")), true);
});

test("only a stored «granted» or «denied» is a decision", () => {
  assert.equal(parseConsent("granted"), "granted");
  assert.equal(parseConsent("denied"), "denied");
  assert.equal(parseConsent("yes"), null);
  assert.equal(parseConsent(null), null);
});

test("withdrawing consent removes GA and Metrica cookies, not the site's own", () => {
  for (const name of ["_ga", "_ga_TKV2YGN4KZ", "_ym_uid", "_ym_d", "_ym_isad"]) assert.equal(isAnalyticsCookie(name), true);
  for (const name of ["quran_locale_v1", "quran_refresh_v1", "_gat_custom", "ga"]) assert.equal(isAnalyticsCookie(name), false);
});

test("nothing is sent before consent; after it both counters get the same events", () => {
  const appended: string[] = [];
  const fakeWindow: {
    location: { href: string };
    addEventListener: () => void;
    requestIdleCallback: (callback: () => void) => void;
    dataLayer?: IArguments[];
    ym?: { a: IArguments[] };
  } = {
    location: { href: "https://iqro.forum/ru" },
    addEventListener: () => undefined,
    requestIdleCallback: (callback) => callback(),
  };
  Object.assign(globalThis, {
    window: fakeWindow,
    document: {
      readyState: "complete",
      title: "IQRO",
      head: { appendChild: (script: { src: string }) => appended.push(script.src) },
      createElement: () => ({}),
    },
  });

  trackEvent("surah_open", { surah: 2 });
  assert.equal(fakeWindow.dataLayer, undefined);

  startAnalytics({ gaId: "G-TEST1", metrikaId: 42 });
  assert.deepEqual(appended, [
    "https://www.googletagmanager.com/gtag/js?id=G-TEST1",
    "https://mc.yandex.ru/metrika/tag.js",
  ]);
  const config = Array.from(fakeWindow.dataLayer![1]!);
  assert.deepEqual(config, ["config", "G-TEST1", { allow_google_signals: false, allow_ad_personalization_signals: false }]);
  assert.deepEqual(Array.from(fakeWindow.ym!.a[0]!).slice(0, 2), [42, "init"]);

  trackEvent("share", { content_type: "ayah", method: "native" });
  assert.deepEqual(Array.from(fakeWindow.dataLayer!.at(-1)!), ["event", "share", { content_type: "ayah", method: "native" }]);
  assert.deepEqual(Array.from(fakeWindow.ym!.a.at(-1)!), [42, "reachGoal", "share", { content_type: "ayah", method: "native" }]);

  // The first address is counted by «init»; Metrica hears of the next one only.
  trackPageView();
  assert.equal(fakeWindow.ym!.a.length, 2);
  fakeWindow.location.href = "https://iqro.forum/ru/quran";
  trackPageView();
  assert.deepEqual(Array.from(fakeWindow.ym!.a.at(-1)!), [
    42, "hit", "https://iqro.forum/ru/quran", { referer: "https://iqro.forum/ru", title: "IQRO" },
  ]);

  // A second start (another consent event) does not load the scripts again.
  startAnalytics({ gaId: "G-TEST1", metrikaId: 42 });
  assert.equal(appended.length, 2);
});

const day = (offset: number) => new Date(2026, 10, 21 + offset, 9);
const empty = parseReminder(null);

/** A refusal on day 0, then visits on each of `offsets`. */
function declinedThenVisited(offsets: number[]) {
  return offsets.reduce((reminder, offset) => noteReminderDay(reminder, day(offset)), reminderAfterAnswer(empty, "denied", day(0)));
}

test("the reminder waits 30 days and 5 days of visits", () => {
  assert.equal(REMINDER_AFTER_DAYS, 30);
  assert.equal(REMINDER_ACTIVE_DAYS, 5);

  const declined = reminderAfterAnswer(empty, "denied", day(0));
  assert.deepEqual(declined, { declinedOn: "2026-11-21", lastDay: "2026-11-21", days: 1, done: false });
  assert.equal(reminderDue(declined, day(0)), false);

  // Every day for 29 days: too early. Day 30: due.
  const daily = declinedThenVisited(Array.from({ length: 29 }, (_, index) => index + 1));
  assert.equal(reminderDue(daily, day(29)), false);
  assert.equal(reminderDue(noteReminderDay(daily, day(30)), day(30)), true);

  // Long ago but only four days of visits: not yet. The same day counts once.
  const rare = noteReminderDay(noteReminderDay(declinedThenVisited([1, 2]), day(90)), day(90));
  assert.equal(rare.days, 4);
  assert.equal(reminderDue(rare, day(90)), false);
  assert.equal(reminderDue(noteReminderDay(rare, day(91)), day(91)), true);
});

test("any answer to the reminder is final; an earlier refusal restarts the count", () => {
  const due = declinedThenVisited([1, 2, 3, 40]);
  assert.equal(reminderDue(due, day(40)), true);

  for (const answer of ["denied", "granted"] as const) {
    const answered = reminderAfterAnswer(due, answer, day(40));
    assert.equal(answered.done, true);
    assert.equal(reminderDue(answered, day(400)), false);
    // Withdrawing or declining later changes nothing.
    assert.equal(reminderAfterAnswer(noteReminderDay(answered, day(401)), "denied", day(401)), answered);
  }

  // Allowed and withdrawn on /cookies before the reminder: counted from the new refusal.
  const early = declinedThenVisited([1, 2]);
  assert.equal(reminderAfterAnswer(early, "granted", day(3)), early);
  assert.deepEqual(reminderAfterAnswer(early, "denied", day(20)), { declinedOn: "2026-12-11", lastDay: "2026-12-11", days: 1, done: false });

  assert.deepEqual(parseReminder("not json"), empty);
  assert.deepEqual(parseReminder('{"declinedOn":5,"days":"7"}'), empty);
});

test("the stored choice: an old refusal starts counting, the second one ends it, agreeing is kept", () => {
  const items = new Map<string, string>();
  let events = 0;
  Object.assign(globalThis, {
    window: {
      location: { hostname: "iqro.forum" },
      dispatchEvent: () => events++,
      localStorage: {
        getItem: (key: string) => items.get(key) ?? null,
        setItem: (key: string, value: string) => items.set(key, value),
        removeItem: (key: string) => items.delete(key),
      },
    },
    document: { cookie: "" },
  });
  const stored = () => parseReminder(items.get("iqro_analytics_reminder_v1"));

  // Nobody who has not answered, or agreed, is counted.
  noteAnalyticsVisit(day(0));
  items.set("iqro_analytics_consent_v1", "granted");
  noteAnalyticsVisit(day(0));
  assert.equal(items.has("iqro_analytics_reminder_v1"), false);

  // A refusal from before the reminder existed: the count starts today.
  items.set("iqro_analytics_consent_v1", "denied");
  noteAnalyticsVisit(day(0));
  assert.equal(stored().declinedOn, "2026-11-21");
  assert.equal(events, 1);
  noteAnalyticsVisit(day(0));
  assert.equal(events, 1);

  for (const offset of [5, 10, 15, 29]) noteAnalyticsVisit(day(offset));
  assert.equal(readReminderDue(day(29)), false);
  noteAnalyticsVisit(day(30));
  assert.equal(readReminderDue(day(30)), true);
  // It waits for an answer.
  assert.equal(readReminderDue(day(45)), true);

  writeConsent("denied", day(45));
  assert.equal(items.get("iqro_analytics_consent_v1"), "denied");
  assert.equal(stored().done, true);
  noteAnalyticsVisit(day(400));
  assert.equal(readReminderDue(day(400)), false);

  // Agreeing on the reminder turns statistics on and closes it too.
  items.set("iqro_analytics_reminder_v1", JSON.stringify({ declinedOn: "2026-01-01", lastDay: "2026-02-01", days: 5, done: false }));
  assert.equal(readReminderDue(day(0)), true);
  writeConsent("granted", day(0));
  assert.equal(items.get("iqro_analytics_consent_v1"), "granted");
  assert.equal(stored().done, true);
  assert.equal(readReminderDue(day(0)), false);
});
