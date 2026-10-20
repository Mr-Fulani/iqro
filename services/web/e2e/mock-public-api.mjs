import { readFileSync } from "node:fs";
import { createServer } from "node:http";
import {
  paginated,
  recitationById,
  recitationsMatching,
  reciters,
  surahPlayback,
  tracksFor,
} from "./fixtures/audio.ts";

const host = "127.0.0.1";
const port = Number(process.env.MOCK_PUBLIC_API_PORT || 3199);
const publishedAt = "2026-08-24T00:00:00Z";
const unavailableInstallationId = "00000000-0000-7000-8000-000000000999";
const duaFavoriteKeys = new Set();

const playerBackgrounds = [
  {
    id: "019a0000-0000-7000-8000-000000000901",
    title_ar: "الجبال",
    title_en: "Mountains",
    title_ru: "Горы",
    title_tr: "",
    image_url: "/player-backgrounds/geometric.webp",
    // VP9 decodes in every Chromium build; the Linux CI one may lack H.264.
    video_url: "/media/audio/player-backgrounds/mountains-loop.webm",
    show_equalizer: false,
    sort_order: 10,
  },
];
const playerBackgroundVideo = readFileSync(new URL("./fixtures/player-background-loop.webm", import.meta.url));

// The contract example is served as is; only its language follows the request and
// its images point at this mock (through the site's /media rewrite) so pages load
// without the network.
const salahCourseExample = JSON.parse(
  readFileSync(new URL("../../../docs/salah/course-document.example.json", import.meta.url), "utf8"),
);
const salahLanguages = new Set(["ru", "en", "ar", "tr"]);

function salahCourse(language) {
  const document = structuredClone(salahCourseExample);
  document.course.language = language;
  for (const item of Object.values(document.media)) {
    item.url = item.url.replace("https://media.iqro.forum/", "/media/");
  }
  return document;
}

