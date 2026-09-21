import assert from "node:assert/strict";
import test from "node:test";

import {
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
