import assert from "node:assert/strict";
import test from "node:test";
import type { TajweedAyah, TajweedReference } from "./api.ts";
import {
  highlightRuns,
  joinedParts,
  joinedRuns,
  arabicParts,
  presentRules,
  ruleOccurrences,
  ruleText,
  stepRules,
  stepTiming,
  tajweedSteps,
  tajweedWordIndex,
  timedPosition,
  tajweedWordKey,
  wordTiming,
} from "./tajweed.ts";

// Quran.Foundation markup of 112:4 as the backend binds it to QF word positions.
const IKHLAS_4: TajweedAyah = {
  verse_key: "112:4",
  surah_number: 112,
  ayah_number: 4,
  page_number: 604,
  rules: ["idgham_wo_ghunnah", "qalaqah", "madda_normal"],
  words: [
    { position: 2, text: "يَكُن", rules: [{ code: "idgham_wo_ghunnah", start: 3, end: 5, joins_next: true }] },
    {
      position: 3,
      text: "لَّهُۥ",
      rules: [
        { code: "idgham_wo_ghunnah", start: 0, end: 1, joins_previous: true },
        { code: "madda_normal", start: 5, end: 6, variant: "silah_sughra" },
      ],
    },
    { position: 5, text: "أَحَدُۢ", rules: [{ code: "qalaqah", start: 4, end: 5, variant: "stop" }] },
  ],
};

const texts = (ru: string) => ({ ru, en: `${ru} (en)`, ar: ru, tr: ru });
const REFERENCE: TajweedReference = {
  version: "test",
  review_status: "pending_teacher_review",
  languages: ["ru", "en", "ar", "tr"],
  rules: [
    { code: "idgham_wo_ghunnah", arabic_name: "الإدغام بغير غنة", color: "#A3A5A5", name: texts("Идгам без гунны"), why: texts("Нун перед ل"), how: texts("Без гунны"), variants: [] },
    { code: "qalaqah", arabic_name: "القلقلة", color: "#2FADFF", name: texts("Калькаля"), why: texts("Сукун"), how: texts("Отскок"), variants: [{ code: "stop", name: texts("При остановке"), why: texts("Конец слова"), how: texts("Отчётливее") }] },
    { code: "madda_normal", arabic_name: "المد الطبيعي", color: "#CE9E00", name: texts("Мадд табии"), why: texts("Буква мадда"), how: texts("2 хараката"), variants: [{ code: "silah_sughra", name: texts("Силя сугра"), why: texts("Хаъ местоимения"), how: texts("2 вслитную") }] },
    { code: "ham_wasl", arabic_name: "همزة الوصل", color: "#9FA5A5", name: texts("Хамзату-ль-васль"), why: texts("ٱ"), how: texts("Пропустить"), variants: [] },
  ],
};

test("idgham crossing a word boundary shows both words in reading order", () => {
  const [first, second] = IKHLAS_4.words;
  const fromFirst = joinedParts(IKHLAS_4, first, first.rules[0]);
  const fromSecond = joinedParts(IKHLAS_4, second, second.rules[0]);

  assert.deepEqual(fromFirst.map((part) => part.word.text), ["يَكُن", "لَّهُۥ"]);
  assert.deepEqual(fromSecond.map((part) => part.word.text), ["يَكُن", "لَّهُۥ"]);
  assert.deepEqual(fromSecond.map((part) => part.fragment.start), [3, 0]);
});

test("occurrences count a joined rule once and keep ayah order", () => {
  assert.equal(ruleOccurrences([IKHLAS_4], "idgham_wo_ghunnah").length, 1);
  assert.equal(ruleOccurrences([IKHLAS_4], "qalaqah")[0][0].word.position, 5);
  assert.deepEqual(ruleOccurrences([IKHLAS_4], "ghunnah"), []);
});

test("highlight runs keep vowel marks with their letter", () => {
  // QF marks only «د» of أَحَدُۢ and «ُن» of يَكُن; the damma belongs to its letter.
  assert.deepEqual(highlightRuns("أَحَدُۢ", IKHLAS_4.words[2].rules), [
    { text: "أَحَ", code: null },
    { text: "دُۢ", code: "qalaqah" },
  ]);
  assert.deepEqual(highlightRuns("يَكُن", IKHLAS_4.words[0].rules), [
    { text: "يَكُ", code: null },
    { text: "ن", code: "idgham_wo_ghunnah" },
  ]);
});

test("highlight runs colour fragments and let the narrower nested rule win", () => {
  assert.deepEqual(highlightRuns("لَّهُۥ", IKHLAS_4.words[1].rules), [
    { text: "لَّ", code: "idgham_wo_ghunnah" },
    { text: "هُ", code: null },
    { text: "ۥ", code: "madda_normal" },
  ]);
  assert.deepEqual(
    highlightRuns("دُوٓاْ", [
      { code: "madda_obligatory", start: 1, end: 6 },
      { code: "slnt", start: 4, end: 6 },
    ]),
    [
      { text: "دُ", code: null },
      { text: "وٓ", code: "madda_obligatory" },
      { text: "اْ", code: "slnt" },
    ],
  );
});

