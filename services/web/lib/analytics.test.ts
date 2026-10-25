import assert from "node:assert/strict";
import test from "node:test";

import {
  analyticsConfig,
  hasAnalytics,
  isAnalyticsCookie,
  parseConsent,
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
