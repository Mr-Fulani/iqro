import type { Recitation, Reciter } from "./api";
import type { MessageKey } from "./i18n";
import { reciterHasPortrait } from "./reciter-portraits.ts";

const CANONICAL_RECITER_SLUGS: Readonly<Record<string, string>> = {
  "qf-1-abdulbaset-abdulsamad-mujawwad": "qf-2-abdul-baset-abdul-samad",
  "qf-12-mahmoud-khaleel-al-husary": "qf-6-mahmoud-khaleel-al-husary",
};

export const HOME_POPULAR_RECITER_SLUGS = [
  "qf-7-mishari-rashid-al-afasy",
  "qf-3-abdur-rahman-as-sudais",
  "qf-2-abdul-baset-abdul-samad",
  "qf-9-muhammad-siddiq-al-minshawi",
  "qf-6-mahmoud-khaleel-al-husary",
  "qf-159-maher-al-muaiqly",
  "qf-13-saad-al-ghamdi",
  "qf-10-saud-ash-shuraym",
] as const;

export type RecitationRole = "listen" | "ayah_playback" | "memorization";

export function reciterPersonKey(reciter: Pick<Reciter, "slug"> | string): string {
  const slug = typeof reciter === "string" ? reciter : reciter.slug;
  return CANONICAL_RECITER_SLUGS[slug] || slug;
}

