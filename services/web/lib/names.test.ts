import assert from "node:assert/strict";
import { readdirSync, readFileSync } from "node:fs";
import test from "node:test";

import {
  isNameLearned,
  learnedCount,
  markNameSeen,
  nameLabel,
  namesCounter,
  namesProgressStorageKey,
  parseNamesDocument,
  parseNamesProgress,
  readNamesProgress,
  seenCount,
  setNameLearned,
  stripHarakat,
  wheelIndex,
  wheelTarget,
  writeNamesProgress,
} from "./names.ts";
import { RECORDED_NAMES } from "./names-audio.ts";
import { flushCourseEvents, type CourseEvent } from "./course-feedback.ts";

// The contract example is the shared source of truth for the backend, the app and the site.
const example = JSON.parse(
  readFileSync(new URL("../../../docs/names-of-allah/names-document.example.json", import.meta.url), "utf8"),
);

function memoryStorage() {
  const values = new Map<string, string>();
  return {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => void values.set(key, value),
  };
}

test("the contract example parses", () => {
  const document = parseNamesDocument(example);
  assert.equal(document.collection.slug, "asma-al-husna");
  assert.deepEqual(document.names.map((name) => name.position), [1, 2, 3, 4]);
  assert.deepEqual(document.names[0].ayah, { surah: 55, ayah: 1, word: 1 });
  // A name of two words has an ayah but no word to play; a name from the Sunnah has neither.
  assert.equal(document.names[2].ayah?.word, null);
  assert.equal(document.names[3].ayah, null);
});

test("a list that does not fit the contract is rejected", () => {
  const broken = (change: (document: typeof example) => void) => {
    const copy = structuredClone(example);
    change(copy);
    return copy;
  };
  for (const document of [
    null,
    { collection: example.collection, names: [] },
    broken((copy) => { copy.names[1].position = 5; }),
    broken((copy) => { copy.names[1].slug = "ar-rahman"; }),
    broken((copy) => { copy.names[0].slug = "Ar Rahman"; }),
    broken((copy) => { copy.names[0].arabic = ""; }),
    broken((copy) => { delete copy.names[0].tafsir; }),
    broken((copy) => { copy.names[0].ayah.surah = 0; }),
    broken((copy) => { copy.names[0].ayah.word = "1"; }),
    broken((copy) => { delete copy.collection.tafsir_source; }),
  ]) {
    assert.throws(() => parseNamesDocument(document));
  }
});

test("the Arabic document shows the name itself", () => {
  const [name] = parseNamesDocument(example).names;
  assert.equal(nameLabel(name), "Ар-Рахман");
  assert.equal(nameLabel({ ...name, transliteration: "" }), name.arabic);
  assert.equal(stripHarakat("الرَّحْمَٰنُ"), "الرحمن");
});

test("seen and learned are marks of one record", () => {
  const { names } = parseNamesDocument(example);
  const first = new Date("2026-11-12T10:00:00Z");
  const later = new Date("2026-11-12T11:00:00Z");
  let progress = markNameSeen({ lessons: {} }, "ar-rahman", "v1", first);
  assert.equal(progress.lessons["ar-rahman"].status, "in_progress");
  assert.equal(seenCount(progress, names), 1);
  assert.equal(isNameLearned(progress, "ar-rahman"), false);
  // Settling on the name again changes nothing: the record keeps its time.
  assert.equal(markNameSeen(progress, "ar-rahman", "v2", later), progress);

  progress = setNameLearned(progress, "ar-rahman", true, "v1", later);
  assert.equal(isNameLearned(progress, "ar-rahman"), true);
  assert.equal(markNameSeen(progress, "ar-rahman", "v1", later), progress);
  // «Выучено» taken back leaves the name seen.
  progress = setNameLearned(progress, "ar-rahman", false, "v1", later);
  assert.equal(isNameLearned(progress, "ar-rahman"), false);
  assert.equal(seenCount(progress, names), 1);
  // A mark of a name that left the list is not counted.
  assert.equal(seenCount(markNameSeen(progress, "gone", "v1", later), names), 1);
  assert.equal(seenCount(null, names), 0);
});