function salahImage(label) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="720" height="720" viewBox="0 0 720 720">`
    + `<rect width="720" height="720" fill="#ecfdf5"/><circle cx="360" cy="230" r="70" fill="#a7f3d0"/>`
    + `<rect x="290" y="320" width="140" height="260" rx="60" fill="#a7f3d0"/>`
    + `<text x="360" y="660" font-size="32" text-anchor="middle" fill="#065f46">${label}</text></svg>`;
}

const socialProfiles = [
  {
    platform: "telegram",
    platform_name: "Telegram",
    display_name: "@iqro_forum",
    url: "https://t.me/iqro_forum",
    sort_order: 10,
    include_in_seo: true,
  },
  {
    platform: "youtube",
    platform_name: "YouTube",
    display_name: "IQRO",
    url: "https://www.youtube.com/@iqro",
    sort_order: 20,
    include_in_seo: false,
  },
];

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
  ayah_count: 7,
  first_page: 1,
};

const ayahs = [
  "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ",
  "الْحَمْدُ لِلَّهِ رَبِّ الْعَالَمِينَ",
  "الرَّحْمَٰنِ الرَّحِيمِ",
  "مَالِكِ يَوْمِ الدِّينِ",
  "إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ",
  "اهْدِنَا الصِّرَاطَ الْمُسْتَقِيمَ",
  "صِرَاطَ الَّذِينَ أَنْعَمْتَ عَلَيْهِمْ غَيْرِ الْمَغْضُوبِ عَلَيْهِمْ وَلَا الضَّالِّينَ",
].map((text, index) => ({
  id: `00000000-0000-0000-0000-${String(index + 4).padStart(12, "0")}`,
  edition_code: edition.code,
  content_version: edition.active_version.version,
  surah_number: 1,
  number: index + 1,
  text_uthmani: text,
  juz_number: 1,
  hizb_number: 1,
  rub_el_hizb_number: 1,
  pages: [1],
}));

const duaContent = {
  ar: {
    title: "أذكار الاستيقاظ من النوم",
    meaning: "الْحَمْدُ للَّهِ الَّذِي أَحْيَانَا بَعْدَ مَا أَمَاتَنَا، وَإِلَيْهِ النُّشُورُ",
    transliteration: "",
    edition: "حصن المسلم من أذكار الكتاب والسنة",
    author: "سعيد بن علي بن وهف القحطاني",
    sourceUrl: "https://islamhouse.com/ar/books/2522",
  },
  en: {
    title: "When waking up",
    meaning: "All praise is for Allah who gave us life after having taken it from us and unto Him is the resurrection.",
    transliteration: "",
    edition: "Fortress of the Muslim",
    author: "Saeed bin Ali bin Wahf al-Qahtani",
    sourceUrl: "https://islamhouse.com/en/books/39062",
  },
  ru: {
    title: "Слова поминания при пробуждении ото сна",
    meaning: "Хвала Аллаху, воскресившему нас после того, как Он умертвил нас, и к Нему воскресение.",
    transliteration: "Аль-хамду ли-Лляхи аллязи ахйа-на ба'да ма амата-на ва иляй-хи-н-нушуру.",
    edition: "Молитвы из Корана и Сунны",
    author: "Саид ибн Али ибн Вахб аль-Кахтани",
    sourceUrl: "https://islamhouse.com/ru/books/888254",
  },
  tr: {
    title: "Uykudan uyanınca yapılan dualar",
    meaning: "Bizi öldürdükten sonra dirilten Allah'a hamd olsun. Dönüş yalnızca O'nadır.",
    transliteration: "",
    edition: "Hısnu'l-Müslim",
    author: "Said b. Ali b. Vehf el-Kahtânî",
    sourceUrl: "https://islamhouse.com/tr/books/861",
  },
};

function duaSource(language) {
  const localized = duaContent[language] || duaContent.en;
  return {
    language_code: language,
    provider: "islamhouse",
    source_item_id: "test-source",
    title: localized.edition,
    author: localized.author,
    translator: "",
    reviewer: "",
    source_url: localized.sourceUrl,
    rights_url: "https://d1.islamhouse.com/html/faq.htm",
    source_version: "test-v1",
  };
}

function duaEntry(language) {
  const localized = duaContent[language] || duaContent.en;
  return {
    id: "00000000-0000-7000-8000-000000000801",
    source_number: 1,
    slug: "waking-praise",
    collection: "hisn-al-muslim",
    collection_version: "test-v1",
    category: { source_number: 1, slug: "waking-up", title: localized.title },
    arabic_text: "الْحَمْدُ للَّهِ الَّذِي أَحْيَانَا بَعْدَ مَا أَمَاتَنَا، وَإِلَيْهِ النُّشُورُ",
    repetitions: 1,
    repetition_label: "",
    translation: {
      language_code: language,
      meaning_text: localized.meaning,
      transliteration: localized.transliteration,
    },
    evidence: [{
      kind: "source_note",
      provider: "islamhouse",
      source_name: "Hisn al-Muslim, note 15",
      source_reference: "Al-Bukhari 6314; Muslim 2711.",
      source_url: localized.sourceUrl,
      grade: "",
      external_id: "",
      verification_status: "source_only",
    }],
    source: duaSource(language),
    audio: [{
      id: "00000000-0000-7000-8000-000000000803",
      language_code: "ar",
      provider: "hisnmuslim",
      reader_name: "Hamad Al-Duraihem",
      reader_name_ar: "حمد الدريهم",
      url: "https://www.hisnmuslim.com/audio/ar/1.mp3",
      source_url: "https://hisnmuslim.com/",
      rights_url: "",
      source_version: "hisnmuslim-audio-test-v1",
    }],
  };
}

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
  const url = new URL(request.url || "/", `http://${host}:${port}`);
  const path = url.pathname;
  const language = duaContent[url.searchParams.get("language")] ? url.searchParams.get("language") : "en";

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

  if (path === "/api/v1/salah/courses") {
    const { course } = salahCourseExample;
    return sendJson(response, 200, [{
      slug: course.slug,
      version: course.version,
      methodology: course.methodology,
      languages: [...salahLanguages],
      published_at: course.published_at,
    }]);
  }
  if (path === "/api/v1/salah/courses/hanbali-umdah") {
    const requested = url.searchParams.get("language");
    if (!salahLanguages.has(requested)) return sendJson(response, 400, { detail: "Unsupported language." });
    return sendJson(response, 200, salahCourse(requested));
  }
  const salahMedia = path.match(/^\/media\/salah\/hanbali-umdah\/[^/]+\/([a-z-]+)-[0-9a-f]+\.webp$/);
  if (salahMedia) {
    response.writeHead(200, { "Content-Type": "image/svg+xml", "Cache-Control": "public, max-age=60" });
    return response.end(salahImage(salahMedia[1]));
  }
  if (path === "/media/audio/player-backgrounds/mountains-loop.webm") {
    response.writeHead(200, { "Content-Type": "video/webm", "Cache-Control": "public, max-age=60" });
    return response.end(playerBackgroundVideo);
  }

  if (path === "/api/v1/quran/editions") return sendJson(response, 200, [edition]);
  if (path === "/api/v1/dua/collections") {
    return sendJson(response, 200, [{
      id: "00000000-0000-7000-8000-000000000800",
      slug: "hisn-al-muslim",
      version: "test-v1",
      schema_version: 1,
      category_count: 132,
      entry_count: 267,
      published_at: publishedAt,
      source: duaSource(language),
    }]);
  }
  if (path === "/api/v1/dua/categories") {
    const localized = duaContent[language] || duaContent.en;
    return sendJson(response, 200, [{
      id: "00000000-0000-7000-8000-000000000802",
      collection: "hisn-al-muslim",
      collection_title: localized.edition,
      collection_version: "test-v1",
      source_number: 1,
      slug: "waking-up",
      title: localized.title,
      entry_count: 1,
    }]);
  }
  if (path === "/api/v1/dua/entries") {
    return sendJson(response, 200, { next: null, previous: null, results: [duaEntry(language)] });
  }
  if (path === "/api/v1/dua/entries/resolve") {
    if (
      url.searchParams.get("collection") === "hisn-al-muslim"
      && url.searchParams.get("source_number") === "1"
    ) {
      return sendJson(response, 200, duaEntry(language));
    }
    return sendJson(response, 404, { detail: "The published Dua entry was not found." });
  }
  if (path === "/api/v1/dua/entries/00000000-0000-7000-8000-000000000801") {
    return sendJson(response, 200, duaEntry(language));
  }
  if (path === "/api/v1/me/dua-favorites" && request.method === "GET") {
    return sendJson(response, 200, {
      results: [...duaFavoriteKeys].map((key) => {
        const [collection, sourceNumber] = key.split(":");
        return {
          id: "00000000-0000-7000-8000-000000000804",
          collection,
          source_number: Number(sourceNumber),
          is_favorite: true,
          created_at: publishedAt,
          ...(url.searchParams.get("include") === "entry"
            ? { entry: duaEntry(language) }
            : {}),
        };
      }),
    });
  }
  if (path === "/api/v1/me/dua-favorites/hisn-al-muslim/1" && request.method === "PUT") {
    const input = await readJson(request);
    const key = "hisn-al-muslim:1";
    if (input.is_favorite) duaFavoriteKeys.add(key);
    else duaFavoriteKeys.delete(key);
    return sendJson(response, 200, {
      id: input.is_favorite ? "00000000-0000-7000-8000-000000000804" : null,
      collection: "hisn-al-muslim",
      source_number: 1,
      is_favorite: Boolean(input.is_favorite),
      created_at: input.is_favorite ? publishedAt : null,
    });
  }
  if (path === "/api/v1/site/social-profiles") return sendJson(response, 200, socialProfiles);
  if (path === "/api/v1/player-backgrounds") return sendJson(response, 200, playerBackgrounds);
  if (path === "/api/v1/quran/editions/madani-hafs") return sendJson(response, 200, edition);
  if (path === "/api/v1/quran/editions/madani-hafs/surahs") return sendJson(response, 200, [surah]);
  if (path === "/api/v1/quran/editions/madani-hafs/surahs/1") return sendJson(response, 200, surah);
  if (path === "/api/v1/quran/editions/madani-hafs/surahs/1/ayahs") return sendJson(response, 200, ayahs);
  const ayahMatch = path.match(/^\/api\/v1\/quran\/editions\/madani-hafs\/ayahs\/1\/(\d+)$/);
  const publishedAyah = ayahMatch && ayahs.find((ayah) => ayah.number === Number(ayahMatch[1]));
  if (publishedAyah) return sendJson(response, 200, publishedAyah);
  if (path === "/api/v1/reciters") return sendJson(response, 200, paginated(reciters));
  const reciterMatch = path.match(/^\/api\/v1\/reciters\/([^/]+)$/);
  const listedReciter = reciterMatch && reciters.find((item) => item.id === reciterMatch[1]);
  if (listedReciter) return sendJson(response, 200, listedReciter);
  if (path === "/api/v1/recitations") {
    return sendJson(response, 200, paginated(recitationsMatching(url.searchParams)));
  }
  const recitationMatch = path.match(/^\/api\/v1\/recitations\/([^/]+)(\/tracks|\/surahs\/(\d+))?$/);
  const publishedRecitation = recitationMatch && recitationById(recitationMatch[1]);
  if (publishedRecitation && !recitationMatch[2]) return sendJson(response, 200, publishedRecitation);
  if (publishedRecitation && recitationMatch[2] === "/tracks") {
    return sendJson(response, 200, paginated(tracksFor(publishedRecitation.id)));
  }
  const playback = publishedRecitation && recitationMatch[3]
    && surahPlayback(publishedRecitation.id, Number(recitationMatch[3]));
  if (playback) return sendJson(response, 200, playback);

  return sendJson(response, 404, { detail: "Not found" });
});

server.listen(port, host);

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