function normalizedName(value: string): string {
  return value
    .toLocaleLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f\u064b-\u0655\u0640]/g, "")
    .replace(/ı/g, "i")
    .replace(/ة/g, "ه")
    .replace(/ى/g, "ي")
    .replace(/[-‘’'ʼ]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

const CYRILLIC_LETTERS: Readonly<Record<string, string>> = {
  а: "a", б: "b", в: "v", г: "g", д: "d", е: "e", ж: "j", з: "z", и: "i", к: "k",
  л: "l", м: "m", н: "n", о: "o", п: "p", р: "r", с: "s", т: "t", у: "u", ф: "f",
  х: "h", ц: "s", ч: "ch", ш: "sh", щ: "sh", ъ: "", ы: "i", ь: "", э: "e", ю: "u",
  я: "a",
};

/**
 * What a word sounds like, whatever alphabet or spelling it came in: its
 * consonants, with the letters that transcribe one Arabic sound merged. Родзия,
 * Радия and Rodziah all read "rd"; the app holds the same rules.
 */
function nameSound(word: string): string {
  return word
    .replace(/[а-я]/g, (letter) => CYRILLIC_LETTERS[letter] ?? letter)
    .replace(/dzh|dj/g, "j")
    .replace(/dz/g, "d")
    .replace(/kh/g, "h")
    .replace(/gh/g, "g")
    .replace(/sh|ch/g, "x")
    .replace(/th/g, "s")
    .replace(/dh/g, "z")
    .replace(/[qc]/g, "k")
    .replace(/p/g, "b")
    .replace(/w/g, "v")
    .replace(/[aeiouy]/g, "")
    .replace(/h$/, "")
    .replace(/(.)\1+/g, "$1");
}

type SearchableReciter = Pick<Reciter, "name_ar" | "name_en" | "name_ru" | "name_tr">;

/**
 * The catalog's search: any word order, in any of the reciter's four names.
 * Only when nothing is spelled as asked does it look for names that sound the
 * same. The names are prepared once, so typing stays quick in a long catalog.
 */
export function reciterSearch<T extends SearchableReciter>(
  reciters: readonly T[],
): (query: string) => readonly T[] {
  const prepared = reciters.map((reciter) => {
    const names = [reciter.name_ar, reciter.name_en, reciter.name_ru, reciter.name_tr ?? ""]
      .map(normalizedName);
    return {
      reciter,
      text: names.join(" "),
      // Each word with those after it, so "абдульбасит" meets "Абдуль-Басит".
      sounds: names.flatMap((name) => {
        const words = name.split(" ").map(nameSound);
        return words.map((_, index) => words.slice(index).join(""));
      }),
    };
  });
  return (query) => {
    const words = normalizedName(query).split(" ").filter(Boolean);
    if (words.length === 0) return reciters;
    const spelled = prepared.filter(({ text }) => words.every((word) => text.includes(word)));
    if (spelled.length > 0) return spelled.map((item) => item.reciter);
    const sounds = words.map(nameSound);
    if (sounds.some((sound) => sound.length < 2)) return [];
    return prepared
      .filter((item) =>
        sounds.every((sound) => item.sounds.some((name) => name.startsWith(sound))),
      )
      .map((item) => item.reciter);
  };
}

export function groupRecitersByPerson(reciters: Reciter[]): Reciter[] {
  const people = new Map<string, Reciter>();
  for (const reciter of reciters) {
    const personKey = reciterPersonKey(reciter);
    const current = people.get(personKey);
    if (!current) {
      people.set(personKey, reciter);
      continue;
    }

    const representative = reciter.slug === personKey ? reciter : current;
    // The portrait and its avatar copy come from the same reciter.
    const portraitSource = [representative, current, reciter].find((item) => item.portrait_url);
    const portraitUrl = portraitSource?.portrait_url || null;
    const fullSupport = Boolean(current.full_support || reciter.full_support);
    people.set(
      personKey,
      portraitUrl === representative.portrait_url && fullSupport === representative.full_support
        ? representative
        : {
            ...representative,
            portrait_url: portraitUrl,
            portrait_thumbnail_url: portraitSource?.portrait_thumbnail_url ?? null,
            full_support: fullSupport,
          },
    );
  }
  return [...people.values()];
}

/** Reciters with a portrait open the list, each group in its own order. */
export function recitersWithPortraitsFirst(reciters: Reciter[]): Reciter[] {
  return [
    ...reciters.filter(reciterHasPortrait),
    ...reciters.filter((reciter) => !reciterHasPortrait(reciter)),
  ];
}

export function selectHomePopularReciters(reciters: Reciter[]): Reciter[] {
  const people = groupRecitersByPerson(reciters);
  const bySlug = new Map(people.map((reciter) => [reciterPersonKey(reciter), reciter]));
  const ranked = HOME_POPULAR_RECITER_SLUGS.flatMap((slug) => {
    const reciter = bySlug.get(slug);
    return reciter ? [reciter] : [];
  });
  const rankedKeys = new Set(ranked.map(reciterPersonKey));

  return [...ranked, ...people.filter((reciter) => !rankedKeys.has(reciterPersonKey(reciter)))]
    .slice(0, HOME_POPULAR_RECITER_SLUGS.length);
}

export function reciterSourcesForPerson(reciters: Reciter[], selected: Reciter): Reciter[] {
  const personKey = reciterPersonKey(selected);
  return reciters.filter((reciter) => reciterPersonKey(reciter) === personKey);
}

const STYLE_MESSAGE_KEYS = {
  murattal: "audio.style.murattal",
  mujawwad: "audio.style.mujawwad",
  muallim: "audio.style.muallim",
  "kids-repeat": "audio.style.kidsRepeat",
} as const satisfies Record<string, MessageKey>;

/** The translated name of a recitation style; unknown styles show as sent. */
export function recitationStyleLabel(style: string, t: (key: MessageKey) => string): string {
  const key = STYLE_MESSAGE_KEYS[style as keyof typeof STYLE_MESSAGE_KEYS];
  return key ? t(key) : style;
}

/** How a recording is told apart from the reciter's others: "<style> · <riwayah>". */
export function recitationVariantLabel(recitation: Recitation, t: (key: MessageKey) => string): string {
  return `${recitationStyleLabel(recitation.style, t)} · ${recitation.quran_edition.riwayah}`;
}

/** Listening recordings may hold only some surahs; older catalogs held all of them. */
export function recitationHasSurah(recitation: Recitation, surahNumber: number): boolean {
  const numbers = recitation.coverage.surah_numbers;
  return !numbers?.length || numbers.includes(surahNumber);
}

export function supportsRecitationRole(
  recitation: Recitation,
  role: RecitationRole,
): boolean {
  const capability = recitation.capabilities?.[role];
  if (typeof capability === "boolean") return capability;

  // Keep old cached/API responses readable during the additive contract rollout.
  if (role === "listen") return recitation.rights.stream && recitation.coverage.surah_count > 0;
  return recitation.timings.available && recitation.timings.complete === true;
}

export function recitationsForRole(
  recitations: Recitation[],
  role: RecitationRole,
): Recitation[] {
  return recitations.filter((recitation) => supportsRecitationRole(recitation, role));
}

/** The catalog's teaching reciter: what the Mushaf, Memorization and the courses play by default. */
export function teachingRecitation(recitations: Recitation[]): Recitation | undefined {
  return recitations.find((item) => item.teaching_default === true);
}

/**
 * The fixed voice of the tajweed course: al-Husary's Muallim (Quran.Foundation
 * recitation 12), whatever is picked in the players. Without it in the catalog
 * the teaching reciter, then Mishary al-Afasy, then the first one.
 */
export function tajweedCourseRecitation(available: Recitation[]): Recitation | undefined {
  const byPrefix = (prefix: string) => available
    .filter((item) => item.code.startsWith(prefix))
    .sort((left, right) => right.coverage.surah_count - left.coverage.surah_count)[0];
  return byPrefix("qf-12-") ?? teachingRecitation(available) ?? byPrefix("qf-7-") ?? available[0];
}

/** How many stand-in voices a range of selected words may try: each costs a request. */
export const WORD_TIMING_FALLBACK_LIMIT = 5;

/**
 * The voices, in order, that play selected words of a reciter without their
 * timings: al-Husary's Muallim (else the teaching reciter); his Murattal
 * (`qf-6-`) for the ayahs the Muallim has no timings of, where the sheikh
 * repeats words after a pause (2:9, 2:20, 3:7); then al-Afasy (`qf-7-`) and
 * other Quran Foundation recitations. His Mujawwad shares the `qf-12-` prefix
 * but has no word timings. Port of `wordTimingFallbackRecitations`.
 */
export function wordTimingFallbackRecitations(available: Recitation[]): Recitation[] {
  const byPrefix = (prefix: string) => available.find((item) => item.code.startsWith(prefix));
  const voices: Recitation[] = [];
  const add = (voice: Recitation | undefined) => {
    if (!voice || voices.some((item) => item.id === voice.id) || voice.code.includes("husary-mujawwad")) return;
    if (voices.length < WORD_TIMING_FALLBACK_LIMIT) voices.push(voice);
  };
  add(byPrefix("qf-12-muallim") ?? teachingRecitation(available));
  add(byPrefix("qf-6-"));
  add(byPrefix("qf-7-"));
  for (const recitation of available) if (recitation.code.startsWith("qf-")) add(recitation);
  return voices;
}

function publishedTimestamp(recitation: Recitation): number {
  const timestamp = Date.parse(recitation.published_at);
  return Number.isFinite(timestamp) ? timestamp : 0;
}

export function latestRecitationsByVariant(
  recitations: Recitation[],
  role?: RecitationRole,
): Recitation[] {
  const variants = new Map<string, Recitation>();
  const eligible = role ? recitationsForRole(recitations, role) : recitations;
  for (const recitation of eligible) {
    const key = [
      reciterPersonKey(recitation.reciter),
      recitation.style,
      recitation.quran_edition.code,
    ].join(":");
    const current = variants.get(key);
    if (!current || publishedTimestamp(recitation) > publishedTimestamp(current)) {
      variants.set(key, recitation);
    }
  }
  return [...variants.values()].sort((left, right) =>
    left.style.localeCompare(right.style) ||
    left.quran_edition.riwayah.localeCompare(right.quran_edition.riwayah),
  );
}
