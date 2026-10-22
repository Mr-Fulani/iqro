// Announcements from /api/v1/announcements: parsing, the marks this device keeps
// (read, dismissed, bubble impressions) and the bubble frequency rules.
// Pure functions are tested with node --test; storage access is guarded.
//
// Waves: «Показать снова» in the admin raises an announcement's `wave`. A read or
// closed mark hides it from the home screen only in the wave it was made in; the
// bubble's frequency and impression limit start over in each wave.

export const ANNOUNCEMENT_STORAGE_KEY = "iqro_announcements_v1";
const SESSION_BUBBLE_KEY = "iqro_announcements_bubble_session_v1";
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const DAY_MS = 86_400_000;

export const ANNOUNCEMENT_KINDS = [
  "reciter",
  "feature",
  "app_release",
  "content",
  "fundraising",
  "general",
] as const;
export type AnnouncementKind = (typeof ANNOUNCEMENT_KINDS)[number];
export type BubbleFrequency = "each_visit" | "daily" | "every_3_days" | "weekly";
export type AnnouncementSurface = "bubble" | "card" | "feed" | "modal" | "push";
export type AnnouncementEvent = "impression" | "open" | "click" | "dismiss";

export type AnnouncementStep = {
  title: string;
  text: string;
  image_url: string | null;
  width: number | null;
  height: number | null;
};

export type Announcement = {
  id: string;
  kind: AnnouncementKind;
  priority: "low" | "normal" | "high" | "critical";
  pinned: boolean;
  starts_at: string;
  ends_at: string;
  surfaces: { bubble: boolean; home_card: boolean; modal: boolean };
  bubble: { icon: string; frequency: BubbleFrequency; max_impressions: number };
  audience: { auth: "all" | "guests" | "signed_in" };
  title: string;
  summary: string;
  body: string;
  image: {
    url: string;
    thumb_url: string | null;
    width: number | null;
    height: number | null;
    alt: string;
  } | null;
  steps: AnnouncementStep[];
  action: {
    type: string;
    label: string;
    web_path: string | null;
    app_route: string | null;
    external_url: string | null;
  };
  version: string;
  wave: number;
};

export type AnnouncementFeedPage = { next_cursor: string | null; results: Announcement[] };

export type LocalAnnouncementState = {
  read: Record<string, string>;
  dismissed: Record<string, string>;
  /** The latest wave in which each announcement was read or closed. */
  waves: Record<string, number>;
  bubble: Record<string, { shown: number; last: string; wave: number }>;
  impressions: Record<string, string>;
  lastModalAt: string | null;
};

const BUBBLE_INTERVAL_MS: Record<BubbleFrequency, number> = {
  each_visit: 0,
  daily: DAY_MS,
  every_3_days: 3 * DAY_MS,
  weekly: 7 * DAY_MS,
};
const MODAL_INTERVAL_MS = 7 * DAY_MS;

