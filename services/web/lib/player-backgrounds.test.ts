import assert from "node:assert/strict";
import { existsSync } from "node:fs";
import test from "node:test";

import {
  BUNDLED_PLAYER_BACKGROUNDS,
  CLASSIC_PLAYER_BACKGROUND_ID,
  DEFAULT_PLAYER_BACKGROUND_ID,
  PLAYER_BACKGROUND_SCRIM,
  PLAYER_BACKGROUND_SCRIM_ALPHAS,
  PLAYER_BACKGROUND_STORAGE_KEY,
  loadPlayerBackgroundId,
  parsePlayerBackgrounds,
  playerBackgroundOptions,
  playerBackgroundTitle,
  rememberPlayerBackgroundId,
  resolvePlayerBackground,
} from "./player-backgrounds.ts";

function createMockStorage(): Storage {
  const store = new Map<string, string>();
  return {
    getItem: (key: string) => store.get(key) ?? null,
    setItem: (key: string, value: string) => {
      store.set(key, value);
    },
    removeItem: (key: string) => {
      store.delete(key);
    },
    clear: () => store.clear(),
    key: (index: number) => Array.from(store.keys())[index] ?? null,
    get length() {
      return store.size;
    },
  };
}

function payload(overrides: Record<string, unknown> = {}) {
  return {
    id: "019a0000-0000-7000-8000-000000000001",
    title_ar: "الجبال",
    title_en: "Mountains",
    title_ru: "Горы",
    title_tr: "Dağlar",
    image_url: "https://cdn.example.test/audio/player-backgrounds/abc.webp",
    sort_order: 10,
    ...overrides,
  };
}

