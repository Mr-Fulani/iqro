import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import test from "node:test";

import { SUPPORTED_LOCALES } from "./i18n.ts";
import { appStoreAppId, appStoreBadge, googlePlayBadge } from "./store-badge.ts";
import ar from "./messages/ar.ts";
import en from "./messages/en.ts";
import ru from "./messages/ru.ts";
import tr from "./messages/tr.ts";

const STORE_URL = "https://play.google.com/store/apps/details?id=forum.iqro.app";
const APP_STORE_URL = "https://apps.apple.com/app/iqro/id6740000000";

test("no badge while the store URL is not set", () => {
  for (const locale of SUPPORTED_LOCALES) {
    assert.equal(googlePlayBadge(locale, undefined), null);
    assert.equal(googlePlayBadge(locale, ""), null);
    assert.equal(googlePlayBadge(locale, "  "), null);
    assert.equal(appStoreBadge(locale, undefined), null);
    assert.equal(appStoreBadge(locale, ""), null);
    assert.equal(appStoreBadge(locale, "  "), null);
  }
});

test("every site language has its own badge file and label", () => {
  const messages = { ru, en, ar, tr };
  for (const locale of SUPPORTED_LOCALES) {
    const badge = googlePlayBadge(locale, ` ${STORE_URL} `);
    assert.ok(badge);
    assert.equal(badge.href, STORE_URL);
    assert.equal(badge.src, `/images/store/google-play-${locale}.webp`);
    assert.ok(existsSync(new URL(`../public${badge.src}`, import.meta.url)), badge.src);
    assert.match(messages[locale]["footer.googlePlayBadge"], /Google Play/);
  }
});

test("every site language has Apple's own App Store badge and label", () => {
  const messages = { ru, en, ar, tr };
  for (const locale of SUPPORTED_LOCALES) {
    const badge = appStoreBadge(locale, ` ${APP_STORE_URL} `);
    assert.ok(badge);
    assert.equal(badge.href, APP_STORE_URL);
    assert.equal(badge.src, `/images/store/app-store-${locale}.svg`);
    const svg = readFileSync(new URL(`../public${badge.src}`, import.meta.url), "utf8");
    const [, width, height] = svg.match(/viewBox="0 0 ([\d.]+) ([\d.]+)"/) ?? [];
    assert.equal(Math.round(Number(width)), badge.width, badge.src);
    assert.equal(Math.round(Number(height)), badge.height, badge.src);
    assert.doesNotMatch(svg, /<script|<image|<foreignObject|href=|\son[a-z]+=/i, badge.src);
    assert.match(messages[locale]["footer.appStoreBadge"], /App Store/);
  }
});

test("Safari's banner gets the app number from the App Store page URL", () => {
  assert.equal(appStoreAppId(APP_STORE_URL), "6740000000");
  assert.equal(appStoreAppId(" https://apps.apple.com/ru/app/iqro/id6740000000?l=ru "), "6740000000");
  assert.equal(appStoreAppId("https://apps.apple.com/id6740000000"), "6740000000");
  assert.equal(appStoreAppId(undefined), null);
  assert.equal(appStoreAppId(""), null);
  assert.equal(appStoreAppId("https://apps.apple.com/app/iqro"), null);
  assert.equal(appStoreAppId("https://apps.apple.com/app/iqro/id6740000000x"), null);
  assert.equal(appStoreAppId("https://example.com/app/iqro/id6740000000"), null);
});
