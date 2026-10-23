import assert from "node:assert/strict";
import test from "node:test";

import type { Recitation } from "./api.ts";
import {
  learningRecitation,
  loadReciterPreference,
  reciterPreferenceStorageKey,
  rememberReciterPreference,
} from "./reciter-preference.ts";

function createMockStorage(): Storage {
  const store = new Map<string, string>();
  return {
    getItem: (key: string) => store.get(key) ?? null,
    setItem: (key: string, value: string) => {
      store.set(key, value);
    },
    removeItem: (key: string) => {
      store.delete(key);
    },
    clear: () => store.clear(),
    key: (index: number) => Array.from(store.keys())[index] ?? null,
    get length() {
      return store.size;
    },
  };
}

const listeningReciter = {
  id: "00000000-0000-7000-8000-000000000201",
  slug: "qf-201-listening",
};
const mushafReciter = {
  id: "00000000-0000-7000-8000-000000000202",
  slug: "qf-202-mushaf",
};
const memorizationReciter = {
  id: "00000000-0000-7000-8000-000000000203",
  slug: "qf-203-memorization",
};

test("listening, mushaf and memorization preferences are stored independently", () => {
  const storage = createMockStorage();

  rememberReciterPreference(
    listeningReciter,
    { id: "00000000-0000-7000-8000-000000000211", style: "murattal" },
    "listening",
    storage,
  );
  rememberReciterPreference(
    mushafReciter,
    { id: "00000000-0000-7000-8000-000000000212", style: "murattal" },
    "mushaf",
    storage,
  );
  rememberReciterPreference(
    memorizationReciter,
    { id: "00000000-0000-7000-8000-000000000213", style: "murattal" },
    "memorization",
    storage,
  );

  assert.equal(loadReciterPreference("listening", storage)?.reciterId, listeningReciter.id);
  assert.equal(loadReciterPreference("mushaf", storage)?.reciterId, mushafReciter.id);
  assert.equal(
    loadReciterPreference("memorization", storage)?.reciterId,
    memorizationReciter.id,
  );
  assert.equal(
    storage.getItem(reciterPreferenceStorageKey("listening")) !==
      storage.getItem(reciterPreferenceStorageKey("mushaf")),
    true,
  );
});

test("memorization writes never overwrite the listening preference", () => {
  const storage = createMockStorage();
  rememberReciterPreference(
    listeningReciter,
    { id: "00000000-0000-7000-8000-000000000221", style: "murattal" },
    "listening",
    storage,
  );
  rememberReciterPreference(
    memorizationReciter,
    { id: "00000000-0000-7000-8000-000000000222", style: "murattal" },
    "memorization",
    storage,
  );

  assert.equal(loadReciterPreference("listening", storage)?.personKey, listeningReciter.slug);
  assert.equal(
    loadReciterPreference("memorization", storage)?.personKey,
    memorizationReciter.slug,
  );
});

test("the legacy key is a fallback for listening only", () => {
  const storage = createMockStorage();
  const legacy = {
    personKey: listeningReciter.slug,
    reciterId: listeningReciter.id,
    recitationId: "00000000-0000-7000-8000-000000000231",
    style: "murattal",
  };
  storage.setItem("quran_reciter_preference_v1", JSON.stringify(legacy));

  assert.deepEqual(loadReciterPreference("listening", storage), legacy);
  assert.equal(loadReciterPreference("mushaf", storage), null);
  assert.equal(loadReciterPreference("memorization", storage), null);
});

test("changing listening reciter without a variant clears the previous variant for a new person", () => {
  const storage = createMockStorage();
  rememberReciterPreference(
    listeningReciter,
    { id: "00000000-0000-7000-8000-000000000241", style: "murattal" },
    "listening",
    storage,
  );
  rememberReciterPreference(listeningReciter, null, "listening", storage);
  assert.equal(
    loadReciterPreference("listening", storage)?.recitationId,
    "00000000-0000-7000-8000-000000000241",
  );

  rememberReciterPreference(mushafReciter, null, "listening", storage);
  assert.equal(loadReciterPreference("listening", storage)?.recitationId, null);
  assert.equal(loadReciterPreference("listening", storage)?.style, null);
});

function recitation(
  id: string,
  reciter: { id: string; slug: string },
  extra: Partial<Recitation> = {},
): Recitation {
  return {
    id,
    code: `${reciter.slug}-murattal`,
    version: "1.0.0",
    style: "murattal",
    reciter: { ...reciter, name_ar: "قارئ", name_en: "Reciter", name_ru: "Чтец", country_code: "SA" },
    quran_edition: {
      id: "00000000-0000-7000-8000-000000000301",
      code: "madani-hafs",
      content_version: "1.0.0",
      riwayah: "Hafs 'an Asim",
    },
    source: { name: "Test", url: "https://example.test/source", version: "1", checksum_sha256: "a".repeat(64) },
    license: { rights_holder: "Test", name: "Test", url: "https://example.test/license", spdx_id: "CC0-1.0", attribution: "Test" },
    rights: { stream: true, offline_download: false },
    coverage: {
      track_count: 114,
      surah_count: 114,
      expected_ayahs: 6236,
      timed_ayahs: 6236,
      complete: true,
      timings_complete: true,
    },
    timings: { available: true, segment_count: 6236, complete: true },
    capabilities: { listen: true, ayah_playback: true, memorization: true, offline: false },
    published_at: "2026-08-24T00:00:00Z",
    ...extra,
  };
}

const first = recitation("00000000-0000-7000-8000-000000000311", listeningReciter);
const teaching = recitation("00000000-0000-7000-8000-000000000312", mushafReciter, {
  style: "muallim",
  teaching_default: true,
});
const chosen = recitation("00000000-0000-7000-8000-000000000313", memorizationReciter);

test("the Mushaf and Memorization play the catalog's teaching reciter until the visitor chooses", () => {
  const storage = createMockStorage();
  const catalog = [first, teaching, chosen];

  assert.equal(learningRecitation(catalog, "mushaf", storage), teaching);
  assert.equal(learningRecitation(catalog, "memorization", storage), teaching);

  rememberReciterPreference(chosen.reciter, chosen, "mushaf", storage);
  assert.equal(learningRecitation(catalog, "mushaf", storage), chosen);
  assert.equal(learningRecitation(catalog, "memorization", storage), teaching);

  // A remembered reciter who left the catalog gives way to the teaching one.
  assert.equal(learningRecitation([first, teaching], "mushaf", storage), teaching);
  // Without a teaching reciter the caller keeps its own fallback.
  assert.equal(learningRecitation([first, chosen], "memorization", storage), undefined);
});

test("the Mushaf choice ignores the automatic fallback stored by the v1 key", () => {
  const storage = createMockStorage();
  storage.setItem(
    "quran_reciter_preference_v1:mushaf",
    JSON.stringify({ personKey: first.reciter.slug, reciterId: first.reciter.id, recitationId: first.id, style: "murattal" }),
  );

  assert.equal(loadReciterPreference("mushaf", storage), null);
  assert.equal(learningRecitation([first, teaching], "mushaf", storage), teaching);
});
