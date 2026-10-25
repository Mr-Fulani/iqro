import assert from "node:assert/strict";
import test from "node:test";

import {
  eventBatches,
  flushCourseEvents,
  isVideoFinished,
  parseRating,
  parseVotes,
  ratingStorageKey,
  readRating,
  readVotes,
  recordVote,
  reportContext,
  reportSubject,
  trackCourseEvent,
  voteStorageKey,
  writeRating,
  type CourseEvent,
} from "./course-feedback.ts";

function memoryStorage(): Pick<Storage, "getItem" | "setItem"> & { values: Map<string, string> } {
  const values = new Map<string, string>();
  return {
    values,
    getItem: (key) => values.get(key) ?? null,
    setItem: (key, value) => void values.set(key, value),
  };
}

const opened: CourseEvent = { course: "ramadan", lesson: "namerenie", event: "lesson_opened" };

test("events go in batches of at most 50, in order", () => {
  const events = Array.from({ length: 101 }, (_, index) => ({ ...opened, lesson: `lesson-${index}` }));
  const bodies = eventBatches(events).map((body) => JSON.parse(body) as { platform: string; events: CourseEvent[] });

  assert.deepEqual(bodies.map((body) => body.events.length), [50, 50, 1]);
  assert.equal(bodies[0]!.platform, "web");
  assert.equal(bodies[2]!.events[0]!.lesson, "lesson-100");
  assert.deepEqual(eventBatches([]), []);
});

test("the queue sends everything once and then is empty", () => {
  trackCourseEvent(opened);
  trackCourseEvent({ ...opened, event: "lesson_helpful" });
  const sent: string[] = [];

  flushCourseEvents((body) => sent.push(body));
  flushCourseEvents((body) => sent.push(body));

  assert.equal(sent.length, 1);
  assert.deepEqual(JSON.parse(sent[0]!), {
    platform: "web",
    events: [opened, { ...opened, event: "lesson_helpful" }],
  });
});

test("a video is watched from 90 percent", () => {
  assert.equal(isVideoFinished(8_999, 10_000), false);
  assert.equal(isVideoFinished(9_000, 10_000), true);
  assert.equal(isVideoFinished(5_000, 0), false);
});

test("a lesson takes one vote on the device", () => {
  const storage = memoryStorage();

  assert.equal(voteStorageKey("ramadan"), "courses.vote.ramadan");
  assert.equal(recordVote("ramadan", "namerenie", "helpful", storage), true);
  assert.equal(recordVote("ramadan", "namerenie", "not_helpful", storage), false);
  assert.equal(recordVote("ramadan", "taraviikh", "not_helpful", storage), true);
  assert.deepEqual(readVotes("ramadan", storage), { namerenie: "helpful", taraviikh: "not_helpful" });
  assert.deepEqual(parseVotes('{"a": "helpful", "b": "maybe", "c": 1}'), { a: "helpful" });
  assert.deepEqual(parseVotes("not json"), {});
});

test("the rating the device remembers", () => {
  const storage = memoryStorage();
  const rating = { stars: 4, comment: "Спасибо", updated_at: "2027-01-20T10:00:00Z" };

  writeRating("ramadan", rating, storage);

  assert.equal(ratingStorageKey("ramadan"), "courses.rating.ramadan");
  assert.deepEqual(readRating("ramadan", storage), rating);
  assert.equal(parseRating('{"stars": 6}'), null);
  assert.equal(parseRating('{"stars": 2.5}'), null);
  assert.deepEqual(parseRating('{"stars": 1}'), { stars: 1, comment: "", updated_at: "" });
});

test("a lesson report names the course, lesson, release and video moment", () => {
  assert.equal(reportSubject("Рамадан", 2, "Намерение (ният)"), "Рамадан · 2. Намерение (ният)");
  const long = reportSubject("К".repeat(100), 12, "Т".repeat(100));
  assert.equal(long.length, 160);
  assert.ok(long.endsWith("…"));

  assert.deepEqual(reportContext("ramadan", "namerenie", "3", 252_000), {
    course_slug: "ramadan",
    lesson_slug: "namerenie",
    content_version: "3",
    route: "/courses/ramadan/namerenie",
    client_platform: "web",
    playback_ms: 252_000,
  });
  assert.equal("playback_ms" in reportContext("ramadan", "namerenie", "3", undefined), false);
  assert.deepEqual(reportContext("ramadan", "namerenie", "3", undefined, 4), {
    course_slug: "ramadan",
    lesson_slug: "namerenie",
    content_version: "3",
    route: "/courses/ramadan/namerenie",
    client_platform: "web",
    slide_number: 4,
  });
});
