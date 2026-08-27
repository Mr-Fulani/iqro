import { createServer } from "node:http";

const host = "127.0.0.1";
const port = Number(process.env.MOCK_PUBLIC_API_PORT || 3199);
const publishedAt = "2026-08-24T00:00:00Z";
const unavailableInstallationId = "00000000-0000-7000-8000-000000000999";

const edition = {
  id: "00000000-0000-0000-0000-000000000001",
  code: "madani-hafs",
  name_ar: "مصحف المدينة",
  name_en: "Madani Mushaf",
  name_ru: "Мединский мусхаф",
  riwayah: "Hafs 'an Asim",
  source_name: "Approved test source",
  source_url: "https://example.test/source",
  license_name: "Test license",
  license_url: "https://example.test/license",
  active_version: {
    id: "00000000-0000-0000-0000-000000000002",
    version: "1.0.0",
    checksum_sha256: "a".repeat(64),
    page_count: 604,
    surah_count: 1,
    juz_count: 30,
    hizb_count: 60,
    rub_el_hizb_count: 240,
    published_at: publishedAt,
  },
};

const surah = {
  id: "00000000-0000-0000-0000-000000000003",
  number: 1,
  name_ar: "الفاتحة",
  name_en: "Al-Fatihah",
  name_ru: "Аль-Фатиха",
  revelation_type: "meccan",
  ayah_count: 2,
  first_page: 1,
};

const ayahs = [
  {
    id: "00000000-0000-0000-0000-000000000004",
    edition_code: edition.code,
    content_version: edition.active_version.version,
    surah_number: 1,
    number: 1,
    text_uthmani: "بِسْمِ اللَّهِ",
    juz_number: 1,
    hizb_number: 1,
    rub_el_hizb_number: 1,
    pages: [1],
  },
  {
    id: "00000000-0000-0000-0000-000000000005",
    edition_code: edition.code,
    content_version: edition.active_version.version,
    surah_number: 1,
    number: 2,
    text_uthmani: "الْحَمْدُ لِلَّهِ",
    juz_number: 1,
    hizb_number: 1,
    rub_el_hizb_number: 1,
    pages: [1],
  },
];

const reciter = {
  id: "00000000-0000-7000-8000-000000000159",
  slug: "qf-159-maher-al-muaiqly",
  name_ar: "ماهر المعيقلي",
  name_en: "Maher al-Muaiqly",
  name_ru: "Махер аль-Муайкли",
  country_code: "SA",
  biography_ar: "قارئ وإمام من المملكة العربية السعودية.",
  biography_en: "A Quran reciter and imam from Saudi Arabia.",
  biography_ru: "Чтец Корана и имам из Саудовской Аравии.",
  portrait_url: null,
};

const recitation = {
  id: "00000000-0000-7000-8000-000000000701",
  code: "maher-murattal",
  version: "1.0.0",
  style: "murattal",
  reciter,
  quran_edition: {
    id: edition.id,
    code: edition.code,
    content_version: edition.active_version.version,
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
  coverage: { track_count: 114, surah_count: 114, complete: true },
  timings: { available: true, segment_count: 2 },
  published_at: publishedAt,
};

const tracks = Array.from({ length: 114 }, (_, index) => {
  const asset = {
    url: `https://audio.example.test/${recitation.id}/${index + 1}.mp3`,
    content_type: "audio/mpeg",
    codec: "mp3",
    bitrate_kbps: 128,
    bytes: 1_000_000,
    sha256: null,
    etag: null,
    range_supported: true,
    immutable: true,
  };
  return {
    id: `00000000-0000-7000-8000-${String(index + 1).padStart(12, "0")}`,
    recitation_id: recitation.id,
    scope: "surah",
    surah_number: index + 1,
    juz_number: null,
    duration_ms: 60_000 + index * 1_000,
    offline_download_allowed: false,
    asset,
    renditions: [
      {
        id: `00000000-0000-7000-8200-${String(index + 1).padStart(12, "0")}`,
        quality: "standard",
        is_default: true,
        asset,
      },
    ],
  };
});

function sendJson(response, status, body) {
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "public, max-age=60",
  });
  response.end(JSON.stringify(body));
}

async function readJson(request) {
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  return JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
}

const server = createServer(async (request, response) => {
  const path = new URL(request.url || "/", `http://${host}:${port}`).pathname;

  if (path === "/api/v1/auth/guest" && request.method === "POST") {
    const input = await readJson(request);
    if (input.installation_id === unavailableInstallationId) {
      return sendJson(response, 403, {
        code: "guest_bootstrap_unavailable",
        detail: "Guest bootstrap is unavailable for this installation.",
      });
    }
    return sendJson(response, 200, {
      token_type: "Bearer",
      access_token: "rotated-guest-access-token",
      expires_in: 900,
      access_expires_at: "2027-08-27T00:15:00Z",
      refresh_token: "rotated-guest-refresh-token",
      refresh_expires_in: 2592000,
      refresh_expires_at: "2027-09-26T00:00:00Z",
      user: {
        id: "00000000-0000-7000-8000-000000000199",
        status: "guest",
        preferred_locale: input.locale || "ru",
        email: null,
        deletion_requested_at: null,
        deletion_scheduled_for: null,
      },
      device: {
        id: "00000000-0000-7000-8000-000000000299",
        platform: "web",
        locale: input.locale || "ru",
        app_version: input.app_version || "1.0.0",
        bootstrap_generation: 1,
      },
    });
  }
  if (path === "/api/v1/auth/email/start" && request.method === "POST") {
    return sendJson(response, 202, {
      challenge_id: "00000000-0000-7000-8000-000000000399",
      expires_in: 600,
      expires_at: "2027-08-27T00:10:00Z",
    });
  }

  if (path === "/api/v1/quran/editions") return sendJson(response, 200, [edition]);
  if (path === "/api/v1/quran/editions/madani-hafs") return sendJson(response, 200, edition);
  if (path === "/api/v1/quran/editions/madani-hafs/surahs") return sendJson(response, 200, [surah]);
  if (path === "/api/v1/quran/editions/madani-hafs/surahs/1") return sendJson(response, 200, surah);
  if (path === "/api/v1/quran/editions/madani-hafs/surahs/1/ayahs") return sendJson(response, 200, ayahs);
  if (path === "/api/v1/quran/editions/madani-hafs/ayahs/1/1") return sendJson(response, 200, ayahs[0]);
  if (path === "/api/v1/quran/editions/madani-hafs/ayahs/1/2") return sendJson(response, 200, ayahs[1]);
  if (path === "/api/v1/reciters") return sendJson(response, 200, { next: null, previous: null, results: [reciter] });
  if (path === `/api/v1/reciters/${reciter.id}`) return sendJson(response, 200, reciter);
  if (path === "/api/v1/recitations") return sendJson(response, 200, { next: null, previous: null, results: [recitation] });
  if (path === `/api/v1/recitations/${recitation.id}`) return sendJson(response, 200, recitation);
  if (path === `/api/v1/recitations/${recitation.id}/tracks`) {
    return sendJson(response, 200, { next: null, previous: null, results: tracks });
  }

  return sendJson(response, 404, { detail: "Not found" });
});

server.listen(port, host);

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
