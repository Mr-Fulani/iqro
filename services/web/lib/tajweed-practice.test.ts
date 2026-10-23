import assert from "node:assert/strict";
import test from "node:test";

import {
  applyPracticeSession,
  dueReviewKeys,
  emptyPracticeState,
  localDate,
  parsePracticeState,
  parsePracticeStore,
  parsePracticeTasks,
  PRACTICE_PENDING,
  recordPracticeSession,
  shownStreak,
  type PracticeAnswer,
  type PracticeSession,
} from "./tajweed-practice.ts";

const KEY = "find~112:4~izhar";

function answer(key: string, correct: boolean, at: string): PracticeAnswer {
  const [type, , target] = key.split("~") as [PracticeAnswer["type"], string, string];
  return { key, target, type, correct, at };
}

function session(id: string, day: string, answers: PracticeAnswer[]): PracticeSession {
  return { id, course: "tajweed", local_date: day, finished_at: `${day}T12:00:00.000Z`, answers };
}

// The same cases as the backend's tests/test_tajweed_practice.py: one algorithm, two places.
test("score counts right answers and the streak counts days in a row", () => {
  let state = emptyPracticeState();
  state = applyPracticeSession(state, session("a", "2026-10-20", [answer(KEY, true, "2026-10-20T10:00:00Z")]));
  state = applyPracticeSession(state, session("b", "2026-10-20", [answer(KEY, false, "2026-10-20T11:00:00Z")]));
  state = applyPracticeSession(state, session("c", "2026-10-21", []));
  assert.deepEqual([state.answers, state.correct, state.streak.current, state.streak.best], [2, 1, 2, 2]);
  state = applyPracticeSession(state, session("d", "2026-10-25", []));
  assert.deepEqual(state.streak, { current: 1, best: 2, last_date: "2026-10-25" });
  assert.equal(state.score, 1);
  assert.equal(state.sessions, 4);
});

test("a mistake comes back after one then three days until it is learned", () => {
  let state = applyPracticeSession(emptyPracticeState(), session("a", "2026-10-20", [answer(KEY, false, "2026-10-20T10:00:00Z")]));
  assert.deepEqual(state.review, [{ key: KEY, target: "izhar", type: "find", box: 1, due_at: "2026-10-20T10:00:00.000Z" }]);
  state = applyPracticeSession(state, session("b", "2026-10-20", [answer(KEY, true, "2026-10-20T11:00:00Z")]));
  assert.deepEqual([state.review[0]!.box, state.review[0]!.due_at], [2, "2026-10-21T11:00:00.000Z"]);
  state = applyPracticeSession(state, session("c", "2026-10-21", [answer(KEY, true, "2026-10-21T11:00:00Z")]));
  assert.deepEqual([state.review[0]!.box, state.review[0]!.due_at], [3, "2026-10-24T11:00:00.000Z"]);
  state = applyPracticeSession(state, session("d", "2026-10-24", [answer(KEY, true, "2026-10-24T11:00:00Z")]));
  assert.deepEqual(state.review, []);
  state = applyPracticeSession(state, session("e", "2026-10-24", [answer(KEY, true, "2026-10-24T12:00:00Z")]));
  assert.deepEqual(state.review, []);
});

test("due review keys come oldest first and the shown streak breaks after a missed day", () => {
  let state = emptyPracticeState();
  state = applyPracticeSession(state, session("a", "2026-10-20", [
    answer("identify~2:2~idgham_wo_ghunnah", false, "2026-10-20T10:05:00Z"),
    answer(KEY, false, "2026-10-20T10:01:00Z"),
  ]));
  assert.deepEqual(dueReviewKeys(state, new Date("2026-10-20T10:03:00Z")), [KEY]);
  assert.deepEqual(dueReviewKeys(state, new Date("2026-10-21T00:00:00Z")), [KEY, "identify~2:2~idgham_wo_ghunnah"]);
  assert.equal(shownStreak(state, "2026-10-20"), 1);
  assert.equal(shownStreak(state, "2026-10-21"), 1);
  assert.equal(shownStreak(state, "2026-10-22"), 0);
  assert.equal(localDate(new Date(2026, 9, 5, 23, 30)), "2026-10-05");
});

test("a finished session counts at once and waits to be sent", () => {
  const first = recordPracticeSession(parsePracticeStore(null), session("a", "2026-10-20", [answer(KEY, true, "2026-10-20T10:00:00Z")]));
  assert.equal(first.state.score, 1);
  assert.deepEqual(first.pending.map((item) => item.id), ["a"]);
  const stored = parsePracticeStore(JSON.stringify(first));
  assert.deepEqual(stored, first);
  let store = stored;
  for (let index = 0; index < PRACTICE_PENDING + 5; index += 1) {
    store = recordPracticeSession(store, session(`s${index}`, "2026-10-21", []));
  }
  assert.equal(store.pending.length, PRACTICE_PENDING);
  assert.equal(store.pending[0]!.id, "s5");
  assert.deepEqual(parsePracticeStore("not json"), { state: emptyPracticeState(), pending: [] });
  assert.equal(parsePracticeState({ score: 1 }), null);
});

test("tasks that do not fit the contract are dropped", () => {
  const example = {
    verse_key: "112:4",
    surah_number: 112,
    ayah_number: 4,
    page_number: 604,
    words: [{ position: 4, text: "كُفُوًا" }, { position: 5, text: "أَحَدٌۢ" }],
    occurrences: [{ parts: [{ position: 4, start: 4, end: 6 }, { position: 5, start: 0, end: 2 }] }],
  };
  const tasks = parsePracticeTasks({
    seed: 1,
    tasks: [
      { key: "find~112:4~izhar", type: "find", target: "izhar", review: true, example, focus: 0 },
      { key: "identify~112:4~izhar", type: "identify", target: "izhar", review: false, example, focus: 0, options: ["qalaqah", "izhar"] },
      { key: "identify~112:4~izhar", type: "identify", target: "izhar", example, focus: 0, options: ["qalaqah"] },
      { key: "listen~112:4~izhar", type: "listen", target: "izhar", example, focus: 3, options: ["izhar"] },
      { key: "guess~112:4~izhar", type: "guess", target: "izhar", example, focus: 0 },
    ],
  });
  assert.deepEqual(tasks.map((task) => [task.type, task.review, task.options]), [
    ["find", true, []],
    ["identify", false, ["qalaqah", "izhar"]],
  ]);
});
