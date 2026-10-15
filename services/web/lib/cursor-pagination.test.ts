import assert from "node:assert/strict";
import test from "node:test";

import type { Bookmark, PaginatedResponse, Reciter } from "./api.ts";
import { indexAyahBookmarks } from "./ayah-bookmarks.ts";
import { collectCursorPages, CursorPaginationLimitError } from "./cursor-pagination.ts";

function cursorServer<T>(items: T[], pageSize: number) {
  const requestedCursors: Array<string | undefined> = [];
  const fetchPage = async (cursor: string | undefined): Promise<PaginatedResponse<T>> => {
    requestedCursors.push(cursor);
    const offset = cursor ? Number(cursor.replace("c", "")) : 0;
    const nextOffset = offset + pageSize;
    return {
      results: items.slice(offset, nextOffset),
      next: nextOffset < items.length
        ? `https://api.example.test/api/v1/items?cursor=c${nextOffset}&page_size=${pageSize}`
        : null,
      previous: null,
    };
  };
  return { fetchPage, requestedCursors };
}

function reciter(index: number): Reciter {
  return {
    id: `00000000-0000-7000-8000-${String(index).padStart(12, "0")}`,
    slug: `qf-${index}-reciter`,
    name_ar: `قارئ ${index}`,
    name_en: `Reciter ${index}`,
    name_ru: `Чтец ${index}`,
    country_code: "SA",
  };
}

function ayahBookmark(index: number): Bookmark {
  const surahNumber = 2 + Math.floor(index / 100);
  const ayahNumber = (index % 100) + 1;
  return {
    id: `bookmark-${index}`,
    edition_code: "madani-hafs",
    page_number: 2,
    ayah: { id: `ayah-${surahNumber}-${ayahNumber}`, surah_number: surahNumber, ayah_number: ayahNumber },
    label: `${surahNumber}:${ayahNumber}`,
    color_key: "emerald",
    revision: 1,
    deleted_at: null,
  };
}

test("collects a reciter catalog spread over several cursor pages", async () => {
  const catalog = Array.from({ length: 237 }, (_, index) => reciter(index + 1));
  const server = cursorServer(catalog, 100);

  const reciters = await collectCursorPages(server.fetchPage);

  assert.equal(reciters.length, 237);
  assert.equal(reciters.at(-1)?.slug, "qf-237-reciter");
  assert.deepEqual(server.requestedCursors, [undefined, "c100", "c200"]);
});

test("indexes every bookmark past the first page so the reader does not recreate them", async () => {
  const bookmarks = Array.from({ length: 120 }, (_, index) => ayahBookmark(index));
  const server = cursorServer(bookmarks, 50);

  const saved = indexAyahBookmarks(await collectCursorPages(server.fetchPage));

  assert.equal(server.requestedCursors.length, 3);
  assert.equal(Object.keys(saved).length, 120);
  assert.equal(saved["3:20"]?.id, "bookmark-119");
  assert.equal(new Set(Object.values(saved).map((bookmark) => bookmark.id)).size, 120);
});

test("skips deleted and page-only bookmarks in the ayah index", () => {
  const deleted = { ...ayahBookmark(0), deleted_at: "2026-10-01T00:00:00Z" };
  const pageOnly = { ...ayahBookmark(1), ayah: null };

  assert.deepEqual(indexAyahBookmarks([deleted, pageOnly]), {});
});

test("signals an incomplete result instead of truncating silently", async () => {
  const server = cursorServer(Array.from({ length: 30 }, (_, index) => index), 10);

  await assert.rejects(collectCursorPages(server.fetchPage, 2), CursorPaginationLimitError);
});

test("stops when the server repeats a cursor", async () => {
  const fetchPage = async (): Promise<PaginatedResponse<number>> => ({
    results: [1],
    next: "/api/v1/items?cursor=same",
    previous: null,
  });

  await assert.rejects(collectCursorPages(fetchPage), CursorPaginationLimitError);
});
