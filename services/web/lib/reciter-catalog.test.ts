import assert from "node:assert/strict";
import test from "node:test";

import type { Recitation, Reciter } from "./api.ts";
import {
  latestRecitationsByVariant,
  recitationHasSurah,
  recitersWithPortraitsFirst,
  reciterSearch,
  recitationStyleLabel,
  recitationsForRole,
  supportsRecitationRole,
  tajweedCourseRecitation,
} from "./reciter-catalog.ts";

const reciter: Reciter = {
  id: "00000000-0000-7000-8000-000000000101",
  slug: "qf-101-test-reciter",
  name_ar: "قارئ الاختبار",
  name_en: "Test Reciter",
  name_ru: "Тестовый чтец",
  country_code: "SA",
};

function recitation(
  id: string,
  publishedAt: string,
  capabilities: Recitation["capabilities"],
): Recitation {
  return {
    id,
    code: "qf-101-murattal",
    version: publishedAt,
    style: "murattal",
    reciter,
    quran_edition: {
      id: "00000000-0000-7000-8000-000000000102",
      code: "madani-hafs",
      content_version: "1.0.0",
      riwayah: "Hafs 'an Asim",
    },
    source: {
      name: "Test source",
      url: "https://example.test/source",
      version: "1.0.0",
      checksum_sha256: "a".repeat(64),
    },
    license: {
      rights_holder: "Test",
      name: "Test license",
      url: "https://example.test/license",
      spdx_id: "CC0-1.0",
      attribution: "Test",
    },
    rights: { stream: true, offline_download: false },
    coverage: {
      track_count: 114,
      surah_count: 114,
      expected_ayahs: 6236,
      timed_ayahs: capabilities.ayah_playback ? 6236 : 0,
      complete: true,
      timings_complete: capabilities.ayah_playback,
    },
    timings: {
      available: capabilities.ayah_playback,
      segment_count: capabilities.ayah_playback ? 6236 : 0,
      complete: capabilities.ayah_playback,
    },
    capabilities,
    published_at: publishedAt,
  };
}

const timed = recitation(
  "00000000-0000-7000-8000-000000000103",
  "2026-09-01T00:00:00Z",
  { listen: true, ayah_playback: true, memorization: true, offline: false },
);

const newerUntimed = recitation(
  "00000000-0000-7000-8000-000000000104",
  "2026-09-10T00:00:00Z",
  { listen: true, ayah_playback: false, memorization: false, offline: false },
);

test("filters recitations by explicit role capabilities", () => {
  assert.deepEqual(recitationsForRole([timed, newerUntimed], "listen"), [
    timed,
    newerUntimed,
  ]);
  assert.deepEqual(recitationsForRole([timed, newerUntimed], "ayah_playback"), [timed]);
  assert.deepEqual(recitationsForRole([timed, newerUntimed], "memorization"), [timed]);

  const listenOnly = { ...timed, capabilities: { ...timed.capabilities, listen: false } };
  assert.equal(supportsRecitationRole(listenOnly, "listen"), false);
});

test("filters before deduplicating so a newer untimed variant does not hide a timed one", () => {
  assert.deepEqual(latestRecitationsByVariant([timed, newerUntimed], "listen"), [newerUntimed]);
  assert.deepEqual(latestRecitationsByVariant([timed, newerUntimed], "ayah_playback"), [timed]);
  assert.deepEqual(latestRecitationsByVariant([timed, newerUntimed], "memorization"), [timed]);
});

test("legacy responses retain listening compatibility while timed roles require complete timings", () => {
  const legacy = structuredClone(timed) as Recitation;
  delete (legacy as unknown as { capabilities?: unknown }).capabilities;
  delete (legacy.timings as unknown as { complete?: boolean }).complete;

  assert.equal(supportsRecitationRole(legacy, "listen"), true);
  assert.equal(supportsRecitationRole(legacy, "ayah_playback"), false);
  assert.equal(supportsRecitationRole(legacy, "memorization"), false);
});

test("a partial listening recording knows which surahs it holds", () => {
  const partial = recitation("partial", "2026-10-18T00:00:00Z", {
    listen: true,
    ayah_playback: false,
    memorization: false,
    offline: false,
  });
  partial.coverage = { ...partial.coverage, surah_count: 2, complete: false, surah_numbers: [1, 112] };
  const legacy = recitation("legacy", "2026-10-18T00:00:00Z", partial.capabilities);

  assert.equal(recitationHasSurah(partial, 112), true);
  assert.equal(recitationHasSurah(partial, 2), false);
  assert.equal(recitationHasSurah(legacy, 2), true);
});

