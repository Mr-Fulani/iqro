import assert from "node:assert/strict";
import test from "node:test";

import type { DuaCategory } from "./api.ts";
import { duaChaptersMatching } from "./dua-search.ts";

const chapter = (number: number, title: string): DuaCategory => ({
  id: `c${number}`, slug: `chapter-${number}`, title, entry_count: 1,
  collection: "hisn-al-muslim", collection_title: "", collection_version: "v1",
  source_number: number,
});

// Cases of dua_search_test.dart.
const chapters = [
  chapter(26, "СЛОВА МОЛЬБЫ, ПРОИЗНОСИМЫЕ ВО ВРЕМЯ МОЛИТВЫ ИСПРАШИВАНИЯ ПОМОЩИ"),
  chapter(32, "СЛОВА ОБРАЩЕНИЯ К АЛЛАХУ С МОЛЬБОЙ ВО ВРЕМЯ ВИТРА"),
  chapter(125, "ЧТО ДОЛЖЕН СКАЗАТЬ ТОТ, КТО ОПАСАЕТСЯ СГЛАЗИТЬ НЕЧТО"),
];
const found = (query: string) =>
  duaChaptersMatching(query, chapters).map((item) => item.source_number);

test("istikhara is found by the name people know it by", () => {
  for (const query of ["истихара", "Истихару", "istikharah", "istihare", "استخارة"]) {
    assert.deepEqual(found(query), [26], query);
  }
});

test("qunut leads to the witr chapter", () => {
  assert.deepEqual(found("кунут"), [32]);
});

test("a word of a chapter title finds it", () => {
  assert.deepEqual(found("сглаз"), [125]);
});

test("too short a query finds no chapter", () => {
  assert.deepEqual(found("ис"), []);
});