function luminance(red: number, green: number, blue: number): number {
  const linear = [red, green, blue].map((channel) => {
    const value = channel / 255;
    return value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * linear[0]! + 0.7152 * linear[1]! + 0.0722 * linear[2]!;
}

function contrast(foreground: number[], background: number[]): number {
  const [lighter, darker] = [
    luminance(foreground[0]!, foreground[1]!, foreground[2]!),
    luminance(background[0]!, background[1]!, background[2]!),
  ].sort((left, right) => right - left);
  return (lighter! + 0.05) / (darker! + 0.05);
}

test("bundled backgrounds match the app and ship their WebP and video files", () => {
  assert.deepEqual(
    BUNDLED_PLAYER_BACKGROUNDS.map((item) => item.id),
    [
      CLASSIC_PLAYER_BACKGROUND_ID,
      DEFAULT_PLAYER_BACKGROUND_ID,
      "bundled:sea-dawn",
      "bundled:palm-oasis",
      "bundled:geometric",
      "bundled:reciter-video",
    ],
  );
  assert.equal(BUNDLED_PLAYER_BACKGROUNDS[0]!.image, null);
  for (const background of BUNDLED_PLAYER_BACKGROUNDS) {
    if (!background.image) continue;
    const files = [background.image.src, background.image.thumbnailSrc];
    if (background.videoSrc) files.push(background.videoSrc);
    for (const path of files) {
      assert.ok(existsSync(new URL(`../public${path}`, import.meta.url)), path);
    }
    assert.match(background.image.srcSet ?? "", /-192\.webp 192w, .+\.webp (?:768|720)w$/);
  }
  assert.deepEqual(
    BUNDLED_PLAYER_BACKGROUNDS.filter((background) => background.videoSrc).map((background) => background.videoSrc),
    ["/player-backgrounds/reciter-hood.mp4"],
  );
});

test("admin backgrounds are validated, sorted and namespaced", () => {
  const second = payload({ sort_order: 20, id: "019A0000-0000-7000-8000-000000000002" });
  const first = payload({ sort_order: 5, id: "019a0000-0000-7000-8000-000000000003" });
  const parsed = parsePlayerBackgrounds([
    second,
    first,
    payload({ id: "not-a-uuid" }),
    payload({ id: "019a0000-0000-7000-8000-000000000004", image_url: "javascript:alert(1)" }),
    payload({ id: "019a0000-0000-7000-8000-000000000005", image_url: "//evil.test/x.webp" }),
    payload({ id: "019a0000-0000-7000-8000-000000000006", title_en: " " }),
    { ...first },
    null,
  ]);

  assert.deepEqual(parsed.map((item) => item.id), [
    "remote:019a0000-0000-7000-8000-000000000003",
    "remote:019a0000-0000-7000-8000-000000000002",
  ]);
  assert.deepEqual(parsed[0]!.image, {
    src: "https://cdn.example.test/audio/player-backgrounds/abc.webp",
    thumbnailSrc: "https://cdn.example.test/audio/player-backgrounds/abc.webp",
  });
  assert.deepEqual(parsePlayerBackgrounds({ results: [first] }), []);
});

test("an admin video is kept only from a safe URL and its picture stays the poster", () => {
  const parsed = parsePlayerBackgrounds([
    payload({ video_url: "https://cdn.example.test/audio/player-backgrounds/abc.mp4" }),
    payload({ id: "019a0000-0000-7000-8000-000000000002", video_url: "/media/loop.webm", sort_order: 11 }),
    payload({ id: "019a0000-0000-7000-8000-000000000003", video_url: null, sort_order: 12 }),
    payload({ id: "019a0000-0000-7000-8000-000000000004", video_url: "javascript:alert(1)", sort_order: 13 }),
    payload({ id: "019a0000-0000-7000-8000-000000000005", video_url: "//evil.test/x.mp4", sort_order: 14 }),
    payload({ id: "019a0000-0000-7000-8000-000000000006", video_url: "https://user:pw@cdn.example.test/x.mp4", sort_order: 15 }),
  ]);

  assert.deepEqual(parsed.map((item) => item.videoSrc), [
    "https://cdn.example.test/audio/player-backgrounds/abc.mp4",
    "/media/loop.webm",
    undefined,
    undefined,
    undefined,
    undefined,
  ]);
  for (const background of parsed) {
    assert.equal(background.image?.src, "https://cdn.example.test/audio/player-backgrounds/abc.webp");
  }
  assert.equal("videoSrc" in parsed[2]!, false);
});

test("sound bars stay on unless the admin switched them off", () => {
  assert.ok(BUNDLED_PLAYER_BACKGROUNDS.every((background) => background.showEqualizer));
  const [shown, hidden] = parsePlayerBackgrounds([
    payload(),
    payload({ id: "019a0000-0000-7000-8000-000000000002", show_equalizer: false }),
  ]);
  assert.equal(shown!.showEqualizer, true);
  assert.equal(hidden!.showEqualizer, false);
});

test("an empty Turkish title falls back to English", () => {
  const [background] = parsePlayerBackgrounds([payload({ title_tr: "" })]);
  assert.equal(playerBackgroundTitle(background!, "tr"), "Mountains");
  assert.equal(playerBackgroundTitle(background!, "ru"), "Горы");
  assert.equal(playerBackgroundTitle(background!, "ar"), "الجبال");
});

test("a removed admin background resolves to the bundled default", () => {
  const options = playerBackgroundOptions(parsePlayerBackgrounds([payload()]));
  assert.equal(
    resolvePlayerBackground("remote:019a0000-0000-7000-8000-000000000001", options).id,
    "remote:019a0000-0000-7000-8000-000000000001",
  );
  assert.equal(
    resolvePlayerBackground("remote:019a0000-0000-7000-8000-00000000dead", options).id,
    DEFAULT_PLAYER_BACKGROUND_ID,
  );
  assert.equal(resolvePlayerBackground(null, options).id, DEFAULT_PLAYER_BACKGROUND_ID);
  assert.equal(
    resolvePlayerBackground(CLASSIC_PLAYER_BACKGROUND_ID, options).id,
    CLASSIC_PLAYER_BACKGROUND_ID,
  );
});

test("the choice is remembered locally and unsafe values are discarded", () => {
  const storage = createMockStorage();
  assert.equal(loadPlayerBackgroundId(storage), null);

  rememberPlayerBackgroundId("bundled:sea-dawn", storage);
  assert.equal(loadPlayerBackgroundId(storage), "bundled:sea-dawn");

  rememberPlayerBackgroundId("javascript:alert(1)", storage);
  assert.equal(loadPlayerBackgroundId(storage), "bundled:sea-dawn");

  storage.setItem(PLAYER_BACKGROUND_STORAGE_KEY, "<script>");
  assert.equal(loadPlayerBackgroundId(storage), null);
  assert.equal(storage.getItem(PLAYER_BACKGROUND_STORAGE_KEY), null);
});

test("the scrim keeps player text at WCAG AA over a pure white picture", () => {
  assert.equal(
    PLAYER_BACKGROUND_SCRIM,
    "linear-gradient(180deg, rgba(6, 29, 24, 0.68) 0%, rgba(6, 29, 24, 0.77) 50%, rgba(6, 29, 24, 0.86) 100%)",
  );
  const scrim = [0x06, 0x1d, 0x18];
  for (const alpha of PLAYER_BACKGROUND_SCRIM_ALPHAS) {
    const composite = scrim.map((channel) => channel * alpha + 255 * (1 - alpha));
    assert.ok(contrast([255, 255, 255], composite) >= 4.5, `white at ${alpha}`);
    // Secondary text colour used in app/globals.css.
    assert.ok(contrast([0xd5, 0xe3, 0xdf], composite) >= 4.5, `#d5e3df at ${alpha}`);
  }
});
