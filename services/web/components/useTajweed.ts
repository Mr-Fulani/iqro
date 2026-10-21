"use client";

import { useEffect, useState } from "react";
import { api, ApiError, type TajweedPage, type TajweedReference } from "../lib/api";

const MAX_CACHED_PAGES = 12;
const MISSING_MARKUP_MS = 60 * 60 * 1000;
let referenceRequest: Promise<TajweedReference | null> | null = null;
const pageRequests = new Map<number, Promise<TajweedPage | null>>();
let missingUntil = 0;

function loadReference(): Promise<TajweedReference | null> {
  referenceRequest ??= api.getTajweedRules().catch(() => {
    referenceRequest = null;
    return null;
  });
  return referenceRequest;
}

// Until the markup is imported pages answer 404 and the reader has no tajweed
// layer; one such answer spares the next page turns for an hour. Other failures
// are not remembered, so a later page retries.
function loadPage(pageNumber: number): Promise<TajweedPage | null> {
  if (Date.now() < missingUntil) return Promise.resolve(null);
  let request = pageRequests.get(pageNumber);
  if (!request) {
    request = api.getTajweedPage(pageNumber).catch((error: unknown) => {
      pageRequests.delete(pageNumber);
      if (error instanceof ApiError && error.status === 404) missingUntil = Date.now() + MISSING_MARKUP_MS;
      return null;
    });
    pageRequests.set(pageNumber, request);
    const oldest = pageRequests.keys().next().value;
    if (pageRequests.size > MAX_CACHED_PAGES && oldest !== undefined) pageRequests.delete(oldest);
  }
  return request;
}

export type TajweedData = { reference: TajweedReference; pages: TajweedPage[] };

/** Rule reference and per-page tajweed markup for QCF V4 pages, or null. */
export function useTajweed(pageNumbers: readonly number[], enabled: boolean): TajweedData | null {
  const key = enabled ? [...new Set(pageNumbers)].sort((left, right) => left - right).join(",") : "";
  const [state, setState] = useState<{ key: string; data: TajweedData | null }>({ key: "", data: null });

  useEffect(() => {
    if (!key) return;
    let cancelled = false;
    void Promise.all([loadReference(), Promise.all(key.split(",").map((value) => loadPage(Number(value))))])
      .then(([reference, pages]) => {
        if (cancelled) return;
        const loaded = pages.filter((page): page is TajweedPage => page !== null);
        setState({ key, data: reference && loaded.length ? { reference, pages: loaded } : null });
      });
    return () => { cancelled = true; };
  }, [key]);

  return state.key === key ? state.data : null;
}
