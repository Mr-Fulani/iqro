import assert from "node:assert/strict";
import test from "node:test";

import type { DuaEntry } from "./api.ts";
import { duaReference } from "./dua-presentation.ts";
import { formatMessage, type MessageKey } from "./i18n.ts";
import ru from "./messages/ru.ts";

const t = (key: MessageKey, variables: Record<string, string | number>) => formatMessage(ru[key], variables);

function entry(overrides: Partial<DuaEntry> = {}): DuaEntry {
  return {
    id: "entry-75", source_number: 75, slug: "hisn-entry-075", collection: "hisn-al-muslim",
    collection_version: "full-v1",
    category: { source_number: 27, slug: "morning-evening", title: "Утром и вечером" },
    arabic_text: "دعاء", repetitions: 1, repetition_label: "",
    translation: { language_code: "ru", meaning_text: "Смысл", transliteration: "" },
    evidence: [{
      kind: "source_note", provider: "islamhouse", source_name: "Hisn al-Muslim",
      source_reference: "Hisn al-Muslim, entry 75.", source_url: "", grade: "", external_id: "",
      verification_status: "source_only",
    }],
    source: {
      language_code: "ru", provider: "islamhouse", source_item_id: "", title: "Молитвы из Корана и Сунны",
      author: "", translator: "", reviewer: "", source_url: "", rights_url: "", source_version: "",
    },
    audio: [],
    ...overrides,
  };
}

test("the card names the source in the reader's language, without brackets", () => {
  assert.equal(duaReference(entry(), t), "Крепость мусульманина, № 75");
  assert.equal(duaReference(entry({
    collection: "supplications-from-quran",
    source_number: 1,
    evidence: [{ ...entry().evidence[0], kind: "quran", source_reference: "2:126" }],
  }), t), "Коран, 2:126");
  assert.equal(duaReference(entry({ collection: "other", source_number: 4 }), t), "Молитвы из Корана и Сунны, № 4");
  assert.equal(duaReference(entry({ collection: "other", source_number: 4, source: null }), t), "#4");
});
