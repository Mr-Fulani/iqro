// One audio catalog for the mock public API (server rendering) and the browser
// mocks in the specs. Static pages are rendered once, so a spec cannot swap the
// catalog per test: both sides must read the same data from here.
import type { AudioTrack, Recitation, Reciter, SurahPlayback } from "../../lib/api.ts";

const publishedAt = "2026-08-24T00:00:00Z";

function listedReciter(
  id: string,
  slug: string,
  names: Pick<Reciter, "name_ar" | "name_en" | "name_ru">,
  countryCode: string,
): Reciter {
  return { id: `00000000-0000-7000-8000-${id}`, slug, ...names, country_code: countryCode, portrait_url: null };
}

// The first person in API order is the default reciter of the audio page.
export const reciter: Reciter = {
  id: "00000000-0000-7000-8000-000000000159",
  slug: "qf-159-maher-al-muaiqly",
  name_ar: "ماهر المعيقلي",
  name_en: "Maher al-Muaiqly",
  name_ru: "Махер аль-Муайкли",
  name_tr: "Mahir el-Muaykli",
  country_code: "SA",
  biography_ar: "قارئ وإمام من المملكة العربية السعودية.",
  biography_en: "A Quran reciter and imam from Saudi Arabia.",
  biography_ru: "Чтец Корана и имам из Саудовской Аравии.",
  biography_tr: "Suudi Arabistanlı Kur'an okuyucusu ve imamdır.",
  portrait_url: null,
};

export const alternateReciter = listedReciter("000000000006", "qf-6-mahmoud-khaleel-al-husary", {
  name_ar: "محمود خليل الحصري",
  name_en: "Mahmoud Khaleel Al-Husary",
  name_ru: "Махмуд Халиль Аль-Хусари",
}, "EG");

export const abdulBaset = listedReciter("000000000002", "qf-2-abdul-baset-abdul-samad", {
  name_ar: "عبد الباسط عبد الصمد",
  name_en: "Abdul Baset Abdul Samad",
  name_ru: "Абдуль-Басит Абдус-Самад",
}, "EG");

// A second source of the same person: the catalog shows it as one reciter.
export const abdulBasetMujawwad = listedReciter("000000000001", "qf-1-abdulbaset-abdulsamad-mujawwad", {
  name_ar: "عبد الباسط عبد الصمد - مجود",
  name_en: "AbdulBaset AbdulSamad [Mujawwad]",
  name_ru: "Абдуль-Басит Абдус-Самад",
}, "EG");

export const sudais = listedReciter("000000000003", "qf-3-abdur-rahman-as-sudais", {
  name_ar: "عبدالرحمن السديس",
  name_en: "Abdur-Rahman as-Sudais",
  name_ru: "Абдур-Рахман ас-Судайс",
}, "SA");

export const mishari = listedReciter("000000000007", "qf-7-mishari-rashid-al-afasy", {
  name_ar: "مشاري راشد العفاسي",
  name_en: "Mishari Rashid al-Afasy",
  name_ru: "Мишари Рашид аль-Афаси",
}, "KW");

export const reciters: Reciter[] = [
  reciter,
  abdulBaset,
  abdulBasetMujawwad,
  listedReciter("000000000158", "qf-158-abdullah-ali-jabir", {
    name_ar: "عبدالله علي جابر",
    name_en: "Abdullah Ali Jabir",
    name_ru: "Абдуллах Али Джабир",
  }, "SA"),
  listedReciter("000000000175", "qf-175-abdullah-hamad-abu-sharida", {
    name_ar: "عبدالله حمد أبو شريدة",
    name_en: "Abdullah Hamad Abu Sharida",
    name_ru: "Абдуллах Хамад Абу Шарида",
  }, "SA"),
  sudais,
  listedReciter("000000000004", "qf-4-abu-bakr-al-shatri", {
    name_ar: "أبو بكر الشاطري",
    name_en: "Abu Bakr al-Shatri",
    name_ru: "Абу Бакр аш-Шатри",
  }, "SA"),
  listedReciter("000000000005", "qf-5-hani-ar-rifai", {
    name_ar: "هاني الرفاعي",
    name_en: "Hani ar-Rifai",
    name_ru: "Хани ар-Рифаи",
  }, "SA"),
  alternateReciter,
  mishari,
  listedReciter("000000000009", "qf-9-muhammad-siddiq-al-minshawi", {
    name_ar: "محمد صديق المنشاوي",
    name_en: "Muhammad Siddiq al-Minshawi",
    name_ru: "Мухаммад Сиддик аль-Миншави",
  }, "EG"),
  listedReciter("000000000010", "qf-10-saud-ash-shuraym", {
    name_ar: "سعود الشريم",
    name_en: "Saud ash-Shuraym",
    name_ru: "Сауд аш-Шурайм",
  }, "SA"),
];

/** Reciters grouped by person, as the audio page and the home page show them. */
export const reciterPeopleCount = reciters.length - 1;

