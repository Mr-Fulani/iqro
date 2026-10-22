import assert from "node:assert/strict";
import test from "node:test";

import {
  bodyBlocks,
  boldSegments,
  bubbleAnnouncements,
  cardAnnouncement,
  emptyState,
  forAudience,
  isFinished,
  markDismissed,
  markRead,
  mergeReceipts,
  modalAnnouncement,
  parseAnnouncementFeed,
  parseAnnouncements,
  parseState,
  recordBubbleShown,
  takeImpression,
  type Announcement,
} from "./announcements.ts";

const DAY = 86_400_000;
const NOW = Date.parse("2026-10-22T10:00:00Z");
const ID_A = "01a16092-1950-77f9-9d76-0ea6de5279b8";
const ID_B = "01a16092-1950-77f9-9d76-0ea6de5279b9";

function payload(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    id: ID_A,
    kind: "reciter",
    priority: "normal",
    pinned: false,
    starts_at: "2026-10-21T00:00:00Z",
    ends_at: "2026-11-04T00:00:00Z",
    surfaces: { bubble: true, home_card: true, modal: false },
    bubble: { icon: "portrait", frequency: "daily", max_impressions: 3 },
    audience: { auth: "all" },
    title: "Новый чтец",
    summary: "114 сур",
    body: "",
    image: null,
    steps: [],
    action: { type: "reciter", label: "Послушать", web_path: "/ru/audio?reciter=x", app_route: "/audio/reciter/x", external_url: null },
    version: "v1",
    ...overrides,
  };
}

function item(overrides: Record<string, unknown> = {}): Announcement {
  const [parsed] = parseAnnouncements({ results: [payload(overrides)] });
  assert.ok(parsed);
  return parsed;
}

test("parsing keeps valid announcements and drops broken or unsafe parts", () => {
  const items = parseAnnouncements({
    results: [
      payload(),
      payload({ id: "not-a-uuid" }),
      payload({ id: ID_B, action: { type: "external", label: "x", web_path: "//evil.example", external_url: "https://evil.example" } }),
    ],
  });
  assert.equal(items.length, 2);
  assert.equal(items[1].action.web_path, null);
  assert.equal(items[1].action.external_url, null);
  assert.deepEqual(parseAnnouncements(null), []);
  assert.deepEqual(parseAnnouncementFeed({ next_cursor: "abc", results: [] }), { next_cursor: "abc", results: [] });
});

test("the card skips announcements that were read or closed", () => {
  const first = item();
  const second = item({ id: ID_B });
  let state = emptyState();
  assert.equal(cardAnnouncement([first, second], state)?.id, ID_A);
  state = markDismissed(state, ID_A, NOW);
  assert.equal(cardAnnouncement([first, second], state)?.id, ID_B);
  state = markRead(state, ID_B, NOW);
  assert.equal(cardAnnouncement([first, second], state), null);
});

test("the bubble follows the admin's frequency and impression limit", () => {
  const daily = item();
  let state = emptyState();
  const noSession = new Set<string>();
  assert.deepEqual(bubbleAnnouncements([daily], state, NOW, noSession).map((entry) => entry.id), [ID_A]);

  state = recordBubbleShown(state, [daily], NOW, noSession);
  assert.equal(state.bubble[ID_A].shown, 1);
  // Shown today: hidden on the next visit, but kept while this tab is open.
  assert.deepEqual(bubbleAnnouncements([daily], state, NOW + 1_000, noSession), []);
  assert.equal(bubbleAnnouncements([daily], state, NOW + 1_000, new Set([ID_A])).length, 1);
  assert.equal(bubbleAnnouncements([daily], state, NOW + DAY, noSession).length, 1);

  state = recordBubbleShown(state, [daily], NOW + DAY, noSession);
  state = recordBubbleShown(state, [daily], NOW + 2 * DAY, noSession);
  assert.equal(state.bubble[ID_A].shown, 3);
  assert.deepEqual(bubbleAnnouncements([daily], state, NOW + 10 * DAY, noSession), []);

  const weekly = item({ id: ID_B, bubble: { icon: "sparkle", frequency: "weekly", max_impressions: 5 } });
  const seen = recordBubbleShown(emptyState(), [weekly], NOW, noSession);
  assert.deepEqual(bubbleAnnouncements([weekly], seen, NOW + 6 * DAY, noSession), []);
  assert.equal(bubbleAnnouncements([weekly], seen, NOW + 7 * DAY, noSession).length, 1);
});

test("fundraising and read announcements never ride the bubble", () => {
  const fundraising = item({ kind: "fundraising" });
  assert.deepEqual(bubbleAnnouncements([fundraising], emptyState(), NOW, new Set()), []);
  const read = markRead(emptyState(), ID_A, NOW);
  assert.deepEqual(bubbleAnnouncements([item()], read, NOW, new Set()), []);
});

