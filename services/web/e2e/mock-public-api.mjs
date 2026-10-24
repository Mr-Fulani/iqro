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
const announcementReceipts = new Map();
const announcementEvents = [];
// «Показать снова» in the admin: the wave of each announcement, 1 unless raised.
const announcementWaves = new Map();

const announcementTexts = {
  ru: {
    reciter: ["Новый чтец: Хани ар-Рифаи", "Полное чтение Корана, 114 сур.", "Послушать"],
    feature: ["Живой компас Киблы", "Направление на Каабу в реальном времени.", "Открыть компас"],
    general: ["Курс намаза обновлён", "Новые уроки и озвучка шагов.", ""],
  },
  en: {
    reciter: ["New reciter: Hani ar-Rifai", "The whole Quran, 114 surahs.", "Listen"],
    feature: ["Live Qibla compass", "The direction of the Kaaba in real time.", "Open the compass"],
    general: ["The prayer course is updated", "New lessons and voiced steps.", ""],
  },
  ar: {
    reciter: ["قارئ جديد: هاني الرفاعي", "تلاوة كاملة للقرآن: 114 سورة.", "استمع"],
    feature: ["بوصلة القبلة المباشرة", "اتجاه الكعبة لحظة بلحظة.", "افتح البوصلة"],
    general: ["تحديث دورة الصلاة", "دروس جديدة وخطوات مسموعة.", ""],
  },
  tr: {
    reciter: ["Yeni kâri: Hani er-Rifai", "Kur'an'ın tamamı, 114 sure.", "Dinle"],
    feature: ["Canlı kıble pusulası", "Kâbe'nin yönü anında.", "Pusulayı aç"],
    general: ["Namaz kursu güncellendi", "Yeni dersler ve seslendirilmiş adımlar.", ""],
  },
};

function announcementFixtures(locale) {
  return announcementItems(locale).map((item) => ({ ...item, wave: announcementWaves.get(item.id) || 1 }));
}

function announcementItems(locale) {
  const texts = announcementTexts[locale] || announcementTexts.ru;
  const base = {
    priority: "normal",
    pinned: false,
    ends_at: "2099-01-01T00:00:00Z",
    surfaces: { bubble: true, home_card: true, modal: false },
    audience: { auth: "all" },
    body: "",
    image: null,
    steps: [],
  };
  return [
    {
      ...base,
      id: "019a0000-0000-7000-8000-00000000a001",
      kind: "reciter",
      // Late evening in UTC: already the next day for most of the world.
      starts_at: "2026-10-21T22:30:00Z",
      bubble: { icon: "portrait", frequency: "daily", max_impressions: 5 },
      title: texts.reciter[0],
      summary: texts.reciter[1],
      action: {
        type: "reciter",
        label: texts.reciter[2],
        web_path: `/${locale}/audio?reciter=${reciters[0].id}&play=1`,
        app_route: `/audio/reciter/${reciters[0].id}?play=1`,
        external_url: null,
      },
      version: "a1",
    },
    {
      ...base,
      id: "019a0000-0000-7000-8000-00000000a002",
      kind: "feature",
      starts_at: "2026-10-20T08:00:00Z",
      bubble: { icon: "sparkle", frequency: "daily", max_impressions: 5 },
      title: texts.feature[0],
      summary: texts.feature[1],
      steps: [
        { title: "1", text: "", image_url: null, width: null, height: null },
        { title: "2", text: "", image_url: null, width: null, height: null },
      ],
      action: {
        type: "screen",
        label: texts.feature[2],
        web_path: `/${locale}/prayer?qibla=1`,
        app_route: "/prayer?qibla=1",
        external_url: null,
      },
      version: "a2",
    },
    {
      ...base,
      id: "019a0000-0000-7000-8000-00000000a003",
      kind: "general",
      starts_at: "2026-09-01T08:00:00Z",
      ends_at: "2026-09-15T08:00:00Z",
      surfaces: { bubble: false, home_card: false, modal: false },
      bubble: { icon: "megaphone", frequency: "daily", max_impressions: 5 },
      title: texts.general[0],
      summary: texts.general[1],
      body: "**Уроки** по шагам.\n\n- вуду\n- фаджр",
      action: { type: "none", label: "", web_path: null, app_route: null, external_url: null },
      version: "a3",
    },
  ];
}

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