test("rule texts follow the variant and fall back to English", () => {
  assert.deepEqual(ruleText(REFERENCE, "madda_normal", "ru", "silah_sughra"), {
    code: "madda_normal",
    color: "#CE9E00",
    name: "Мадд табии",
    variantName: "Силя сугра",
    arabicName: "المد الطبيعي",
    why: "Хаъ местоимения",
    how: "2 вслитную",
  });
  assert.equal(ruleText(REFERENCE, "qalaqah", "de")?.name, "Калькаля (en)");
  assert.equal(ruleText(REFERENCE, "unknown", "ru"), null);
});

test("legend keeps the reference order and only present rules", () => {
  assert.deepEqual(
    presentRules(REFERENCE, ["madda_normal", "idgham_wo_ghunnah", "qalaqah"]).map((rule) => rule.code),
    ["idgham_wo_ghunnah", "qalaqah", "madda_normal"],
  );
});

test("word index and timings resolve QF word positions", () => {
  const index = tajweedWordIndex([IKHLAS_4]);
  assert.equal(index.get(tajweedWordKey("112:4", 3))?.text, "لَّهُۥ");
  assert.equal(index.has(tajweedWordKey("112:4", 1)), false);
  const words: [number, number, number][] = [[1, 8425, 9155], [3, 9675, 10505]];
  assert.deepEqual(wordTiming(words, 3), { startMs: 9675, endMs: 10505 });
  assert.equal(wordTiming(words, 2), null);
  assert.equal(wordTiming([[2, 10, 10]], 2), null);
  assert.equal(wordTiming(undefined, 2), null);
});

test("joined runs keep connecting letters connected across colour breaks", () => {
  const [before, letter] = joinedRuns(highlightRuns("أَحَدُۢ", IKHLAS_4.words[2].rules));
  // ح connects forward to د; د itself never connects to a following letter.
  assert.equal(before.text, "أَحَ\u200d");
  assert.equal(letter.text, "\u200dدُۢ");
  const [lam, ha, waw] = joinedRuns(highlightRuns("لَّهُۥ", IKHLAS_4.words[1].rules));
  assert.deepEqual([lam.text, ha.text, waw.text], ["لَّ\u200d", "\u200dهُ", "ۥ"]);
});

test("Arabic examples inside an explanation are split out for isolation", () => {
  assert.deepEqual(arabicParts("Хаъ (ـهُۥ / ـهِۦ) перед ل."), [
    { text: "Хаъ (", arabic: false },
    { text: "ـهُۥ / ـهِۦ", arabic: true },
    { text: ") перед ", arabic: false },
    { text: "ل", arabic: true },
    { text: ".", arabic: false },
  ]);
  assert.deepEqual(arabicParts("2 counts."), [{ text: "2 counts.", arabic: false }]);
});

test("breakdown steps follow the reading order, one rule in one place each", () => {
  const steps = tajweedSteps(IKHLAS_4, REFERENCE);
  // The idgham spans يَكُن لَّهُۥ: one step, shown on both words.
  assert.deepEqual(
    steps.map((step) => [step.code, step.variant, step.parts.map((part) => part.word.position)]),
    [
      ["idgham_wo_ghunnah", null, [2, 3]],
      ["madda_normal", "silah_sughra", [3]],
      ["qalaqah", "stop", [5]],
    ],
  );
  // Each step keeps only its own letters of the word.
  assert.deepEqual(steps[1].parts[0].fragment, IKHLAS_4.words[1].rules[1]);
});

test("breakdown steps split several rules of one word and skip unknown rules", () => {
  const ayah: TajweedAyah = {
    ...IKHLAS_4,
    words: [
      {
        position: 1,
        text: "ٱللَّهُ",
        rules: [
          { code: "ham_wasl", start: 0, end: 1 },
          { code: "laam_shamsiyah", start: 1, end: 2 },
          { code: "madda_normal", start: 3, end: 5 },
        ],
      },
    ],
  };
  assert.deepEqual(tajweedSteps(ayah, REFERENCE).map((step) => step.code), ["ham_wasl", "madda_normal"]);
});

test("a rule continued from a missing word still makes its own step", () => {
  const ayah: TajweedAyah = { ...IKHLAS_4, words: [IKHLAS_4.words[1]] };
  const steps = tajweedSteps(ayah, REFERENCE);
  assert.deepEqual(steps.map((step) => step.code), ["idgham_wo_ghunnah", "madda_normal"]);
  assert.equal(steps[0].parts.length, 1);
});

test("the summary lists each rule once, with its steps, in order of appearance", () => {
  const steps = tajweedSteps(IKHLAS_4, REFERENCE);
  assert.deepEqual(stepRules([...steps, steps[0]]), [
    { code: "idgham_wo_ghunnah", steps: [0, 3] },
    { code: "madda_normal", steps: [1] },
    { code: "qalaqah", steps: [2] },
  ]);
});

test("a step plays from its first word to its last; the ayah lights the sounding word", () => {
  const [idgham, madd] = tajweedSteps(IKHLAS_4, REFERENCE);
  const words = [[2, 9155, 9675], [3, 9675, 10200], [5, 11000, 12000]];
  assert.deepEqual(stepTiming(words, idgham), { startMs: 9155, endMs: 10200 });
  assert.deepEqual(stepTiming(words, madd), { startMs: 9675, endMs: 10200 });
  assert.equal(stepTiming([[2, 9155, 9675]], idgham), null);
  assert.equal(timedPosition(words, 9675), 3);
  assert.equal(timedPosition(words, 10500), null);
  assert.equal(timedPosition(undefined, 9675), null);
});
