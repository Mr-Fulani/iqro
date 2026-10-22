import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import { mergeCourseProgress, summarizeCourseProgress, type CourseProgress } from "./course-progress.ts";
import {
  courseLessons,
  lessonOutline,
  lessonStepSlugs,
  nextTajweedLesson,
  occurrenceAt,
  occurrenceRuns,
  occurrenceTiming,
  parseTajweedCourseDocument,
  parseTajweedExamplesPage,
  readTajweedProgress,
  recordTajweedStep,
  splitFirstExamples,
  tajweedProgressStorageKey,
  tajweedStepFromLocation,
  TajweedCourseDocumentError,
  writeTajweedProgress,
  type TajweedCourseExample,
} from "./tajweed-course.ts";

const documentJson = JSON.parse(
  readFileSync(new URL("../../../docs/tajweed/course-document.example.json", import.meta.url), "utf8"),
);
const examplesJson = JSON.parse(
  readFileSync(new URL("../e2e/fixtures/tajweed-course-examples.json", import.meta.url), "utf8"),
);

// 112:4 as the examples API sends it for the idgham-without-ghunnah lesson.
const ikhlas4: TajweedCourseExample = {
  verse_key: "112:4",
  surah_number: 112,
  ayah_number: 4,
  page_number: 604,
  words: [
    { position: 1, text: "وَلَمْ" },
    { position: 2, text: "يَكُن" },
    { position: 3, text: "لَّهُۥ" },
    { position: 4, text: "كُفُوًا" },
    { position: 5, text: "أَحَدٌۢ" },
  ],
  occurrences: [{ parts: [{ position: 2, start: 3, end: 5 }, { position: 3, start: 0, end: 1 }] }],
};

test("the contract example parses into lessons in course order with their targets", () => {
  const document = parseTajweedCourseDocument(documentJson);
  const lessons = courseLessons(document);
  assert.equal(lessons.length, 21);
  assert.equal(lessons[0]!.slug, "izhar");
  assert.equal(document.targets.izhar!.rule, null);
  assert.equal(document.targets.idgham_wo_ghunnah!.color, "#A3A5A5");
  assert.equal(nextTajweedLesson(document, "izhar")!.slug, "idgham-ghunnah");
  assert.equal(nextTajweedLesson(document, lessons.at(-1)!.slug), null);
  assert.throws(() => parseTajweedCourseDocument({ ...documentJson, schema_version: 2 }), TajweedCourseDocumentError);
  assert.throws(
    () => parseTajweedCourseDocument({ ...documentJson, lessons: [{ ...documentJson.lessons[0], target: "tafkhim" }] }),
    TajweedCourseDocumentError,
  );
});

test("lesson steps: the first page is read except its last example, which is found", () => {
  const examples = parseTajweedExamplesPage({ ...examplesJson.izhar, offset: 0, next_offset: 4 }).examples.slice(0, 4);
  const { shown, find } = splitFirstExamples(examples);
  assert.equal(shown.length, 3);
  assert.equal(find, examples[3]);
  assert.deepEqual(lessonStepSlugs(shown.length, true), ["intro", "how", "example-1", "example-2", "example-3", "find"]);
  assert.deepEqual(splitFirstExamples(examples.slice(0, 1)), { shown: examples.slice(0, 1), find: null });
  assert.deepEqual(lessonStepSlugs(0, false), ["intro", "how", "example-1"]);
  assert.deepEqual(lessonOutline({ slug: "izhar" }).steps.map((step) => step.slug), [
    "intro", "how", "example-1", "example-2", "example-3", "find",
  ]);
});

test("examples that do not fit the contract are dropped", () => {
  const page = parseTajweedExamplesPage({
    offset: 4,
    next_offset: null,
    examples: [ikhlas4, { ...ikhlas4, occurrences: [] }, { verse_key: "1:1" }],
  });
  assert.deepEqual(page, { offset: 4, next_offset: null, examples: [ikhlas4] });
  assert.deepEqual(parseTajweedExamplesPage(null), { offset: 0, next_offset: null, examples: [] });
});

test("a step comes from the hash, `step=` or the query", () => {
  assert.equal(tajweedStepFromLocation("#example-2", ""), "example-2");
  assert.equal(tajweedStepFromLocation("#step=find", ""), "find");
  assert.equal(tajweedStepFromLocation("", "?step=how"), "how");
  assert.equal(tajweedStepFromLocation("#example-0", ""), null);
  assert.equal(tajweedStepFromLocation("#fajr.r1.ruku", ""), null);
});