// The tajweed course contract example and real lesson examples from the Quran.Foundation
// markup (docs/tajweed/course.md); the language follows the request.
const tajweedCourseExample = JSON.parse(
  readFileSync(new URL("../../../docs/tajweed/course-document.example.json", import.meta.url), "utf8"),
);
const tajweedCourseExamples = JSON.parse(
  readFileSync(new URL("./fixtures/tajweed-course-examples.json", import.meta.url), "utf8"),
);

// Practice sessions sent by signed-in visitors; the state is a simple tally of them.
const tajweedPracticeSessions = new Map();

function tajweedPracticeState() {
  const answers = [...tajweedPracticeSessions.values()].flatMap((session) => session.answers);
  const days = [...tajweedPracticeSessions.values()].map((session) => session.local_date).sort();
  const correct = answers.filter((answer) => answer.correct).length;
  return {
    course: "tajweed",
    sessions: tajweedPracticeSessions.size,
    answers: answers.length,
    correct,
    score: correct,
    streak: { current: days.length ? 1 : 0, best: days.length ? 1 : 0, last_date: days.at(-1) ?? null },
    review: answers.filter((answer) => !answer.correct).map((answer) => ({
      key: answer.key, target: answer.target, type: answer.type, box: 1, due_at: answer.at,
    })),
  };
}

function tajweedCourse(language) {
  const document = structuredClone(tajweedCourseExample);
  document.course.language = language;
  return document;
}

// Thematic courses (docs/courses/README.md): the contract examples in Russian, and an
// Arabic release of the same course for RTL. Other languages see no course, as on the
// backend, where a course is visible only in the languages of its release.
const courseListExample = JSON.parse(
  readFileSync(new URL("../../../docs/courses/course-list.example.json", import.meta.url), "utf8"),
);
const courseDocumentExample = JSON.parse(
  readFileSync(new URL("../../../docs/courses/course-document.example.json", import.meta.url), "utf8"),
);
const courseLanguages = new Set(["ru", "en", "ar", "tr"]);
const ramadanLanguages = ["ru", "ar"];
const arabic = (text, extra = {}) => ({ text, lang: "ar", ...extra });
const ramadanArabic = {
  course: ["رمضان", "الصيام والنية والتراويح وليلة القدر وزكاة الفطر: ما ينبغي معرفته قبل الشهر."],
  lessons: {
    "smysl-posta": ["معنى الصيام", "لماذا يصوم المسلمون في رمضان."],
    namerenie: ["النية", "ما النية ومتى تكون."],
    taraviikh: ["التراويح", "قيام ليالي رمضان."],
  },
  notes: [
    { type: "heading", dir: "rtl", text: [arabic("ما النية")] },
    {
      type: "paragraph",
      dir: "rtl",
      lines: [[arabic("النية هي "), arabic("عزم القلب", { bold: true }), arabic(" على الصيام لله.")]],
    },
    { type: "list", dir: "rtl", ordered: false, items: [[arabic("تميّز النية العبادة عن العادة.")], [arabic("محلها القلب.")]] },
    { type: "quote", dir: "rtl", lines: [[arabic("إنما الأعمال بالنيات")]], source: "صحيح البخاري، 1" },
    { type: "note", dir: "rtl", lines: [[arabic("تُبيَّت النية من الليل.")]] },
  ],
};

const toMockMedia = (url) => url.replace("https://media.iqro.forum/", "/media/");

function courseCover(cover) {
  return cover && { ...cover, url: toMockMedia(cover.url), thumb_url: toMockMedia(cover.thumb_url) };
}

// The lesson video of the example, with the Arabic document showing the Russian voice:
// a language without its own dub gets the main video, as the server decides.
function courseVideo(video) {
  return video && {
    ...video,
    url: toMockMedia(video.url),
    poster: { ...video.poster, url: toMockMedia(video.poster.url), small_url: toMockMedia(video.poster.small_url) },
  };
}
// VP9 decodes in every Chromium build; the Linux CI one may lack H.264.
const courseLessonVideo = readFileSync(new URL("./fixtures/course-lesson-video.webm", import.meta.url));

