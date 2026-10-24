import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import type { CourseProgress } from "./course-progress.ts";
import {
  continueTarget,
  courseOutline,
  courseProgressStorageKey,
  isCourseSlug,
  isQuizSlug,
  parseCourseDocument,
  parseCourseList,
  readThematicProgress,
  recordLessonCompleted,
  recordLessonOpened,
  summarizeThematicProgress,
  writeThematicProgress,
  type CourseDocument,
} from "./thematic-courses.ts";

function example(name: string): Record<string, unknown> {
  return JSON.parse(readFileSync(new URL(`../../../docs/courses/${name}`, import.meta.url), "utf8"));
}

function exampleDocument(): CourseDocument {
  const result = parseCourseDocument(example("course-document.example.json"));
  assert.equal(result.outdated, false);
  return (result as { document: CourseDocument }).document;
}

function memoryStorage() {
  const values = new Map<string, string>();
  return {
    values,
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => void values.set(key, value),
  };
}

test("course and quiz slugs are lowercase slugs outside the reserved list", () => {
  for (const slug of ["ramadan", "ramadan-basics", "hajj-2027"]) {
    assert.equal(isCourseSlug(slug), true, slug);
    assert.equal(isQuizSlug(slug), true, slug);
  }
  for (const slug of ["", "Ramadan", "ramadan_", "-ramadan", "ramadan--x", "../ramadan", "a".repeat(65)]) {
    assert.equal(isCourseSlug(slug), false, slug);
    assert.equal(isQuizSlug(slug), false, slug);
  }
  for (const slug of ["salah", "tajweed", "quiz", "courses", "new", "preview", "events"]) {
    assert.equal(isCourseSlug(slug), false, slug);
    assert.equal(isQuizSlug(slug), false, slug);
  }
});

test("the contract examples parse; unknown fields are ignored", () => {
  const listPayload = example("course-list.example.json");
  const [course] = parseCourseList(listPayload);
  assert.equal(course!.slug, "ramadan");
  assert.equal(course!.lesson_count, 3);
  assert.equal(course!.cover?.thumb_url.endsWith("-640.webp"), true);

  const document = exampleDocument();
  assert.deepEqual(document.lessons.map((lesson) => lesson.slug), ["smysl-posta", "namerenie", "taraviikh"]);
  assert.deepEqual(document.course.languages, ["ru"]);
  assert.equal(document.lessons[1]!.notes.at(-1)!.type, "note");

  const extended = example("course-document.example.json");
  extended.future_field = { anything: true };
  (extended.course as Record<string, unknown>).trailer = "x";
  ((extended.lessons as Record<string, unknown>[])[0]!).video = { url: "https://media.iqro.forum/v.mp4" };
  assert.deepEqual(parseCourseDocument(extended), { outdated: false, document });
});

test("a newer schema asks for a reload; a broken document is an error", () => {
  const newer = example("course-document.example.json");
  newer.schema_version = 2;
  newer.lessons = "a shape this site cannot know";
  assert.deepEqual(parseCourseDocument(newer), { outdated: true });

  for (const change of [
    (value: Record<string, unknown>) => { value.schema_version = 0; },
    (value: Record<string, unknown>) => { (value.course as Record<string, unknown>).slug = "salah"; },
    (value: Record<string, unknown>) => { ((value.lessons as Record<string, unknown>[])[0]!).slug = "Bad Slug"; },
    (value: Record<string, unknown>) => {
      ((value.lessons as { notes: Record<string, unknown>[] }[])[0]!).notes[0]!.type = "video";
    },
    (value: Record<string, unknown>) => {
      (value.course as Record<string, unknown>).cover = { url: "javascript:alert(1)", thumb_url: "", width: 1, height: 1 };
    },
  ]) {
    const broken = example("course-document.example.json");
    change(broken);
    assert.throws(() => parseCourseDocument(broken), /Invalid course document/);
  }
});

test("progress uses the shared course-progress shape under courses.progress.<slug>", () => {
  const storage = memoryStorage();
  const now = new Date("2026-10-24T10:00:00Z");
  let progress: CourseProgress = { lessons: {} };
  progress = recordLessonOpened(progress, "namerenie", "1", now);
  progress = recordLessonCompleted(progress, "smysl-posta", "1", now);
  writeThematicProgress(progress, "ramadan", storage);

  assert.equal(courseProgressStorageKey("ramadan"), "courses.progress.ramadan");
  assert.deepEqual(JSON.parse(storage.values.get("courses.progress.ramadan")!), {
    lessons: {
      namerenie: { status: "in_progress", step_slug: "", content_version: "1", updated_at: now.toISOString() },
      "smysl-posta": { status: "completed", step_slug: "", content_version: "1", updated_at: now.toISOString() },
    },
  });
  assert.deepEqual(readThematicProgress("ramadan", storage), progress);

  // Reopening a completed lesson keeps it completed.
  const reopened = recordLessonOpened(progress, "smysl-posta", "2", new Date("2026-10-25T10:00:00Z"));
  assert.equal(reopened.lessons["smysl-posta"]!.status, "completed");
});

test("summary and «Continue» follow the first unfinished lesson of the course opened last", () => {
  const ramadan = courseOutline(exampleDocument());
  const hajj = { slug: "hajj", version: "1", title: "Хадж", lessons: [{ slug: "ihram", number: 1, title: "Ихрам" }] };
  const progress: Record<string, CourseProgress> = {
    ramadan: {
      lessons: {
        "smysl-posta": { status: "completed", step_slug: "", content_version: "1", updated_at: "2026-10-24T10:00:00.000Z" },
        // A lesson gone from the release does not count.
        "old-lesson": { status: "completed", step_slug: "", content_version: "0", updated_at: "2026-10-20T10:00:00.000Z" },
      },
    },
    hajj: {
      lessons: { ihram: { status: "in_progress", step_slug: "", content_version: "1", updated_at: "2026-10-23T10:00:00.000Z" } },
    },
  };
  const progressOf = (slug: string) => progress[slug] ?? { lessons: {} };

  assert.deepEqual(summarizeThematicProgress(ramadan, progress.ramadan!), {
    completed: 1,
    total: 3,
    started: true,
    nextLesson: { slug: "namerenie", number: 2, title: "Намерение (ният)" },
    updatedAt: "2026-10-24T10:00:00.000Z",
  });
  assert.equal(continueTarget([hajj, ramadan], progressOf)?.lesson.slug, "namerenie");

  progress.ramadan!.lessons.namerenie = { ...progress.ramadan!.lessons["smysl-posta"]!, status: "completed" };
  progress.ramadan!.lessons.taraviikh = { ...progress.ramadan!.lessons["smysl-posta"]!, status: "completed" };
  // A finished course has nothing to continue, so the other one is offered.
  assert.equal(continueTarget([hajj, ramadan], progressOf)?.course.slug, "hajj");
  assert.equal(continueTarget([ramadan], progressOf), null);
  assert.equal(continueTarget([ramadan], () => ({ lessons: {} })), null);
});