test("the step window opens by itself at most once a week", () => {
  const explainer = item({
    priority: "high",
    surfaces: { bubble: false, home_card: true, modal: true },
    steps: [{ title: "Откройте", text: "", image_url: null, width: null, height: null }],
  });
  assert.equal(modalAnnouncement([explainer], emptyState(), NOW)?.id, ID_A);
  const recent = { ...emptyState(), lastModalAt: new Date(NOW - DAY).toISOString() };
  assert.equal(modalAnnouncement([explainer], recent, NOW), null);
  assert.equal(modalAnnouncement([item()], emptyState(), NOW), null);
});

test("audience, receipts and impressions", () => {
  const guests = item({ audience: { auth: "guests" } });
  const members = item({ id: ID_B, audience: { auth: "signed_in" } });
  assert.deepEqual(forAudience([guests, members], false).map((entry) => entry.id), [ID_A]);
  assert.deepEqual(forAudience([guests, members], true).map((entry) => entry.id), [ID_B]);

  const local = markRead(emptyState(), ID_A, NOW);
  const merged = mergeReceipts(local, {
    results: [
      { announcement_id: ID_A, read_at: "2020-01-01T00:00:00Z", dismissed_at: null },
      { announcement_id: ID_B, read_at: null, dismissed_at: "2026-10-20T00:00:00Z" },
    ],
  });
  assert.equal(merged.read[ID_A], local.read[ID_A]);
  assert.equal(merged.dismissed[ID_B], "2026-10-20T00:00:00Z");

  const first = takeImpression(emptyState(), ID_A, "card", NOW);
  assert.equal(first.fresh, true);
  assert.equal(takeImpression(first.state, ID_A, "card", NOW + 1_000).fresh, false);
  assert.equal(takeImpression(first.state, ID_A, "card", NOW + DAY).fresh, true);
});

test("stored state survives garbage", () => {
  assert.deepEqual(parseState("not json"), emptyState());
  const stored = parseState(JSON.stringify({ read: { [ID_A]: "x", junk: "y" }, bubble: { [ID_A]: { shown: 2, last: "z" } } }));
  assert.deepEqual(Object.keys(stored.read), [ID_A]);
  assert.equal(stored.bubble[ID_A].shown, 2);
});

test("the body supports paragraphs, lists and bold only", () => {
  assert.deepEqual(bodyBlocks("Первый абзац\nвторая строка\n\n- один\n- два"), [
    { type: "paragraph", lines: ["Первый абзац", "вторая строка"] },
    { type: "list", lines: ["один", "два"] },
  ]);
  assert.deepEqual(boldSegments("Нажмите **Кибла** внизу"), [
    { text: "Нажмите ", bold: false },
    { text: "Кибла", bold: true },
    { text: " внизу", bold: false },
  ]);
});

test("a mark hides the announcement only in its own wave", () => {
  const first = item();
  let state = markDismissed(emptyState(), ID_A, NOW, 1);
  assert.equal(isFinished(first, state), true);
  assert.equal(cardAnnouncement([first], state), null);

  // «Показать снова»: the same announcement in wave 2 is back on the home screen.
  const again = item({ wave: 2 });
  assert.equal(isFinished(again, state), false);
  assert.equal(cardAnnouncement([again], state)?.id, ID_A);
  state = markDismissed(state, ID_A, NOW + DAY, 2);
  assert.equal(isFinished(again, state), true);
  assert.equal(state.dismissed[ID_A], new Date(NOW).toISOString());

  // Marks saved before waves existed count as wave 1; the feed's "read" stays.
  const legacy = parseState(JSON.stringify({ read: { [ID_A]: "2026-10-21T10:00:00Z" } }));
  assert.equal(isFinished(first, legacy), true);
  assert.equal(isFinished(again, legacy), false);
  assert.equal(markRead(legacy, ID_A, NOW, 2).read[ID_A], "2026-10-21T10:00:00Z");
});

test("the bubble's frequency and limit start over in each wave", () => {
  const first = item();
  const noSession = new Set<string>();
  let state = emptyState();
  for (let day = 0; day < 3; day += 1) state = recordBubbleShown(state, [first], NOW + day * DAY, noSession);
  assert.deepEqual(bubbleAnnouncements([first], state, NOW + 10 * DAY, noSession), []);

  const again = item({ wave: 2 });
  assert.equal(bubbleAnnouncements([again], state, NOW + 10 * DAY, noSession).length, 1);
  state = recordBubbleShown(state, [again], NOW + 10 * DAY, noSession);
  assert.deepEqual(state.bubble[ID_A], { shown: 1, last: new Date(NOW + 10 * DAY).toISOString(), wave: 2 });
});

test("receipts and impressions carry the wave", () => {
  const merged = mergeReceipts(emptyState(), {
    results: [{ announcement_id: ID_A, read_at: null, dismissed_at: "2026-10-20T00:00:00Z", wave: 3 }],
  });
  assert.equal(isFinished(item({ wave: 3 }), merged), true);
  assert.equal(isFinished(item({ wave: 4 }), merged), false);

  const first = takeImpression(emptyState(), ID_A, "card", NOW, 1);
  assert.equal(takeImpression(first.state, ID_A, "card", NOW, 2).fresh, true);
  assert.equal(parseAnnouncements({ results: [payload()] })[0].wave, 1);
});