// Slides and banners: real WebP at the contract's sizes (1600 px and 800 px on the longer side),
// about as heavy as the server's files. The hash in the path picks the picture.
const courseMediaPictures = {
  "1111111111aaaaaaaaaa": "slide-timeline",
  "3333333333cccccccccc": "slide-pattern",
  "4444444444dddddddddd": "slide-lantern",
  "5555555555eeeeeeeeee": "slide-timeline",
  "6666666666ffffffffff": "slide-pattern",
  "2222222222bbbbbbbbbb": "banner-minaret",
};
const courseImage = (image) => ({ ...image, url: toMockMedia(image.url), small_url: toMockMedia(image.small_url) });
const courseSlide = (hash, width, height, caption, dir = "ltr") => ({
  image: courseImage({
    url: `https://media.iqro.forum/courses/slides/${hash}.webp`,
    small_url: `https://media.iqro.forum/courses/slides/${hash}-800.webp`,
    width,
    height,
  }),
  caption,
  alt: caption,
  dir,
});

// The example's two slides and three more: a tall one (3:4, above the frame's 4:5 limit) among them.
function courseMedia(media, language) {
  return media.map((block) => {
    if (block.type === "video") return { ...block, video: courseVideo(block.video) };
    if (block.type === "banner") return { ...block, image: courseImage(block.image) };
    if (block.type !== "slides") return block;
    const slides = block.slides.map((slide) => ({ ...slide, image: courseImage(slide.image) }));
    slides.push(
      courseSlide("4444444444dddddddddd", 1200, 1600, "Фонарь Рамадана"),
      courseSlide("5555555555eeeeeeeeee", 1600, 1200, ""),
      courseSlide("6666666666ffffffffff", 1600, 900, "Узор: намерение — в сердце"),
    );
    if (language === "ar") {
      const captions = ["متى تكون النية", "نويت صوم غد", "فانوس رمضان", "", "النية محلها القلب"];
      slides.forEach((slide, index) => Object.assign(slide, { caption: captions[index], alt: captions[index], dir: "rtl" }));
    }
    return { ...block, slides };
  });
}

function ramadanCourse(language) {
  const document = structuredClone(courseDocumentExample);
  document.course.language = language;
  document.course.languages = ramadanLanguages;
  document.course.cover = courseCover(document.course.cover);
  for (const lesson of document.lessons) {
    lesson.video = courseVideo(lesson.video);
    lesson.media = courseMedia(lesson.media, language);
  }
  if (language === "ar") {
    [document.course.title, document.course.summary] = ramadanArabic.course;
    document.course.source = "المؤلف والمصادر بعد المراجعة";
    for (const lesson of document.lessons) {
      [lesson.title, lesson.summary] = ramadanArabic.lessons[lesson.slug];
      lesson.notes = ramadanArabic.notes;
      lesson.sources = ["صحيح البخاري"];
    }
  }
  return document;
}

function courseList(language) {
  if (!ramadanLanguages.includes(language)) return { language, courses: [] };
  const list = structuredClone(courseListExample);
  const { course } = ramadanCourse(language);
  list.language = language;
  list.courses[0] = { ...list.courses[0], title: course.title, summary: course.summary, cover: course.cover };
  return list;
}

function courseCoverImage(width, height) {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}" viewBox="0 0 1280 720">`
    + `<rect width="1280" height="720" fill="#065f46"/><circle cx="980" cy="230" r="120" fill="#fbbf24"/>`
    + `<circle cx="1030" cy="200" r="110" fill="#065f46"/></svg>`;
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
    // In capitals, as the source prints most Russian chapters; pages read it
    // in sentence case, as the app does.
    title: "СЛОВА ПОМИНАНИЯ ПРИ ПРОБУЖДЕНИИ ОТО СНА",
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