function isRecord(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function isString(value: unknown): value is string {
  return typeof value === "string";
}

// Paths come from the server; only same-site paths are followed in place.
export function safeSitePath(value: unknown): string | null {
  if (!isString(value) || !value.startsWith("/") || value.startsWith("//")) return null;
  return value;
}

function parseAnnouncement(value: unknown): Announcement | null {
  if (!isRecord(value)) return null;
  const { surfaces, bubble, audience, action, image, steps } = value;
  if (
    !isString(value.id) ||
    !UUID_PATTERN.test(value.id) ||
    !ANNOUNCEMENT_KINDS.includes(value.kind as AnnouncementKind) ||
    !isString(value.title) ||
    !isString(value.summary) ||
    !isString(value.starts_at) ||
    !isString(value.ends_at) ||
    !isRecord(surfaces) ||
    !isRecord(bubble) ||
    !isRecord(audience) ||
    !isRecord(action) ||
    !Array.isArray(steps)
  ) {
    return null;
  }
  const frequency = bubble.frequency as BubbleFrequency;
  return {
    id: value.id,
    kind: value.kind as AnnouncementKind,
    priority: (["low", "normal", "high", "critical"].includes(value.priority as string)
      ? value.priority
      : "normal") as Announcement["priority"],
    pinned: value.pinned === true,
    starts_at: value.starts_at,
    ends_at: value.ends_at,
    surfaces: {
      bubble: surfaces.bubble === true,
      home_card: surfaces.home_card === true,
      modal: surfaces.modal === true,
    },
    bubble: {
      icon: isString(bubble.icon) ? bubble.icon : "megaphone",
      frequency: frequency in BUBBLE_INTERVAL_MS ? frequency : "daily",
      max_impressions:
        typeof bubble.max_impressions === "number" && bubble.max_impressions > 0
          ? Math.floor(bubble.max_impressions)
          : 5,
    },
    audience: {
      auth: (["all", "guests", "signed_in"].includes(audience.auth as string)
        ? audience.auth
        : "all") as Announcement["audience"]["auth"],
    },
    title: value.title,
    summary: value.summary,
    body: isString(value.body) ? value.body : "",
    image:
      isRecord(image) && isString(image.url)
        ? {
            url: image.url,
            thumb_url: isString(image.thumb_url) ? image.thumb_url : null,
            width: typeof image.width === "number" ? image.width : null,
            height: typeof image.height === "number" ? image.height : null,
            alt: isString(image.alt) ? image.alt : "",
          }
        : null,
    steps: steps
      .filter((step): step is Record<string, unknown> => isRecord(step) && isString(step.title))
      .map((step) => ({
        title: step.title as string,
        text: isString(step.text) ? step.text : "",
        image_url: isString(step.image_url) ? step.image_url : null,
        width: typeof step.width === "number" ? step.width : null,
        height: typeof step.height === "number" ? step.height : null,
      })),
    action: {
      type: isString(action.type) ? action.type : "none",
      label: isString(action.label) ? action.label : "",
      web_path: safeSitePath(action.web_path),
      app_route: isString(action.app_route) ? action.app_route : null,
      external_url: safeSitePath(action.external_url),
    },
    version: isString(value.version) ? value.version : "",
    wave: wave(value.wave),
  };
}

function wave(value: unknown): number {
  return typeof value === "number" && Number.isInteger(value) && value > 0 ? value : 1;
}

export function parseAnnouncements(value: unknown): Announcement[] {
  if (!isRecord(value) || !Array.isArray(value.results)) return [];
  return value.results.map(parseAnnouncement).filter((item): item is Announcement => item !== null);
}

export function parseAnnouncementFeed(value: unknown): AnnouncementFeedPage {
  return {
    next_cursor: isRecord(value) && isString(value.next_cursor) ? value.next_cursor : null,
    results: parseAnnouncements(value),
  };
}

export function emptyState(): LocalAnnouncementState {
  return { read: {}, dismissed: {}, waves: {}, bubble: {}, impressions: {}, lastModalAt: null };
}

function stringMap(value: unknown): Record<string, string> {
  if (!isRecord(value)) return {};
  return Object.fromEntries(
    Object.entries(value).filter(
      (entry): entry is [string, string] => UUID_PATTERN.test(entry[0].split(":")[0]) && isString(entry[1]),
    ),
  );
}

export function parseState(raw: string | null): LocalAnnouncementState {
  if (!raw) return emptyState();
  try {
    const value: unknown = JSON.parse(raw);
    if (!isRecord(value)) return emptyState();
    const bubble: LocalAnnouncementState["bubble"] = {};
    if (isRecord(value.bubble)) {
      for (const [id, entry] of Object.entries(value.bubble)) {
        if (
          UUID_PATTERN.test(id) &&
          isRecord(entry) &&
          typeof entry.shown === "number" &&
          isString(entry.last)
        ) {
          bubble[id] = { shown: entry.shown, last: entry.last, wave: wave(entry.wave) };
        }
      }
    }
    const waves: Record<string, number> = {};
    if (isRecord(value.waves)) {
      for (const [id, number] of Object.entries(value.waves)) {
        if (UUID_PATTERN.test(id)) waves[id] = wave(number);
      }
    }
    return {
      read: stringMap(value.read),
      dismissed: stringMap(value.dismissed),
      waves,
      bubble,
      impressions: stringMap(value.impressions),
      lastModalAt: isString(value.lastModalAt) ? value.lastModalAt : null,
    };
  } catch {
    return emptyState();
  }
}

export function loadState(): LocalAnnouncementState {
  try {
    return parseState(window.localStorage.getItem(ANNOUNCEMENT_STORAGE_KEY));
  } catch {
    return emptyState();
  }
}

export function saveState(state: LocalAnnouncementState): void {
  try {
    window.localStorage.setItem(ANNOUNCEMENT_STORAGE_KEY, JSON.stringify(state));
  } catch {
    // Private mode or full storage: the marks live until the tab closes.
  }
}

export function forAudience(
  items: Announcement[],
  signedIn: boolean,
): Announcement[] {
  return items.filter(
    (item) =>
      item.audience.auth === "all" ||
      (item.audience.auth === "signed_in" ? signedIn : !signedIn),
  );
}

/** The wave this device last read or closed it in; marks from before waves count as 1. */
export function finishedWave(state: LocalAnnouncementState, id: string): number {
  return state.waves[id] ?? (state.read[id] || state.dismissed[id] ? 1 : 0);
}

/** Read or closed in the current wave: off the home screen, still in the feed. */
export function isFinished(item: Announcement, state: LocalAnnouncementState): boolean {
  return finishedWave(state, item.id) >= item.wave;
}

/** The card on desktop: one at a time, the first that was neither read nor closed. */
export function cardAnnouncement(
  items: Announcement[],
  state: LocalAnnouncementState,
): Announcement | null {
  return items.find((item) => item.surfaces.home_card && !isFinished(item, state)) ?? null;
}

/** Announcements the bubble carries now, by the admin's frequency and impression limit. */
export function bubbleAnnouncements(
  items: Announcement[],
  state: LocalAnnouncementState,
  now: number,
  shownThisSession: ReadonlySet<string>,
): Announcement[] {
  return items.filter((item) => {
    if (!item.surfaces.bubble || item.kind === "fundraising" || isFinished(item, state)) {
      return false;
    }
    if (shownThisSession.has(item.id)) return true;
    const seen = state.bubble[item.id];
    if (!seen || seen.wave < item.wave) return true;
    if (seen.shown >= item.bubble.max_impressions) return false;
    return now - Date.parse(seen.last) >= BUBBLE_INTERVAL_MS[item.bubble.frequency];
  });
}

export function recordBubbleShown(
  state: LocalAnnouncementState,
  items: Announcement[],
  now: number,
  shownThisSession: ReadonlySet<string>,
): LocalAnnouncementState {
  const bubble = { ...state.bubble };
  for (const item of items) {
    if (shownThisSession.has(item.id)) continue;
    const seen = bubble[item.id];
    const shown = seen && seen.wave >= item.wave ? seen.shown : 0;
    bubble[item.id] = { shown: shown + 1, last: new Date(now).toISOString(), wave: item.wave };
  }
  return { ...state, bubble };
}

/** The step window opens by itself at most once a week, for high-priority news only. */
export function modalAnnouncement(
  items: Announcement[],
  state: LocalAnnouncementState,
  now: number,
): Announcement | null {
  if (state.lastModalAt && now - Date.parse(state.lastModalAt) < MODAL_INTERVAL_MS) return null;
  return (
    items.find(
      (item) =>
        item.surfaces.modal &&
        item.steps.length > 0 &&
        (item.priority === "high" || item.priority === "critical") &&
        !isFinished(item, state),
    ) ?? null
  );
}

function finish(
  state: LocalAnnouncementState,
  mark: "read" | "dismissed",
  id: string,
  now: number,
  wave: number,
): LocalAnnouncementState {
  if (state[mark][id] && finishedWave(state, id) >= wave) return state;
  return {
    ...state,
    [mark]: { ...state[mark], [id]: state[mark][id] ?? new Date(now).toISOString() },
    waves: { ...state.waves, [id]: Math.max(finishedWave(state, id), wave) },
  };
}

export function markRead(
  state: LocalAnnouncementState,
  id: string,
  now: number,
  wave = 1,
): LocalAnnouncementState {
  return finish(state, "read", id, now, wave);
}

export function markDismissed(
  state: LocalAnnouncementState,
  id: string,
  now: number,
  wave = 1,
): LocalAnnouncementState {
  return finish(state, "dismissed", id, now, wave);
}

/** Server receipts of a signed-in person: marks only ever move forward. */
export function mergeReceipts(state: LocalAnnouncementState, receipts: unknown): LocalAnnouncementState {
  if (!isRecord(receipts) || !Array.isArray(receipts.results)) return state;
  const read = { ...state.read };
  const dismissed = { ...state.dismissed };
  const waves = { ...state.waves };
  for (const receipt of receipts.results) {
    if (!isRecord(receipt) || !isString(receipt.announcement_id)) continue;
    const id = receipt.announcement_id;
    if (!UUID_PATTERN.test(id)) continue;
    const marked = isString(receipt.read_at) || isString(receipt.dismissed_at);
    if (marked) waves[id] = Math.max(finishedWave(state, id), wave(receipt.wave));
    if (isString(receipt.read_at) && !read[id]) read[id] = receipt.read_at;
    if (isString(receipt.dismissed_at) && !dismissed[id]) dismissed[id] = receipt.dismissed_at;
  }
  return { ...state, read, dismissed, waves };
}

export function readBubbleSession(): Set<string> {
  try {
    const value: unknown = JSON.parse(window.sessionStorage.getItem(SESSION_BUBBLE_KEY) || "[]");
    return new Set(Array.isArray(value) ? value.filter((id) => isString(id) && UUID_PATTERN.test(id)) : []);
  } catch {
    return new Set();
  }
}

export function writeBubbleSession(ids: Iterable<string>): void {
  try {
    window.sessionStorage.setItem(SESSION_BUBBLE_KEY, JSON.stringify([...new Set(ids)]));
  } catch {
    // Without session storage the bubble simply counts each page view.
  }
}

/** One impression per announcement, surface and wave a day, decided on the device. */
export function takeImpression(
  state: LocalAnnouncementState,
  id: string,
  surface: AnnouncementSurface,
  now: number,
  wave = 1,
): { state: LocalAnnouncementState; fresh: boolean } {
  const key = `${id}:${surface}:${wave}`;
  const day = new Date(now).toISOString().slice(0, 10);
  if (state.impressions[key] === day) return { state, fresh: false };
  return { state: { ...state, impressions: { ...state.impressions, [key]: day } }, fresh: true };
}

type QueuedEvent = { id: string; surface: AnnouncementSurface; event: AnnouncementEvent; wave: number };
const queue: QueuedEvent[] = [];
let flushTimer: ReturnType<typeof setTimeout> | null = null;
let flushOnHideBound = false;

function flushEvents(): void {
  if (flushTimer) clearTimeout(flushTimer);
  flushTimer = null;
  if (!queue.length) return;
  const body = JSON.stringify({ platform: "web", events: queue.splice(0, 50) });
  try {
    const blob = new Blob([body], { type: "application/json" });
    if (!navigator.sendBeacon?.("/api/v1/announcements/events", blob)) {
      void fetch("/api/v1/announcements/events", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body,
        keepalive: true,
      }).catch(() => {});
    }
  } catch {
    // Counters are best effort and never block the page.
  }
  if (queue.length) flushEvents();
}

