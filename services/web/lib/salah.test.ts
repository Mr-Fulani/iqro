import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

import {
  findSalahLesson,
  formulaAudioRange,
  isSalahRuling,
  nextSalahLesson,
  orderedLessons,
  parseSalahCourseDocument,
  parseSalahProgress,
  readSalahProgress,
  recordSalahStep,
  resumeStepIndex,
  salahLessonBundle,
  salahProgressStorageKey,
  SalahDocumentError,
  stepRepeatTarget,
  stepSlugFromLocation,
  summarizeSalahProgress,
  writeSalahProgress,
  type SalahLesson,
  type SalahProgress,
} from "./salah.ts";

// The contract example is the shared source of truth for the backend, the app and the site.
const example = JSON.parse(
  readFileSync(new URL("../../../docs/salah/course-document.example.json", import.meta.url), "utf8"),
) as Record<string, unknown>;
const course = parseSalahCourseDocument(example);

function lesson(slug: string): SalahLesson {
  const found = findSalahLesson(course, slug);
  assert.ok(found, slug);
  return found;
}

function memoryStorage(initial: Record<string, string> = {}) {
  const values = new Map(Object.entries(initial));
  return {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => void values.set(key, value),
    values,
  };
}

test("the contract example parses into ordered lessons", () => {
  assert.equal(course.course.slug, "hanbali-umdah");
  assert.deepEqual(orderedLessons(course).map((item) => item.slug), ["what-is-salah", "wudu", "fajr"]);
  assert.equal(lesson("fajr").prayer?.rakats, 2);
  assert.equal(nextSalahLesson(course, "wudu")?.slug, "fajr");
  assert.equal(nextSalahLesson(course, "fajr"), null);
});

test("prayer kinds and rulings from a newer course do not break the document", () => {
  assert.equal(lesson("fajr").prayer?.kind_title, "Фард");
  const lessons = example.lessons as Record<string, unknown>[];
  const eid = {
    ...lessons[2],
    slug: "eid",
    prayer: { code: "eid", kind: "eid", kind_title: "Праздничный", rakats: 2 },
  };
  const newer = parseSalahCourseDocument({ ...example, lessons: [...lessons, eid] });
  assert.equal(findSalahLesson(newer, "eid")?.prayer?.kind_title, "Праздничный");
  assert.equal(isSalahRuling("rukn"), true);
  assert.equal(isSalahRuling("mustahabb"), false);
  assert.equal(isSalahRuling(undefined), false);
});

test("the parser rejects unsupported or broken documents", () => {
  assert.throws(() => parseSalahCourseDocument({ ...example, schema_version: 2 }), SalahDocumentError);
  assert.throws(() => parseSalahCourseDocument(null), SalahDocumentError);
  const lessons = example.lessons as Record<string, unknown>[];
  assert.throws(
    () => parseSalahCourseDocument({ ...example, lessons: [...lessons, lessons[0]] }),
    /duplicated/,
  );
  assert.throws(
    () => parseSalahCourseDocument({ ...example, lessons: [{ ...lessons[0], steps: [] }] }),
    /non-empty/,
  );
  assert.throws(
    () => parseSalahCourseDocument({ ...example, lessons: [{ ...lessons[2], prayer: undefined }] }),
    /prayer is missing/,
  );
});

test("dangling formula, media and lesson references are dropped", () => {
  const lessons = example.lessons as { steps: Record<string, unknown>[] }[];
  const broken = parseSalahCourseDocument({
    ...example,
    sections: [{ slug: "basics", title: "Основы", lessons: ["what-is-salah", "missing"] }],
    lessons: [{
      ...lessons[0],
      steps: [{ ...lessons[0]!.steps[0], formulas: ["takbir", "missing"], media: "missing" }],
    }],
  });
  assert.deepEqual(broken.sections[0]!.lessons, ["what-is-salah"]);
  assert.deepEqual(broken.lessons[0]!.steps[0]!.formulas, ["takbir"]);
  assert.equal(broken.lessons[0]!.steps[0]!.media, undefined);
});

test("a lesson bundle carries only the formulas and media its steps use", () => {
  const bundle = salahLessonBundle(course, lesson("wudu"));
  assert.equal(bundle.courseVersion, "2026-10-18");
  assert.deepEqual(Object.keys(bundle.formulas), []);
  assert.deepEqual(Object.keys(bundle.media), ["wudu-face"]);
  const fajr = salahLessonBundle(course, lesson("fajr"));
  assert.deepEqual(Object.keys(fajr.formulas).sort(), ["fatiha", "ruku-tasbih", "takbir", "tashahhud", "taslim"]);
});

test("a step is read from the hash or the query", () => {
  assert.equal(stepSlugFromLocation("#fajr.r1.ruku", ""), "fajr.r1.ruku");
  assert.equal(stepSlugFromLocation("#step=fajr.r2.taslim", ""), "fajr.r2.taslim");
  assert.equal(stepSlugFromLocation("", "?step=wudu.face"), "wudu.face");
  assert.equal(stepSlugFromLocation("#<script>", ""), null);
  assert.equal(stepSlugFromLocation("#%E0%A4%A", ""), null);
  assert.equal(stepSlugFromLocation("", ""), null);
});

