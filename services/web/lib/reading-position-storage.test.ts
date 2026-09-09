import assert from "node:assert/strict";
import test from "node:test";

import {
  readLocalReadingPosition,
  writeLocalReadingPosition,
  readingPositionStorageKey,
} from "./reading-position-storage.ts";

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
    length: store.size,
  };
}

test("readingPositionStorageKey returns expected prefix key", () => {
  assert.equal(
    readingPositionStorageKey("madani-hafs"),
    "iqro_quran_reading_position_v1:madani-hafs",
  );
});

test("writeLocalReadingPosition persists page, surah, ayah and updatedAt", () => {
  const storage = createMockStorage();
  writeLocalReadingPosition(
    "madani-hafs",
    { pageNumber: 45, surahNumber: 2, ayahNumber: 260 },
    storage,
  );

  const restored = readLocalReadingPosition("madani-hafs", storage);
  assert.ok(restored);
  assert.equal(restored.pageNumber, 45);
  assert.equal(restored.surahNumber, 2);
  assert.equal(restored.ayahNumber, 260);
  assert.ok(restored.updatedAt);
});

test("readLocalReadingPosition rejects invalid page numbers", () => {
  const storage = createMockStorage();
  storage.setItem(readingPositionStorageKey("madani-hafs"), JSON.stringify({ pageNumber: 0 }));
  assert.equal(readLocalReadingPosition("madani-hafs", storage), null);

  storage.setItem(readingPositionStorageKey("madani-hafs"), JSON.stringify({ pageNumber: 605 }));
  assert.equal(readLocalReadingPosition("madani-hafs", storage), null);

  storage.setItem(readingPositionStorageKey("madani-hafs"), JSON.stringify({ pageNumber: "not-a-number" }));
  assert.equal(readLocalReadingPosition("madani-hafs", storage), null);
});

test("readLocalReadingPosition returns null for empty or corrupted storage", () => {
  const storage = createMockStorage();
  assert.equal(readLocalReadingPosition("madani-hafs", storage), null);

  storage.setItem(readingPositionStorageKey("madani-hafs"), "invalid JSON text {");
  assert.equal(readLocalReadingPosition("madani-hafs", storage), null);
});
