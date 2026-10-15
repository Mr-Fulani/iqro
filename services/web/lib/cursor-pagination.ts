import type { PaginatedResponse } from "./api";

export const DEFAULT_MAX_CURSOR_PAGES = 100;

export class CursorPaginationLimitError extends Error {
  constructor(maxPages: number) {
    super(`Cursor pagination did not finish within ${maxPages} pages`);
    this.name = "CursorPaginationLimitError";
  }
}

export function cursorFromNextUrl(next: string | null | undefined): string | undefined {
  if (!next) return undefined;
  return new URL(next, "http://api.local").searchParams.get("cursor") || undefined;
}

/**
 * Follows `next` links until the server reports the last page. Throws instead of
 * returning a silently truncated list when the cursor loops or the page cap is hit,
 * because callers use the result as the complete catalog or bookmark set.
 */
export async function collectCursorPages<T>(
  fetchPage: (cursor: string | undefined) => Promise<PaginatedResponse<T>>,
  maxPages = DEFAULT_MAX_CURSOR_PAGES,
): Promise<T[]> {
  const results: T[] = [];
  const seenCursors = new Set<string>();
  let cursor: string | undefined;
  for (let pageNumber = 0; pageNumber < maxPages; pageNumber += 1) {
    const page = await fetchPage(cursor);
    results.push(...(page.results || []));
    cursor = cursorFromNextUrl(page.next);
    if (!cursor) return results;
    if (seenCursors.has(cursor)) throw new CursorPaginationLimitError(pageNumber + 1);
    seenCursors.add(cursor);
  }
  throw new CursorPaginationLimitError(maxPages);
}