test("audio ranges come from explicit bounds or ayah segments", () => {
  assert.deepEqual(formulaAudioRange({ url: "a.mp3" }), { start: 0, end: null });
  assert.deepEqual(formulaAudioRange(course.formulas.fatiha!.audio!), { start: 0, end: 11 });
  assert.deepEqual(formulaAudioRange({ url: "a.mp3", start_ms: 1500, end_ms: 4000 }), { start: 1.5, end: 4 });
});

test("a step counter is shown only when no formula already counts the repeats", () => {
  const wudu = lesson("wudu");
  assert.equal(stepRepeatTarget(wudu.steps[1]!, course.formulas), 3);
  assert.equal(stepRepeatTarget(wudu.steps[0]!, course.formulas), null);
  const ruku = lesson("fajr").steps.find((step) => step.slug === "fajr.r1.ruku")!;
  assert.equal(stepRepeatTarget(ruku, course.formulas), null);
});

test("progress resumes the saved step and starts over when the step is gone", () => {
  const fajr = lesson("fajr");
  const saved = (step_slug: string, status: "in_progress" | "completed" = "in_progress") => ({
    status, step_slug, content_version: "2026-10-18", updated_at: "2026-10-18T10:00:00.000Z",
  });
  assert.equal(resumeStepIndex(fajr, undefined, null), 0);
  assert.equal(resumeStepIndex(fajr, saved("fajr.r1.ruku"), null), 2);
  assert.equal(resumeStepIndex(fajr, saved("fajr.r3.ruku"), null), 0);
  assert.equal(resumeStepIndex(fajr, saved("fajr.r2.taslim", "completed"), null), 0);
  assert.equal(resumeStepIndex(fajr, saved("fajr.r1.ruku"), "fajr.r2.tashahhud"), 3);
  assert.equal(resumeStepIndex(fajr, saved("fajr.r1.ruku"), "wudu.face"), 2);
});

test("a completed lesson stays completed when it is reopened", () => {
  const now = new Date("2026-10-18T12:00:00Z");
  let progress: SalahProgress = { lessons: {} };
  progress = recordSalahStep(progress, "wudu", "wudu.face", "2026-10-18", { completed: true, now });
  progress = recordSalahStep(progress, "wudu", "wudu.intention", "2026-10-19", { now });
  assert.deepEqual(progress.lessons.wudu, {
    status: "completed",
    step_slug: "wudu.intention",
    content_version: "2026-10-19",
    updated_at: "2026-10-18T12:00:00.000Z",
  });
});

test("progress round-trips through storage in the app's shape and ignores junk", () => {
  const storage = memoryStorage();
  const progress = recordSalahStep({ lessons: {} }, "fajr", "fajr.r1.ruku", "2026-10-18", {
    now: new Date("2026-10-18T12:00:00Z"),
  });
  writeSalahProgress(progress, "hanbali-umdah", storage);
  assert.equal(salahProgressStorageKey(), "salah.progress.hanbali-umdah");
  assert.deepEqual(JSON.parse(storage.values.get("salah.progress.hanbali-umdah")!), {
    lessons: {
      fajr: {
        status: "in_progress",
        step_slug: "fajr.r1.ruku",
        content_version: "2026-10-18",
        updated_at: "2026-10-18T12:00:00.000Z",
      },
    },
  });
  assert.deepEqual(readSalahProgress("hanbali-umdah", storage), progress);
  assert.deepEqual(parseSalahProgress("not json"), { lessons: {} });
  assert.deepEqual(
    parseSalahProgress(JSON.stringify({ lessons: { fajr: { status: "done" }, "../x": {} } })),
    { lessons: {} },
  );
  assert.deepEqual(readSalahProgress("hanbali-umdah", null), { lessons: {} });
});

test("the course summary counts completions and picks the lesson to continue", () => {
  const lessons = orderedLessons(course);
  assert.deepEqual(summarizeSalahProgress(lessons, { lessons: {} }), {
    completed: 0,
    total: 3,
    continueLesson: { slug: "what-is-salah", stepSlug: null },
  });
  let progress = recordSalahStep({ lessons: {} }, "what-is-salah", "what-is-salah.intro", "v", {
    completed: true, now: new Date("2026-10-18T10:00:00Z"),
  });
  progress = recordSalahStep(progress, "fajr", "fajr.r1.ruku", "v", { now: new Date("2026-10-18T11:00:00Z") });
  progress = recordSalahStep(progress, "wudu", "wudu.gone", "v", { now: new Date("2026-10-18T09:00:00Z") });
  assert.deepEqual(summarizeSalahProgress(lessons, progress), {
    completed: 1,
    total: 3,
    continueLesson: { slug: "fajr", stepSlug: "fajr.r1.ruku" },
  });
  progress = recordSalahStep(progress, "wudu", "wudu.gone", "v", { now: new Date("2026-10-18T12:00:00Z") });
  assert.deepEqual(summarizeSalahProgress(lessons, progress).continueLesson, { slug: "wudu", stepSlug: null });
});