test("recitation styles are translated, including the children's repeat", () => {
  const t = (key: string) => `t:${key}`;

  assert.equal(recitationStyleLabel("kids-repeat", t), "t:audio.style.kidsRepeat");
  assert.equal(recitationStyleLabel("mujawwad", t), "t:audio.style.mujawwad");
  assert.equal(recitationStyleLabel("hadr", t), "hadr");
});

test("the tajweed course always plays al-Husary's Muallim when the catalog has it", () => {
  const withCode = (id: string, code: string, teaching = false): Recitation => ({
    ...recitation(id, "2026-10-01T00:00:00Z", timed.capabilities),
    code,
    teaching_default: teaching,
  });
  const maher = withCode("maher", "maher-murattal");
  const afasy = withCode("afasy", "qf-7-murattal-01a15bc65dc9");
  const teaching = withCode("teaching", "qf-6-murattal-01a15bc65dc9", true);
  const husary = withCode("husary", "qf-12-muallim-01a15bc65dc9");

  assert.equal(tajweedCourseRecitation([maher, afasy, teaching, husary])?.id, "husary");
  assert.equal(tajweedCourseRecitation([maher, afasy, teaching])?.id, "teaching");
  assert.equal(tajweedCourseRecitation([maher, afasy])?.id, "afasy");
  assert.equal(tajweedCourseRecitation([maher])?.id, "maher");
  assert.equal(tajweedCourseRecitation([]), undefined);
});

function nameOf(name_ar: string, name_en: string, name_ru: string, name_tr = "") {
  return { name_ar, name_en, name_ru, name_tr };
}

test("the reciter search reads every name in any word order", () => {
  const person = nameOf("ناصر القطامي", "Nasser Alqatami", "Насер Аль Катами");
  const search = reciterSearch([person]);
  assert.deepEqual(search("катами"), [person]);
  assert.deepEqual(search("катами насер"), [person]);
  assert.deepEqual(search("QATAMI"), [person]);
  assert.deepEqual(search("القطامي"), [person]);
  assert.deepEqual(search("  "), [person]);
  assert.deepEqual(search("афаси"), []);
});

test("the reciter search forgives Arabic letter forms", () => {
  const person = nameOf("أبو بكر الشاطري", "Abu Bakr", "Абу Бакр");
  assert.deepEqual(reciterSearch([person])("ابو بكر"), [person]);
  assert.deepEqual(reciterSearch([nameOf("حمزة", "Hamza", "Хамза")])("حمزه").length, 1);
});

test("the reciter search finds a name spelled another way", () => {
  const radia = nameOf("رضية عبدالرحمن", "Rodziah Abdulrahman", "Радия Абдуррахман", "Radiye Abdurrahman");
  const rukaya = nameOf("رقية سولونق", "Rogayah Sulong", "Рукайя Сулонг", "Rukiye Sulong");
  const sapina = nameOf("سابينة مامات", "Sapinah Mamat", "Сапина Мамат");
  const basit = nameOf("عبد الباسط", "Abdul Baset", "Абдуль-Басит Абдус-Самад");
  const shuraym = nameOf("سعود الشريم", "Saud ash-Shuraym", "Сауд аш-Шурайм");
  const search = reciterSearch([radia, rukaya, sapina, basit, shuraym]);
  for (const query of ["Родзия", "Радзия", "Rodzia", "Радиях"]) {
    assert.deepEqual(search(query), [radia], query);
  }
  for (const query of ["Рогая", "Рукия", "Рукайа", "Ruqayya"]) {
    assert.deepEqual(search(query), [rukaya], query);
  }
  assert.deepEqual(search("сапинах"), [sapina]);
  assert.deepEqual(search("сабина мамат"), [sapina]);
  assert.deepEqual(search("абдульбасит"), [basit]);
  assert.deepEqual(search("Шурейм"), [shuraym]);
  assert.deepEqual(search("Шурайм"), [shuraym]);
  assert.deepEqual(search("Зульфия"), []);
});

test("a name spelled as asked hides the ones that only sound like it", () => {
  const rashid = nameOf("راشد", "Rashid", "Рашид");
  const rushd = nameOf("رشدي", "Roshdi", "Рошди");
  assert.deepEqual(reciterSearch([rashid, rushd])("рашид"), [rashid]);
});

test("reciters with a portrait open the list in their own order", () => {
  const plain = { ...reciter, id: "plain", slug: "plain", portrait_url: null };
  const uploaded = { ...reciter, id: "uploaded", slug: "uploaded", portrait_url: "https://cdn/a.webp" };
  const curated = { ...reciter, id: "curated", slug: "qf-3-abdur-rahman-as-sudais", portrait_url: null };

  assert.deepEqual(
    recitersWithPortraitsFirst([plain, uploaded, curated]).map((item) => item.id),
    ["uploaded", "curated", "plain"],
  );
});
