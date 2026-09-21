import assert from "node:assert/strict";
import test from "node:test";

import type { Recitation, Reciter } from "./api.ts";
import {
  latestRecitationsByVariant,
  recitationsForRole,
  supportsRecitationRole,
} from "./reciter-catalog.ts";

const reciter: Reciter = {
  id: "00000000-0000-7000-8000-000000000101",
  slug: "qf-101-test-reciter",
  name_ar: "قارئ الاختبار",
  name_en: "Test Reciter",
  name_ru: "Тестовый чтец",
  country_code: "SA",
};

function recitation(
  id: string,
  publishedAt: string,
  capabilities: Recitation["capabilities"],
): Recitation {
  return {
    id,
    code: "qf-101-murattal",
    version: publishedAt,
    style: "murattal",
    reciter,
    quran_edition: {
      id: "00000000-0000-7000-8000-000000000102",
      code: "madani-hafs",
      content_version: "1.0.0",
      riwayah: "Hafs 'an Asim",
    },
    source: {
      name: "Test source",
      url: "https://example.test/source",
      version: "1.0.0",
      checksum_sha256: "a".repeat(64),
    },
    license: {
      rights_holder: "Test",
      name: "Test license",
      url: "https://example.test/license",
      spdx_id: "CC0-1.0",
      attribution: "Test",
    },
    rights: { stream: true, offline_download: false },
    coverage: {
      track_count: 114,
      surah_count: 114,
      expected_ayahs: 6236,
      timed_ayahs: capabilities.ayah_playback ? 6236 : 0,
      complete: true,
      timings_complete: capabilities.ayah_playback,
    },
    timings: {
      available: capabilities.ayah_playback,
      segment_count: capabilities.ayah_playback ? 6236 : 0,
      complete: capabilities.ayah_playback,
    },
    capabilities,
    published_at: publishedAt,
  };
}

const timed = recitation(
  "00000000-0000-7000-8000-000000000103",
  "2026-09-01T00:00:00Z",
  { listen: true, ayah_playback: true, memorization: true, offline: false },
);

const newerUntimed = recitation(
  "00000000-0000-7000-8000-000000000104",
  "2026-09-10T00:00:00Z",
  { listen: true, ayah_playback: false, memorization: false, offline: false },
);

test("filters recitations by explicit role capabilities", () => {
  assert.deepEqual(recitationsForRole([timed, newerUntimed], "listen"), [
    timed,
    newerUntimed,
  ]);
  assert.deepEqual(recitationsForRole([timed, newerUntimed], "ayah_playback"), [timed]);
  assert.deepEqual(recitationsForRole([timed, newerUntimed], "memorization"), [timed]);

  const listenOnly = { ...timed, capabilities: { ...timed.capabilities, listen: false } };
  assert.equal(supportsRecitationRole(listenOnly, "listen"), false);
});

test("filters before deduplicating so a newer untimed variant does not hide a timed one", () => {
  assert.deepEqual(latestRecitationsByVariant([timed, newerUntimed], "listen"), [newerUntimed]);
  assert.deepEqual(latestRecitationsByVariant([timed, newerUntimed], "ayah_playback"), [timed]);
  assert.deepEqual(latestRecitationsByVariant([timed, newerUntimed], "memorization"), [timed]);
});

test("legacy responses retain listening compatibility while timed roles require complete timings", () => {
  const legacy = structuredClone(timed) as Recitation;
  delete (legacy as unknown as { capabilities?: unknown }).capabilities;
  delete (legacy.timings as unknown as { complete?: boolean }).complete;

  assert.equal(supportsRecitationRole(legacy, "listen"), true);
  assert.equal(supportsRecitationRole(legacy, "ayah_playback"), false);
  assert.equal(supportsRecitationRole(legacy, "memorization"), false);
});
