import assert from "node:assert/strict";
import test from "node:test";

import type { DuaEntry } from "./api.ts";
import { duaDisplayTitle, duaShareText, duaShareTitle } from "./dua-share.ts";

function entry(overrides: Partial<DuaEntry> = {}): DuaEntry {
  return {
    id: "entry-7", source_number: 7, slug: "morning", collection: "hisn-al-muslim",
    collection_version: "full-v1",
    category: { source_number: 1, slug: "morning", title: "Morning" },
    arabic_text: "دعاء", repetitions: 1, repetition_label: "",
    translation: { language_code: "en", meaning_text: "A meaning", transliteration: "Dua" },
    evidence: [{
      kind: "source_note", provider: "provider", source_name: "Hisn", source_reference: "Entry 7",
      source_url: "", grade: "", external_id: "", verification_status: "source_only",
    }],
    source: {
      language_code: "en", provider: "islamhouse", source_item_id: "", title: "Hisn al-Muslim",
      author: "", translator: "", reviewer: "", source_url: "", rights_url: "", source_version: "",
    },
    audio: [],
    ...overrides,
  };
}

test("capitals from the source read in sentence case, as in the app", () => {
  assert.equal(
    duaDisplayTitle("СЛОВА ПОМИНАНИЯ АЛЛАХА, ПРОИЗНОСИМЫЕ УТРОМ И ВЕЧЕРОМ", "ru"),
    "Слова поминания Аллаха, произносимые утром и вечером",
  );
  assert.equal(duaDisplayTitle("WHAT TO SAY WHEN READING THE QURAN", "en"), "What to say when reading the Quran");
  assert.equal(
    duaDisplayTitle("СЛОВА МОЛЬБЫ В НАЧАЛЕ МОЛИТВЫ (ду'ау-ль-истифтах)", "ru"),
    "Слова мольбы в начале молитвы (ду'ау-ль-истифтах)",
  );
  assert.equal(duaDisplayTitle("ELBİSE GİYERKEN YAPILAN DUÂ", "tr"), "Elbise giyerken yapılan duâ");
});

test("mixed case and Arabic titles stay as they are", () => {
  assert.equal(duaDisplayTitle("Слова поминания утром", "ru"), "Слова поминания утром");
  assert.equal(duaDisplayTitle("أذكار الصباح", "ar"), "أذكار الصباح");
});

test("the shared du'a has its chapter, meaning and sources without claiming verification", () => {
  assert.equal(duaShareTitle(entry(), "en"), "Morning · #7");
  assert.deepEqual(duaShareText(entry(), "en", "Repetitions"), {
    arabic: "دعاء",
    translation: "A meaning",
    note: "",
    reference: "Hisn al-Muslim · Entry 7",
  });
  // A source repeated in the evidence is named once.
  const repeated = entry({ evidence: [...entry().evidence, { ...entry().evidence[0], source_reference: "Hisn al-Muslim" }] });
  assert.equal(duaShareText(repeated, "en", "Repetitions").reference, "Hisn al-Muslim · Entry 7");
  // In Arabic the meaning repeats the du'a itself.
  assert.equal(duaShareText(entry(), "ar", "التكرارات").translation, "");
});

test("simple and staged repetitions are noted", () => {
  assert.equal(duaShareText(entry({ repetitions: 3 }), "en", "Repetitions").note, "Repetitions: 3");
  assert.equal(
    duaShareText(entry({ repetitions: 3, repetition_label: "33 · 33 · 34" }), "en", "Repetitions").note,
    "Repetitions: 33 · 33 · 34",
  );
});
