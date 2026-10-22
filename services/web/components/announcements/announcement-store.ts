"use client";

import { useEffect, useState, useSyncExternalStore } from "react";
import { api } from "../../lib/api";
import {
  emptyState,
  loadState,
  markDismissed,
  markRead,
  mergeReceipts,
  parseAnnouncements,
  saveState,
  takeImpression,
  trackAnnouncementEvent,
  type Announcement,
  type AnnouncementSurface,
  type LocalAnnouncementState,
} from "../../lib/announcements";
import type { Locale } from "../../lib/i18n";

// One store for the header, the home page and the feed, so a mark set in one
// place is seen in the others at once.
const SERVER_STATE = emptyState();
let state: LocalAnnouncementState | null = null;
const listeners = new Set<() => void>();
const activeRequests = new Map<Locale, Promise<Announcement[]>>();
let syncedUser: string | null = null;

function current(): LocalAnnouncementState {
  if (state === null) state = loadState();
  return state;
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

function update(change: (value: LocalAnnouncementState) => LocalAnnouncementState): void {
  const next = change(current());
  if (next === state) return;
  state = next;
  saveState(next);
  for (const listener of listeners) listener();
}

export function useAnnouncementState(): LocalAnnouncementState {
  return useSyncExternalStore(subscribe, current, () => SERVER_STATE);
}

export function updateAnnouncementState(
  change: (value: LocalAnnouncementState) => LocalAnnouncementState,
): void {
  update(change);
}

function sendReceipt(id: string, body: { read?: boolean; dismissed?: boolean }): void {
  if (!api.getSession()?.access_token) return;
  void api
    .request(`/api/v1/me/announcement-receipts/${id}`, { method: "PUT", body: JSON.stringify(body) })
    .catch(() => {
      // The mark stays on this device; the next visit sends it again.
    });
}

export function readAnnouncement(item: Announcement, surface: AnnouncementSurface, opened = false): void {
  if (opened) trackAnnouncementEvent(item.id, surface, "open");
  if (current().read[item.id]) return;
  update((value) => markRead(value, item.id, Date.now()));
  sendReceipt(item.id, { read: true });
}

export function clickAnnouncement(item: Announcement, surface: AnnouncementSurface): void {
  trackAnnouncementEvent(item.id, surface, "click");
  readAnnouncement(item, surface);
}

export function dismissAnnouncement(item: Announcement, surface: AnnouncementSurface): void {
  trackAnnouncementEvent(item.id, surface, "dismiss");
  update((value) => markDismissed(value, item.id, Date.now()));
  sendReceipt(item.id, { dismissed: true });
}

export function countImpression(item: Announcement, surface: AnnouncementSurface): void {
  const result = takeImpression(current(), item.id, surface, Date.now());
  if (!result.fresh) return;
  update(() => result.state);
  trackAnnouncementEvent(item.id, surface, "impression");
}

function loadActive(locale: Locale): Promise<Announcement[]> {
  let request = activeRequests.get(locale);
  if (!request) {
    request = fetch(`/api/v1/announcements/active?platform=web&locale=${locale}`, {
      headers: { Accept: "application/json" },
    })
      .then((response) => (response.ok ? response.json() : null))
      .then(parseAnnouncements)
      .catch(() => []);
    activeRequests.set(locale, request);
  }
  return request;
}

/** Active announcements for the browser: the header and the "More" menu read them. */
export function useActiveAnnouncements(locale: Locale): Announcement[] {
  const [items, setItems] = useState<Announcement[]>([]);
  useEffect(() => {
    let alive = true;
    void loadActive(locale).then((result) => {
      if (alive) setItems(result);
    });
    return () => {
      alive = false;
    };
  }, [locale]);
  return items;
}

/** Marks of a signed-in person follow them between devices. */
export function useReceiptSync(userId: string | null | undefined): void {
  useEffect(() => {
    if (!userId || syncedUser === userId) return;
    syncedUser = userId;
    void api
      .request<unknown>("/api/v1/me/announcement-receipts", { cache: "no-store" })
      .then((receipts) => update((value) => mergeReceipts(value, receipts)))
      .catch(() => {
        syncedUser = null;
      });
  }, [userId]);
}