function publishedRecitation(
  id: string,
  code: string,
  style: string,
  source: Reciter,
  options: { version?: string; publishedAt?: string; ayahPlayback?: boolean } = {},
): Recitation {
  const ayahPlayback = options.ayahPlayback ?? true;
  return {
    id: `00000000-0000-7000-8000-${id}`,
    code,
    version: options.version ?? "1.0.0",
    style,
    reciter: source,
    quran_edition: {
      id: "00000000-0000-0000-0000-000000000001",
      code: "madani-hafs",
      content_version: "1.0.0",
      riwayah: "Hafs 'an Asim",
    },
    source: {
      name: "Approved audio test source",
      url: "https://example.test/sources/audio",
      version: "2026.08",
      checksum_sha256: "b".repeat(64),
    },
    license: {
      rights_holder: "Test rights holder",
      name: "Test streaming license",
      url: "https://example.test/licenses/audio",
      spdx_id: "CC0-1.0",
      attribution: "Synthetic test audio.",
    },
    rights: { stream: true, offline_download: false },
    coverage: {
      track_count: 114,
      surah_count: 114,
      expected_ayahs: 6236,
      timed_ayahs: ayahPlayback ? 6236 : 0,
      complete: true,
      timings_complete: ayahPlayback,
    },
    timings: { available: ayahPlayback, segment_count: ayahPlayback ? 6236 : 0, complete: ayahPlayback },
    capabilities: {
      listen: true,
      ayah_playback: ayahPlayback,
      memorization: ayahPlayback,
      offline: false,
    },
    published_at: options.publishedAt ?? publishedAt,
  };
}

export const recitation = publishedRecitation("000000000701", "maher-murattal", "murattal", reciter);

export const alternateRecitation = publishedRecitation(
  "000000001006",
  "qf-6-murattal",
  "murattal",
  alternateReciter,
);

// Listening-only variants: an older murattal replaced by a newer one, and a
// mujawwad from the person's second source.
export const abdulBasetRecitations = {
  murattalOld: publishedRecitation("000000001001", `${abdulBaset.slug}-murattal`, "murattal", abdulBaset, {
    version: "2026-08-20",
    publishedAt: "2026-08-20T00:00:00Z",
    ayahPlayback: false,
  }),
  murattalCurrent: publishedRecitation("000000001002", `${abdulBaset.slug}-murattal`, "murattal", abdulBaset, {
    version: "2026-08-25",
    publishedAt: "2026-08-25T00:00:00Z",
    ayahPlayback: false,
  }),
  mujawwad: publishedRecitation(
    "000000001003",
    `${abdulBasetMujawwad.slug}-mujawwad`,
    "mujawwad",
    abdulBasetMujawwad,
    { version: "2026-08-25", publishedAt: "2026-08-25T00:00:00Z", ayahPlayback: false },
  ),
};

export const recitations: Recitation[] = [
  recitation,
  alternateRecitation,
  abdulBasetRecitations.murattalOld,
  abdulBasetRecitations.murattalCurrent,
  abdulBasetRecitations.mujawwad,
];

export function recitationsMatching(query: URLSearchParams): Recitation[] {
  const reciterId = query.get("reciter_id");
  const editionCode = query.get("quran_edition");
  return recitations.filter(
    (item) =>
      (!reciterId || item.reciter.id === reciterId) &&
      (!editionCode || item.quran_edition.code === editionCode),
  );
}

function surahTracks(recitationId: string, trackIdPrefix: string, urlPrefix: string): AudioTrack[] {
  return Array.from({ length: 114 }, (_, index) => {
    const surah = index + 1;
    const asset = {
      url: `https://audio.example.test/${urlPrefix}${String(surah).padStart(3, "0")}.mp3`,
      content_type: "audio/mpeg",
      codec: "mp3",
      bitrate_kbps: 96,
      bytes: 720_000,
      sha256: null,
      etag: null,
      range_supported: false,
      immutable: false,
    };
    return {
      id: `00000000-0000-7000-${trackIdPrefix}-${String(surah).padStart(12, "0")}`,
      recitation_id: recitationId,
      scope: "surah",
      surah_number: surah,
      juz_number: null,
      duration_ms: 60_000,
      offline_download_allowed: false,
      asset,
      renditions: [
        {
          id: `00000000-0000-7000-8200-${String(surah).padStart(12, "0")}`,
          quality: "standard",
          is_default: true,
          asset,
        },
      ],
    };
  });
}

export const tracks = surahTracks(recitation.id, "8100", "");
export const alternateTracks = surahTracks(alternateRecitation.id, "8300", "husary/");

const tracksByRecitation = new Map<string, AudioTrack[]>([
  [recitation.id, tracks],
  [alternateRecitation.id, alternateTracks],
]);
const segmentIdPrefixes = new Map([
  [recitation.id, "8500"],
  [alternateRecitation.id, "8600"],
]);

export function recitationById(recitationId: string): Recitation | undefined {
  return recitations.find((item) => item.id === recitationId);
}

/** Published surah tracks; listening-only fixtures have none yet. */
export function tracksFor(recitationId: string): AudioTrack[] {
  return tracksByRecitation.get(recitationId) ?? [];
}

/** Timed playback for the recitations that support ayah playback. */
export function surahPlayback(recitationId: string, surahNumber: number): SurahPlayback | undefined {
  const track = tracksFor(recitationId)[surahNumber - 1];
  const segmentIdPrefix = segmentIdPrefixes.get(recitationId);
  if (!track || !segmentIdPrefix) return undefined;
  return {
    track,
    segments: [1, 2].map((ayahNumber) => ({
      ayah_id: `00000000-0000-7000-${segmentIdPrefix}-${String(surahNumber * 10 + ayahNumber).padStart(12, "0")}`,
      surah_number: surahNumber,
      ayah_number: ayahNumber,
      start_ms: (ayahNumber - 1) * 1_000,
      end_ms: ayahNumber * 1_000,
    })),
  };
}

export function paginated<T>(results: T[]) {
  return { next: null, previous: null, results };
}