test("marks are stored in the course-progress format", () => {
  const storage = memoryStorage();
  const progress = setNameLearned({ lessons: {} }, "ar-rahman", true, "v1", new Date("2026-11-12T10:00:00Z"));
  writeNamesProgress(progress, "asma-al-husna", storage);
  assert.equal(namesProgressStorageKey(), "names.progress.asma-al-husna");
  assert.deepEqual(JSON.parse(storage.getItem("names.progress.asma-al-husna") ?? ""), {
    lessons: {
      "ar-rahman": { status: "completed", step_slug: "", content_version: "v1", updated_at: "2026-11-12T10:00:00.000Z" },
    },
  });
  assert.deepEqual(readNamesProgress("asma-al-husna", storage), progress);
  assert.deepEqual(parseNamesProgress("not json"), { lessons: {} });
});

test("the card of the course catalog counts the names marked learned", () => {
  let progress = setNameLearned({ lessons: {} }, "ar-rahman", true, "v1");
  progress = markNameSeen(progress, "ar-rahim", "v1");
  progress = setNameLearned(progress, "al-jamil", true, "v1");
  progress = setNameLearned(progress, "al-jamil", false, "v1");

  assert.equal(learnedCount(progress), 1);
  assert.equal(learnedCount({ lessons: {} }), 0);
  assert.equal(learnedCount(null), 0);
});

test("the section and each name count once per page view, like a lesson of a course", () => {
  const sent: CourseEvent[] = [];
  const counter = namesCounter("asma-al-husna", (event) => sent.push(event));

  counter("section_opened");
  counter("section_opened");
  counter("lesson_opened", "ar-rahman");
  // The card was closed and opened again, «Выучено» taken back and set again.
  counter("lesson_opened", "ar-rahman");
  counter("lesson_completed", "ar-rahman");
  counter("lesson_completed", "ar-rahman");
  counter("lesson_opened", "al-jamil");

  assert.deepEqual(sent, [
    { course: "asma-al-husna", lesson: "", event: "section_opened" },
    { course: "asma-al-husna", lesson: "ar-rahman", event: "lesson_opened" },
    { course: "asma-al-husna", lesson: "ar-rahman", event: "lesson_completed" },
    { course: "asma-al-husna", lesson: "al-jamil", event: "lesson_opened" },
  ]);

  // The next page view counts anew, through the queue of the courses.
  namesCounter("asma-al-husna")("section_opened");
  const bodies: string[] = [];
  flushCourseEvents((body) => bodies.push(body));
  assert.deepEqual(bodies.map((body) => JSON.parse(body)), [
    { platform: "web", events: [{ course: "asma-al-husna", lesson: "", event: "section_opened" }] },
  ]);
});

test("the wheel goes round and takes the short way", () => {
  assert.equal(wheelIndex(0, 99), 0);
  assert.equal(wheelIndex(99, 99), 0);
  assert.equal(wheelIndex(-1, 99), 98);
  assert.equal(wheelIndex(100.4, 99), 1);
  assert.equal(wheelTarget(0, 1, 99), 1);
  assert.equal(wheelTarget(0, 98, 99), -1);
  assert.equal(wheelTarget(98, 0, 99), 99);
  assert.equal(wheelTarget(198, 5, 99), 203);
  assert.equal(wheelTarget(-1, 0, 99), 0);
});

test("every name of the list is recorded in every language", () => {
  const list = JSON.parse(
    readFileSync(
      new URL("../../backend/src/quran_backend/modules/names/data/asma-al-husna.json", import.meta.url),
      "utf8",
    ),
  ) as { names: { slug: string }[] };
  const slugs = list.names.map((name) => name.slug).sort();
  assert.deepEqual([...RECORDED_NAMES].sort(), slugs);
  // The name with its meaning in ru, en and tr; the name alone in `ar`.
  for (const language of ["ar", "ru", "en", "tr"]) {
    const files = readdirSync(new URL(`../public/names-audio/${language}/`, import.meta.url))
      .filter((file) => file.endsWith(".mp3"))
      .map((file) => file.replace(".mp3", ""));
    assert.deepEqual(files.sort(), slugs, language);
  }
});
