import assert from "node:assert/strict";
import test from "node:test";

import { isCourseSlug, isQuizSlug } from "./thematic-courses.ts";

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