test("an occurrence lights its letters in each of its words and finds tapped words", () => {
  const occurrence = ikhlas4.occurrences[0]!;
  // A run never starts on a vowel mark: the damma stays with its kaf.
  assert.deepEqual(occurrenceRuns(ikhlas4.words[1]!, occurrence), [
    { text: "يَكُ‍", code: null },
    { text: "‍ن", code: "target" },
  ]);
  assert.deepEqual(occurrenceRuns(ikhlas4.words[2]!, occurrence), [
    { text: "لَّ‍", code: "target" },
    { text: "‍هُۥ", code: null },
  ]);
  assert.deepEqual(occurrenceRuns(ikhlas4.words[0]!, occurrence), [{ text: "وَلَمْ", code: null }]);
  assert.equal(occurrenceAt(ikhlas4, 3), 0);
  assert.equal(occurrenceAt(ikhlas4, 5), -1);
});

test("an occurrence plays from its first word to its last", () => {
  const words = [[1, 0, 400], [2, 400, 900], [3, 900, 1500], [4, 1500, 2100]];
  assert.deepEqual(occurrenceTiming(words, ikhlas4.occurrences[0]!), { startMs: 400, endMs: 1500 });
  assert.equal(occurrenceTiming([[2, 400, 900]], ikhlas4.occurrences[0]!), null);
  assert.equal(occurrenceTiming(undefined, ikhlas4.occurrences[0]!), null);
});

class MemoryStorage {
  values = new Map<string, string>();
  getItem(key: string) { return this.values.get(key) ?? null; }
  setItem(key: string, value: string) { this.values.set(key, value); }
}

test("progress is stored like the prayer course's, under its own key", () => {
  const storage = new MemoryStorage();
  const now = new Date("2026-10-22T10:00:00.000Z");
  let progress = recordTajweedStep(readTajweedProgress("tajweed", storage), "izhar", "example-2", "v1", { now });
  writeTajweedProgress(progress, "tajweed", storage);
  assert.equal(tajweedProgressStorageKey(), "tajweed.progress.tajweed");
  assert.deepEqual(JSON.parse(storage.values.get("tajweed.progress.tajweed")!), {
    lessons: {
      izhar: { status: "in_progress", step_slug: "example-2", content_version: "v1", updated_at: "2026-10-22T10:00:00.000Z" },
    },
  });
  progress = recordTajweedStep(progress, "izhar", "find", "v1", { completed: true, now });
  progress = recordTajweedStep(progress, "izhar", "intro", "v1", { now });
  assert.equal(progress.lessons.izhar!.status, "completed");
  const document = parseTajweedCourseDocument(documentJson);
  const summary = summarizeCourseProgress(courseLessons(document).map(lessonOutline), progress);
  assert.equal(summary.completed, 1);
  assert.deepEqual(summary.continueLesson, { slug: "idgham-ghunnah", stepSlug: null });
});

test("merging two copies keeps a passed lesson passed and takes the later record", () => {
  const entry = (status: "in_progress" | "completed", step: string, at: string) => ({
    status, step_slug: step, content_version: "v1", updated_at: at,
  });
  const phone: CourseProgress = {
    lessons: {
      izhar: entry("completed", "find", "2026-10-20T10:00:00.000Z"),
      iqlab: entry("in_progress", "how", "2026-10-21T10:00:00.000Z"),
    },
  };
  const browser: CourseProgress = {
    lessons: {
      izhar: entry("in_progress", "example-2", "2026-10-22T10:00:00.000Z"),
      iqlab: entry("in_progress", "intro", "2026-10-20T10:00:00.000Z"),
      ikhfa: entry("in_progress", "intro", "2026-10-22T09:00:00.000Z"),
    },
  };
  const merged = mergeCourseProgress(phone, browser);
  assert.deepEqual(merged.lessons.izhar, entry("completed", "example-2", "2026-10-22T10:00:00.000Z"));
  assert.deepEqual(merged.lessons.iqlab, phone.lessons.iqlab);
  assert.deepEqual(merged.lessons.ikhfa, browser.lessons.ikhfa);
  assert.deepEqual(mergeCourseProgress(browser, phone).lessons, merged.lessons);
});
