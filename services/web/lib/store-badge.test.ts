import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import test from "node:test";

import { SUPPORTED_LOCALES } from "./i18n.ts";
import { googlePlayBadge } from "./store-badge.ts";
import ar from "./messages/ar.ts";
import en from "./messages/en.ts";
import ru from "./messages/ru.ts";
import tr from "./messages/tr.ts";

const STORE_URL = "https://play.google.com/store/apps/details?id=forum.iqro.app";

test("no badge while the store URL is not set", () => {
  for (const locale of SUPPORTED_LOCALES) {
    assert.equal(googlePlayBadge(locale, undefined), null);
    assert.equal(googlePlayBadge(locale, ""), null);
    assert.equal(googlePlayBadge(locale, "  "), null);
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