// A second chapter of the "sleep" topic: the topic then lists its chapters,
// and this du'a has the basmala before a surah and is said three times.
const bedtimeContent = {
  ar: { title: "الذكر عند النوم", meaning: "", second: "" },
  en: {
    title: "BEFORE SLEEPING",
    meaning: "Recite Surat al-Ikhlas three times.",
    second: "In Your name, O Allah, I die and I live.",
  },
  ru: {
    title: "СЛОВА ПОМИНАНИЯ ПЕРЕД СНОМ",
    meaning: "Прочитать суру «Искренность» три раза.",
    second: "С именем Твоим, о Аллах, я умираю и оживаю.",
  },
  tr: {
    title: "UYUMADAN ÖNCE YAPILAN DUALAR",
    meaning: "İhlâs sûresini üç kez okumak.",
    second: "Allah'ım, Senin isminle ölür ve dirilirim.",
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

function bedtimeEntry(language) {
  const localized = bedtimeContent[language] || bedtimeContent.en;
  return {
    id: "00000000-0000-7000-8000-000000000811",
    source_number: 100,
    slug: "bedtime-ikhlas",
    collection: "hisn-al-muslim",
    collection_version: "test-v1",
    category: { source_number: 28, slug: "before-sleeping", title: localized.title },
    arabic_text: "بِسْمِ اللَّهِ الرَّحْمَنِ الرَّحِيمِ ﴿قُلْ هُوَ اللَّهُ أَحَدٌ﴾",
    repetitions: 3,
    repetition_label: "",
    translation: {
      language_code: language,
      meaning_text: localized.meaning,
      transliteration: "",
    },
    evidence: [{
      kind: "hadith",
      provider: "islamhouse",
      source_name: "",
      source_reference: "Al-Bukhari 5017.",
      source_url: "",
      grade: "",
      external_id: "",
      verification_status: "editorially_verified",
    }],
    source: duaSource(language),
    audio: [],
  };
}

function bedtimeSecondEntry(language) {
  const localized = bedtimeContent[language] || bedtimeContent.en;
  const first = bedtimeEntry(language);
  return {
    ...first,
    id: "00000000-0000-7000-8000-000000000813",
    source_number: 101,
    slug: "bedtime-name",
    arabic_text: "بِاسْمِكَ اللَّهُمَّ أَمُوتُ وَأَحْيَا",
    repetitions: 1,
    translation: { ...first.translation, meaning_text: localized.second },
    evidence: [{ ...first.evidence[0], source_reference: "Al-Bukhari 6324." }],
  };
}

function duaEntries(language) {
  return [duaEntry(language), bedtimeEntry(language), bedtimeSecondEntry(language)];
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

  if (path === "/api/v1/courses" || path.startsWith("/api/v1/courses/")) {
    const requested = url.searchParams.get("language") ?? "ru";
    if (!courseLanguages.has(requested)) {
      return sendJson(response, 400, { language: ["Поддерживаются: ar, en, ru, tr."] });
    }
    if (path === "/api/v1/courses") return sendJson(response, 200, courseList(requested));
    if (path === "/api/v1/courses/ramadan" && ramadanLanguages.includes(requested)) {
      return sendJson(response, 200, ramadanCourse(requested));
    }
    // A release from a newer backend: the site asks for a reload instead of guessing.
    if (path === "/api/v1/courses/future-format") {
      return sendJson(response, 200, { ...ramadanCourse("ru"), schema_version: 2 });
    }
    return sendJson(response, 404, { detail: "Такого курса нет." });
  }
  const coverMedia = path.match(/^\/media\/courses\/(?:covers\/[0-9a-f]+(-640)?|posters\/[0-9a-f-]+-(?:1280|(640)))\.webp$/);
  if (coverMedia) {
    response.writeHead(200, { "Content-Type": "image/svg+xml", "Cache-Control": "public, max-age=60" });
    return response.end(coverMedia[1] || coverMedia[2] ? courseCoverImage(640, 360) : courseCoverImage(1280, 720));
  }
  const coursePicture = path.match(/^\/media\/courses\/(?:slides|banners)\/([0-9a-f]{20})(-800)?\.webp$/);
  if (coursePicture && courseMediaPictures[coursePicture[1]]) {
    const file = `${courseMediaPictures[coursePicture[1]]}${coursePicture[2] ?? ""}.webp`;
    response.writeHead(200, { "Content-Type": "image/webp", "Cache-Control": "public, max-age=60" });
    return response.end(readFileSync(new URL(`./fixtures/course-media/${file}`, import.meta.url)));
  }
  if (/^\/media\/courses\/videos\/[0-9a-f-]+\.mp4$/.test(path)) {
    // Byte ranges, as R2 serves them: without them the browser cannot seek.
    const headers = { "Content-Type": "video/webm", "Cache-Control": "public, max-age=60", "Accept-Ranges": "bytes" };
    const range = /^bytes=(\d*)-(\d*)$/.exec(request.headers.range ?? "");
    if (!range) {
      response.writeHead(200, { ...headers, "Content-Length": courseLessonVideo.length });
      return response.end(courseLessonVideo);
    }
    const last = courseLessonVideo.length - 1;
    const start = range[1] ? Number(range[1]) : Math.max(0, last + 1 - Number(range[2]));
    const end = range[1] && range[2] ? Math.min(Number(range[2]), last) : last;
    response.writeHead(206, { ...headers, "Content-Range": `bytes ${start}-${end}/${last + 1}`, "Content-Length": end - start + 1 });
    return response.end(courseLessonVideo.subarray(start, end + 1));
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
  if (path === "/api/v1/tajweed/courses") {
    const { course } = tajweedCourseExample;
    return sendJson(response, 200, [{
      slug: course.slug,
      version: course.version,
      languages: [...salahLanguages],
      published_at: course.published_at,
    }]);
  }
  if (path === "/api/v1/tajweed/courses/tajweed") {
    const requested = url.searchParams.get("language");
    if (!salahLanguages.has(requested)) return sendJson(response, 400, { detail: "Unsupported language." });
    return sendJson(response, 200, tajweedCourse(requested));
  }
  const tajweedExamples = path.match(/^\/api\/v1\/tajweed\/courses\/tajweed\/lessons\/([a-z-]+)\/examples$/);
  if (tajweedExamples) {
    const lesson = tajweedCourseExamples[tajweedExamples[1]];
    if (!lesson) return sendJson(response, 404, { detail: "No such lesson." });
    const offset = Number(url.searchParams.get("offset") ?? 0);
    const limit = Number(url.searchParams.get("limit") ?? 4);
    const examples = lesson.examples.slice(offset, offset + limit);
    return sendJson(response, 200, {
      lesson: tajweedExamples[1],
      target: lesson.target,
      offset,
      next_offset: offset + limit < lesson.examples.length ? offset + limit : null,
      examples,
    });
  }
  if (path === "/api/v1/tajweed/courses/tajweed/practice") {
    // Deterministic tasks from the lesson examples: lessons in turn, the seed picks the ayah.
    const lessons = (url.searchParams.get("lessons") ?? "").split(",").filter((slug) => tajweedCourseExamples[slug]);
    if (!lessons.length) return sendJson(response, 400, { lessons: "No lesson of this course." });
    const targets = lessons.map((slug) => tajweedCourseExamples[slug].target);
    const count = Number(url.searchParams.get("count") ?? 8);
    const seed = Number(url.searchParams.get("seed") ?? 0);
    const types = targets.length > 1 ? ["find", "identify", "listen"] : ["find"];
    const task = (type, example, target, review) => ({
      key: `${type}~${example.verse_key}~${target}`,
      type,
      target,
      review,
      example,
      focus: 0,
      ...(type === "find" ? {} : { options: [target, ...targets.filter((item) => item !== target).slice(0, 3)] }),
    });
    const tasks = [];
    for (const key of (url.searchParams.get("review") ?? "").split(",").filter(Boolean)) {
      const [type, verseKey, target] = key.split("~");
      const lesson = lessons.find((slug) => tajweedCourseExamples[slug].target === target);
      const example = lesson && tajweedCourseExamples[lesson].examples.find((item) => item.verse_key === verseKey);
      if (example) tasks.push(task(targets.length > 1 ? type : "find", example, target, true));
    }
    for (let index = 0; tasks.length < count; index += 1) {
      const lesson = tajweedCourseExamples[lessons[index % lessons.length]];
      const example = lesson.examples[(seed + index) % lesson.examples.length];
      if (!tasks.some((item) => item.example.verse_key === example.verse_key && item.target === lesson.target)) {
        tasks.push(task(types[index % types.length], example, lesson.target, false));
      }
      if (index > count * 4) break;
    }
    return sendJson(response, 200, { seed, tasks: tasks.slice(0, count) });
  }
  if (path === "/api/v1/me/tajweed/practice-sessions" && request.method === "POST") {
    const input = await readJson(request);
    const known = tajweedPracticeSessions.has(input.id);
    tajweedPracticeSessions.set(input.id, input);
    return sendJson(response, known ? 200 : 201, tajweedPracticeState());
  }
  if (path === "/api/v1/me/tajweed/practice/tajweed") {
    return sendJson(response, 200, tajweedPracticeState());
  }
  if (path === "/api/v1/me/tajweed/progress/tajweed") {
    const input = request.method === "PUT" ? await readJson(request) : { lessons: {} };
    return sendJson(response, 200, { course: "tajweed", lessons: input.lessons ?? {} });
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
    }, {
      id: "00000000-0000-7000-8000-000000000812",
      collection: "hisn-al-muslim",
      collection_title: localized.edition,
      collection_version: "test-v1",
      source_number: 28,
      slug: "before-sleeping",
      title: (bedtimeContent[language] || bedtimeContent.en).title,
      entry_count: 2,
    }]);
  }
  if (path === "/api/v1/dua/entries") {
    const category = url.searchParams.get("category");
    const query = url.searchParams.get("q")?.toLowerCase();
    const results = duaEntries(language).filter((entry) =>
      (!category || entry.category.slug === category)
      && (!query || [entry.arabic_text, entry.translation.meaning_text]
        .some((text) => text.toLowerCase().includes(query))));
    return sendJson(response, 200, { next: null, previous: null, results });
  }
  if (path === "/api/v1/dua/entries/resolve") {
    const entry = duaEntries(language).find((item) =>
      item.collection === url.searchParams.get("collection")
      && String(item.source_number) === url.searchParams.get("source_number"));
    if (entry) return sendJson(response, 200, entry);
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
            ? { entry: duaEntries(language).find((item) => item.source_number === Number(sourceNumber)) }
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
  if (path === "/api/v1/announcements/active") {
    const items = announcementFixtures(url.searchParams.get("locale"));
    return sendJson(response, 200, { enabled: true, results: items.filter((item) => item.surfaces.home_card) });
  }
  if (path === "/api/v1/announcements") {
    const kind = url.searchParams.get("kind");
    const items = announcementFixtures(url.searchParams.get("locale"));
    return sendJson(response, 200, {
      next_cursor: null,
      results: kind ? items.filter((item) => item.kind === kind) : items,
    });
  }
  if (path === "/api/v1/announcements/events" && request.method === "POST") {
    const input = await readJson(request);
    announcementEvents.push(...(input.events || []));
    return sendJson(response, 202, { accepted: (input.events || []).length });
  }
  if (path === "/__test__/announcement-events") {
    return sendJson(response, 200, { events: announcementEvents });
  }
  if (path === "/__test__/announcements/show-again" && request.method === "POST") {
    const id = url.searchParams.get("id");
    announcementWaves.set(id, (announcementWaves.get(id) || 1) + 1);
    return sendJson(response, 200, { id, wave: announcementWaves.get(id) });
  }
  if (path === "/__test__/announcements/reset" && request.method === "POST") {
    announcementWaves.clear();
    announcementReceipts.clear();
    return sendJson(response, 200, { reset: true });
  }
  if (path === "/api/v1/me/announcement-receipts") {
    return sendJson(response, 200, { results: [...announcementReceipts.values()] });
  }
  const receiptMatch = path.match(/^\/api\/v1\/me\/announcement-receipts\/([0-9a-f-]+)$/);
  if (receiptMatch && request.method === "PUT") {
    const input = await readJson(request);
    const previous = announcementReceipts.get(receiptMatch[1]) || {
      announcement_id: receiptMatch[1],
      read_at: null,
      dismissed_at: null,
      wave: 1,
    };
    const receipt = {
      ...previous,
      read_at: previous.read_at || (input.read ? publishedAt : null),
      dismissed_at: previous.dismissed_at || (input.dismissed ? publishedAt : null),
      wave: input.read || input.dismissed ? Math.max(previous.wave, input.wave || 1) : previous.wave,
    };
    announcementReceipts.set(receiptMatch[1], receipt);
    return sendJson(response, 200, receipt);
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
