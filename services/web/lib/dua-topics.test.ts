import assert from "node:assert/strict";
import test from "node:test";

import type { DuaCategory, DuaEntry } from "./api.ts";
import { duaTopics, topicCategories, topicEntries } from "./dua-topics.ts";

function category(number: number, collection = "hisn-al-muslim"): DuaCategory {
  return { id: `${collection}-${number}`, source_number: number, collection,
    slug: `chapter-${number}`, title: `Chapter ${number}`, collection_title: "",
    collection_version: "full-v1", entry_count: 1 };
}

test("19 localized topics cover every source chapter without accidental duplication", () => {
  assert.equal(duaTopics.length, 19);
  assert.equal(new Set(duaTopics.map((topic) => topic.id)).size, 19);
  for (let number = 1; number <= 132; number++) {
    const matches = duaTopics.filter((topic) => topicCategories(topic, [category(number)]).length);
    assert.equal(matches.length, number === 27 ? 2 : 1, `Chapter ${number}`);
  }
  for (const topic of duaTopics) {
    for (const locale of ["ru", "en", "ar", "tr"] as const) {
      assert.ok(topic.title[locale]);
      assert.ok(topic.description[locale]);
    }
  }
});

test("collection boundaries prevent chapter numbers from selecting another collection", () => {
  const morning = duaTopics.find((topic) => topic.id === "morning")!;
  assert.deepEqual(topicCategories(morning, [category(27, "supplications-from-quran")]), []);
});

test("source-based morning and evening subsets retain the full chapter between them", () => {
  const morning = duaTopics.find((topic) => topic.id === "morning")!;
  const evening = duaTopics.find((topic) => topic.id === "evening")!;
  const entries = Array.from({ length: 24 }, (_, index) => ({
    source_number: index + 75, collection: "hisn-al-muslim",
    category: { source_number: 27 },
  } as DuaEntry));
  const am = topicEntries(morning, entries).map((entry) => entry.source_number);
  const pm = topicEntries(evening, entries).map((entry) => entry.source_number);
  assert.equal(am.length, 23);
  assert.equal(pm.length, 21);
  assert.equal(new Set([...am, ...pm]).size, 24);
  assert.equal(am.includes(97), false);
  assert.equal(pm.includes(97), true);
  for (const number of [93, 94, 95]) {
    assert.equal(am.includes(number), true);
    assert.equal(pm.includes(number), false);
  }
  assert.ok(am.includes(96) && pm.includes(96));
});
