import type { Locale } from "./i18n";

// Mirrors clients/iqro_mobile/lib/features/audio/player_backgrounds.dart so a
// listener sees the same choices on the site and in the app.
export const CLASSIC_PLAYER_BACKGROUND_ID = "bundled:classic";
export const DEFAULT_PLAYER_BACKGROUND_ID = "bundled:desert-night";
export const PLAYER_BACKGROUND_STORAGE_KEY = "quran_player_background_v1";

const MAX_REMOTE_BACKGROUNDS = 24;
const STORED_ID_PATTERN = /^(?:bundled:[a-z][a-z-]{0,31}|remote:[0-9a-f-]{36})$/;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

// #061D18 at 68% → 77% → 86% keeps white text above WCAG AA even over a pure
// white photo (see player-backgrounds.test.ts).
export const PLAYER_BACKGROUND_SCRIM_ALPHAS = [0.68, 0.77, 0.86] as const;
export const PLAYER_BACKGROUND_SCRIM = `linear-gradient(180deg, ${PLAYER_BACKGROUND_SCRIM_ALPHAS.map(
  (alpha, index) => `rgba(6, 29, 24, ${alpha}) ${index * 50}%`,
).join(", ")})`;

export type PlayerBackgroundPayload = {
  id: string;
  title_ar: string;
  title_en: string;
  title_ru: string;
  title_tr: string;
  image_url: string;
  // A silent looping video over image_url, which is its poster.
  video_url?: string | null;
  show_equalizer?: boolean;
  sort_order: number;
};

export type PlayerBackgroundImage = {
  src: string;
  // Only bundled images ship a small variant; admin uploads have one size.
  srcSet?: string;
  thumbnailSrc: string;
};

export type PlayerBackground = {
  id: string;
  titles: Record<Locale, string>;
  image: PlayerBackgroundImage | null;
  // Plays over the image, which stays as the poster and the picker tile.
  videoSrc?: string;
  // The admin can switch the sound bars off where they clash with a picture.
  showEqualizer: boolean;
};

function bundledImage(name: string, width = 768): PlayerBackgroundImage {
  const src = `/player-backgrounds/${name}.webp`;
  const thumbnailSrc = `/player-backgrounds/${name}-192.webp`;
  return { src, srcSet: `${thumbnailSrc} 192w, ${src} ${width}w`, thumbnailSrc };
}

export const BUNDLED_PLAYER_BACKGROUNDS: readonly PlayerBackground[] = [
  {
    id: CLASSIC_PLAYER_BACKGROUND_ID,
    titles: { ru: "Классический", en: "Classic", tr: "Klasik", ar: "كلاسيكي" },
    image: null,
    showEqualizer: true,
  },
  {
    id: DEFAULT_PLAYER_BACKGROUND_ID,
    titles: { ru: "Ночная пустыня", en: "Desert night", tr: "Çöl gecesi", ar: "ليل الصحراء" },
    image: bundledImage("desert-night"),
    showEqualizer: true,
  },
  {
    id: "bundled:sea-dawn",
    titles: { ru: "Море на рассвете", en: "Sea at dawn", tr: "Şafakta deniz", ar: "البحر عند الفجر" },
    image: bundledImage("sea-dawn"),
    showEqualizer: true,
  },
  {
    id: "bundled:palm-oasis",
    titles: { ru: "Оазис", en: "Oasis", tr: "Vaha", ar: "الواحة" },
    image: bundledImage("palm-oasis"),
    showEqualizer: true,
  },
  {
    id: "bundled:geometric",
    titles: { ru: "Орнамент", en: "Ornament", tr: "Süsleme", ar: "زخرفة" },
    image: bundledImage("geometric"),
    showEqualizer: true,
  },
  {
    id: "bundled:reciter-video",
    titles: { ru: "Чтец", en: "Reciter", tr: "Kâri", ar: "القارئ" },
    image: bundledImage("reciter-hood", 720),
    videoSrc: "/player-backgrounds/reciter-hood.mp4",
    showEqualizer: true,
  },
];

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function safeMediaUrl(value: unknown): string | null {
  const url = text(value);
  if (url.startsWith("/") && !url.startsWith("//")) return url;
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== "https:" && parsed.protocol !== "http:") return null;
    if (parsed.username || parsed.password) return null;
    return parsed.toString();
  } catch {
    return null;
  }
}

/** Keeps the valid admin backgrounds from the public API in display order. */
export function parsePlayerBackgrounds(payload: unknown): PlayerBackground[] {
  if (!Array.isArray(payload)) return [];
  const seen = new Set<string>();
  const items: Array<{ background: PlayerBackground; sortOrder: number }> = [];
  for (const raw of payload) {
    if (!raw || typeof raw !== "object") continue;
    const item = raw as Record<string, unknown>;
    const id = text(item.id).toLowerCase();
    const imageUrl = safeMediaUrl(item.image_url);
    // An unsafe video is dropped and the picture stays, as in the app.
    const videoUrl = safeMediaUrl(item.video_url);
    const english = text(item.title_en);
    if (!UUID_PATTERN.test(id) || !imageUrl || !english || seen.has(id)) continue;
    seen.add(id);
    items.push({
      background: {
        id: `remote:${id}`,
        titles: {
          en: english,
          ru: text(item.title_ru) || english,
          ar: text(item.title_ar) || english,
          tr: text(item.title_tr) || english,
        },
        image: { src: imageUrl, thumbnailSrc: imageUrl },
        ...(videoUrl ? { videoSrc: videoUrl } : {}),
        showEqualizer: item.show_equalizer !== false,
      },
      sortOrder: typeof item.sort_order === "number" ? item.sort_order : 0,
    });
  }
  return items
    .sort((left, right) => left.sortOrder - right.sortOrder)
    .slice(0, MAX_REMOTE_BACKGROUNDS)
    .map((item) => item.background);
}

export function playerBackgroundOptions(remote: readonly PlayerBackground[]): PlayerBackground[] {
  return [...BUNDLED_PLAYER_BACKGROUNDS, ...remote];
}

export function playerBackgroundTitle(background: PlayerBackground, locale: Locale): string {
  return background.titles[locale] || background.titles.en;
}

/** A removed admin background falls back to the bundled default. */
export function resolvePlayerBackground(
  id: string | null,
  available: readonly PlayerBackground[],
): PlayerBackground {
  return (
    available.find((item) => item.id === id) ||
    BUNDLED_PLAYER_BACKGROUNDS.find((item) => item.id === DEFAULT_PLAYER_BACKGROUND_ID)!
  );
}

function storageFor(storage?: Storage): Storage | null {
  if (storage) return storage;
  if (typeof window === "undefined") return null;
  try {
    return window.localStorage;
  } catch {
    return null;
  }
}

export function loadPlayerBackgroundId(storage?: Storage): string | null {
  const target = storageFor(storage);
  if (!target) return null;
  try {
    const value = target.getItem(PLAYER_BACKGROUND_STORAGE_KEY);
    if (value && STORED_ID_PATTERN.test(value)) return value;
    if (value) target.removeItem(PLAYER_BACKGROUND_STORAGE_KEY);
  } catch {
    // Storage can be unavailable in privacy-restricted browser contexts.
  }
  return null;
}

export function rememberPlayerBackgroundId(id: string, storage?: Storage): void {
  const target = storageFor(storage);
  if (!target || !STORED_ID_PATTERN.test(id)) return;
  try {
    target.setItem(PLAYER_BACKGROUND_STORAGE_KEY, id);
  } catch {
    // The choice still applies to the open page when storage is unavailable.
  }
}
