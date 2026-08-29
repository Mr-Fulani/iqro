import type { PrayerCode } from "./types";

export const surahs = [
  { number: 1, ar: "الفاتحة", en: "Al-Faatiha", ru: "Аль-Фатиха", tr: "Fâtiha", ayahs: 7, place: "meccan" },
  { number: 2, ar: "البقرة", en: "Al-Baqara", ru: "Аль-Бакара", tr: "Bakara", ayahs: 286, place: "medinan" },
  { number: 3, ar: "آل عمران", en: "Aal-i-Imraan", ru: "Аль Имран", tr: "Âl-i İmrân", ayahs: 200, place: "medinan" },
  { number: 4, ar: "النساء", en: "An-Nisaa", ru: "Ан-Ниса", tr: "Nisâ", ayahs: 176, place: "medinan" },
  { number: 5, ar: "المائدة", en: "Al-Maaida", ru: "Аль-Маида", tr: "Mâide", ayahs: 120, place: "medinan" },
  { number: 6, ar: "الأنعام", en: "Al-An'aam", ru: "Аль-Анам", tr: "En'âm", ayahs: 165, place: "meccan" },
  { number: 18, ar: "الكهف", en: "Al-Kahf", ru: "Аль-Кахф", tr: "Kehf", ayahs: 110, place: "meccan" },
  { number: 36, ar: "يس", en: "Yaseen", ru: "Йа Син", tr: "Yâsîn", ayahs: 83, place: "meccan" },
  { number: 55, ar: "الرحمن", en: "Ar-Rahmaan", ru: "Ар-Рахман", tr: "Rahmân", ayahs: 78, place: "medinan" },
  { number: 67, ar: "الملك", en: "Al-Mulk", ru: "Аль-Мульк", tr: "Mülk", ayahs: 30, place: "meccan" },
  { number: 112, ar: "الإخلاص", en: "Al-Ikhlaas", ru: "Аль-Ихлас", tr: "İhlâs", ayahs: 4, place: "meccan" },
  { number: 114, ar: "الناس", en: "An-Naas", ru: "Ан-Нас", tr: "Nâs", ayahs: 6, place: "meccan" },
] as const;

// Canonical Uthmani text copied from the repository's active madani-hafs dataset.
export const alFatihaAyahs = [
  "بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ",
  "ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَٰلَمِينَ",
  "ٱلرَّحْمَٰنِ ٱلرَّحِيمِ",
  "مَٰلِكِ يَوْمِ ٱلدِّينِ",
  "إِيَّاكَ نَعْبُدُ وَإِيَّاكَ نَسْتَعِينُ",
  "ٱهْدِنَا ٱلصِّرَٰطَ ٱلْمُسْتَقِيمَ",
  "صِرَٰطَ ٱلَّذِينَ أَنْعَمْتَ عَلَيْهِمْ غَيْرِ ٱلْمَغْضُوبِ عَلَيْهِمْ وَلَا ٱلضَّآلِّينَ",
] as const;

export const reciters = [
  { id: "alafasy", ar: "مشاري راشد العفاسي", en: "Mishari Rashid Alafasy", ru: "Мишари Рашид аль-Афаси", tr: "Mishari Rashid Alafasy", initials: "MA" },
  { id: "husary", ar: "محمود خليل الحصري", en: "Mahmoud Khalil Al-Husary", ru: "Махмуд Халиль аль-Хусари", tr: "Mahmoud Khalil Al-Husary", initials: "MH" },
  { id: "abdulbaset", ar: "عبد الباسط عبد الصمد", en: "Abdul Baset Abdus Samad", ru: "Абдуль-Басит Абдус-Самад", tr: "Abdul Baset Abdus Samad", initials: "AB" },
  { id: "sudais", ar: "عبد الرحمن السديس", en: "Abdur-Rahman As-Sudais", ru: "Абдуррахман ас-Судайс", tr: "Abdur-Rahman As-Sudais", initials: "AS" },
] as const;

export const prayerTimes: Array<{ code: PrayerCode; ar: string; ru: string; en: string; tr: string; time: string }> = [
  { code: "fajr", ar: "الفجر", ru: "Фаджр", en: "Fajr", tr: "İmsak", time: "05:12" },
  { code: "dhuhr", ar: "الظهر", ru: "Зухр", en: "Dhuhr", tr: "Öğle", time: "13:09" },
  { code: "asr", ar: "العصر", ru: "Аср", en: "Asr", tr: "İkindi", time: "16:48" },
  { code: "maghrib", ar: "المغرب", ru: "Магриб", en: "Maghrib", tr: "Akşam", time: "19:42" },
  { code: "isha", ar: "العشاء", ru: "Иша", en: "Isha", tr: "Yatsı", time: "21:08" },
];

export const duaTopics = [
  { id: 1, slug: "waking-up", ru: "После пробуждения", en: "When waking up", ar: "أذكار الاستيقاظ من النوم", tr: "Uykudan uyanınca", count: 2, icon: "sunrise" },
  { id: 10, slug: "leaving-home", ru: "Выходя из дома", en: "Leaving the home", ar: "الذكر عند الخروج من المنزل", tr: "Evden çıkarken", count: 1, icon: "home" },
  { id: 13, slug: "entering-mosque", ru: "Входя в мечеть", en: "Entering the mosque", ar: "دعاء دخول المسجد", tr: "Câmiye girerken", count: 1, icon: "arch" },
  { id: 9, slug: "after-ablution", ru: "После омовения", en: "After ablution", ar: "الذكر بعد الفراغ من الوضوء", tr: "Abdestten sonra", count: 2, icon: "droplet" },
] as const;

// Entry 1 from the bundled Hisn al-Muslim source snapshot.
export const duaEntry = {
  sourceNumber: 1,
  title: { ru: "После пробуждения", en: "When waking up", ar: "أذكار الاستيقاظ من النوم", tr: "Uykudan uyanınca" },
  arabic: "الْحَمْدُ للَّهِ الَّذِي أَحْيَانَا بَعْدَ مَا أَمَاتَنَا، وَإِلَيْهِ النُّشُورُ",
  meaning: {
    ru: "Хвала Аллаху, воскресившему нас после того, как Он умертвил нас (то есть, послал нам сон, являющийся братом смерти), и к Нему воскресение.",
    en: "All praise is for Allah who gave us life after having taken it from us and unto Him is the resurrection.",
    ar: "الْحَمْدُ للَّهِ الَّذِي أَحْيَانَا بَعْدَ مَا أَمَاتَنَا، وَإِلَيْهِ النُّشُورُ",
    tr: "Bizi öldürdükten (uykudan) sonra dirilten Allah'a hamd olsun. Dönüş (Kıyâmet günü yeniden diriliş), yalnızca O'nadır.",
  },
  transliteration: "Аль-хамду ли-Лляхи аллязи ахйа-на ба'да ма амата-на ва иляй-хи-н-нушуру.",
  repetitions: 1,
  source: "Hisn al-Muslim, note 15 · Al-Bukhari 6314; Muslim 2711.",
};