/** Anonymous counters: only daily sums per announcement reach the server. */
export function trackAnnouncementEvent(
  id: string,
  surface: AnnouncementSurface,
  event: AnnouncementEvent,
  wave: number,
): void {
  if (typeof window === "undefined") return;
  queue.push({ id, surface, event, wave });
  if (!flushOnHideBound) {
    flushOnHideBound = true;
    document.addEventListener("visibilitychange", () => {
      if (document.visibilityState === "hidden") flushEvents();
    });
  }
  if (!flushTimer) flushTimer = setTimeout(flushEvents, 5_000);
}

export function externalLink(item: Announcement, surface: AnnouncementSurface): string | null {
  if (!item.action.external_url) return null;
  return `${item.action.external_url}?platform=web&surface=${surface}`;
}

export type BodyBlock = { type: "paragraph" | "list"; lines: string[] };

/** The small Markdown subset admins write: paragraphs, "- " lists and **bold**. */
export function bodyBlocks(body: string): BodyBlock[] {
  return body
    .split(/\n{2,}/)
    .map((chunk) => chunk.split("\n").map((line) => line.trimEnd()).filter(Boolean))
    .filter((lines) => lines.length > 0)
    .map((lines) =>
      lines.every((line) => line.trimStart().startsWith("- "))
        ? { type: "list" as const, lines: lines.map((line) => line.trimStart().slice(2)) }
        : { type: "paragraph" as const, lines },
    );
}

export function boldSegments(line: string): { text: string; bold: boolean }[] {
  return line
    .split(/(\*\*[^*]+\*\*)/)
    .filter(Boolean)
    .map((part) =>
      part.startsWith("**") && part.endsWith("**") && part.length > 4
        ? { text: part.slice(2, -2), bold: true }
        : { text: part, bold: false },
    );
}
