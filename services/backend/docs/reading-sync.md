# Reading state and offline synchronization

## Mutation contract

`POST /api/v1/me/bookmarks` requires a client-generated UUIDv7. Repeating the request with the
same UUID and the same normalized state returns `200` with the existing revision and does not
append a sync change, even when the ID is old. Reusing the UUID for different state returns
`409 bookmark_create_conflict`. The first successful creation returns `201`.

For an ID not already present on the server, the UUIDv7 timestamp may be at most 360 days old
and at most 24 hours in the future by default. This age gate prevents an identifier whose old
tombstone was physically pruned from being resurrected at revision 1. A client receiving
`409 bookmark_id_not_reusable`, or sync conflict `entity_id_not_reusable`, must generate a new
UUIDv7, remap that still-local unsynchronized bookmark atomically, and retry with a new
`operation_id`.

Sync batches use `operation_id` for replay protection. A byte-equivalent normalized operation is
replayed without another mutation; reusing the ID with different data returns
`409 sync_operation_reuse`. Entity mutations use server revisions. A stale `base_revision` is
reported as a per-operation conflict, so an old offline device cannot overwrite newer state.
Expected quota/revision outcomes are persisted and returned per operation. The outer batch is
also one database transaction: a fatal domain/validation error in any operation rolls back all
earlier operations in that HTTP request, so the client never receives an opaque error after a
hidden partial commit.

The v1 sync entity union contains `reading_position`, `bookmark`, and `reminder`. Reminder rules
use the same `POST /api/v1/sync/push` envelope and the same per-user monotonic cursor as reading
state. The prayer profile remains a separate singleton resource at
`GET/PUT /api/v1/me/prayer-profile`; it is not a sync entity.

Migration `reading.0005` appends one baseline change for each reminder that predates unified
sync, so an existing incremental cursor converges without a lucky later edit. Deploy it with
writer replicas drained (the normal migrate-before-start sequence): old reminder PATCH/DELETE
code does not dual-write the sync log. The migration locks each existing user and sync cursor,
is idempotent for identities already present in the change log, and invalidates old v1
full-resync page tokens by moving to the versioned three-phase token namespace.
If an in-flight old token returns `full_resync_token_invalid`, the client discards only its
temporary incomplete snapshot and restarts full resync from the first page; its persisted state
and outbox remain untouched.

### Reminder sync operations

A reminder create uses `entity_type=reminder`, `action=upsert`, a client-generated UUIDv7 in
`entity_id`, and `base_revision=0`. Its `payload` is the complete functional reminder state:

```json
{
  "operation_id": "019fe63b-2f58-766f-8a11-b913bb2d80c0",
  "entity_type": "reminder",
  "entity_id": "019fe63b-2f58-766f-8a11-b913bb2d80c1",
  "action": "upsert",
  "base_revision": 0,
  "client_updated_at": "2026-08-09T12:00:00Z",
  "payload": {
    "reminder_type": "prayer",
    "schedule": {
      "kind": "prayer",
      "prayer_event": "fajr",
      "prayer_offset_minutes": -10
    },
    "weekdays_mask": 127,
    "timezone": {"mode": "device_local"},
    "signal": "sound",
    "is_enabled": true
  }
}
```

An update also uses `action=upsert`, requires `base_revision>=1`, and accepts a partial
functional payload. Nested `schedule`, `timezone`, and `review_target` values are strict unions
and are replaced as whole values when present. An empty update payload is a no-op. A delete uses
`action=delete`, requires `base_revision>=1`, and requires an omitted or empty payload. Reminder
payloads never contain `id`, revision metadata, device identity, coordinates, occurrence times,
push tokens, or sound file URLs.

The authenticated access-token device is authoritative. Reminder operations reject a client
`device_id` even in the outer sync envelope; the server binds the device only from the access
token. Unknown reminder payload fields are rejected at every nesting level. The create defaults
are identical to the direct reminder API: all weekdays, device-local timezone, short system
sound, and enabled state.

Real reminder creates and updates append an `upsert` change; deletion appends a `delete` change
whose entity is the minimized tombstone. Direct `POST/PATCH/DELETE /api/v1/me/reminders`
mutations append the same changes atomically, so a mutation through the direct API is visible to
every device through incremental pull. Exact create retries, state-equivalent update no-ops, and
repeated tombstone deletes do not increment the entity revision or sync cursor.

On deletion, older retained changes for that reminder are privacy-collapsed to the same minimized
tombstone. A client that never observed the active rule therefore receives only deletion state,
not obsolete wall-clock, timezone, ayah-range, or device data. Reminder `SyncOperation` rows store
the deterministic outcome/cursor but do not duplicate the functional snapshot; exact replay
rehydrates the current user-owned rule or tombstone.

Reminder concurrency outcomes use the existing per-operation response envelope. Supported
conflict reasons are `revision_mismatch`, `entity_missing`, `entity_id_unavailable`,
`entity_id_not_reusable`, and `reminder_quota_exceeded`. A retained current entity is included
when it is safe and useful; cross-user UUID collisions never expose another user's state.
Tombstones and retired IDs cannot be resurrected. Malformed payloads and invalid timezone/ayah
domain values are request errors and roll back the whole batch rather than becoming stored
per-operation conflicts.

Replay hashing happens after parsing, default application, strict payload normalization, and
authenticated-device binding. JSON object key order, equivalent date/time representations, and
an omitted versus empty delete payload therefore do not create different operations. An exact
replay returns the stored accepted/conflict outcome and original cursor with `replayed=true`; its
reminder entity is rehydrated from the current row so deleted scheduling data is never retained
solely for replay. It does not mutate state or append a change. A different normalized request
under the same `operation_id` returns `409 sync_operation_reuse`. Conflict resolution always uses
a new `operation_id`.

`intra_page_anchor` is intentionally small and typed. It accepts only `x_ratio` and `y_ratio`
(finite numbers from 0 through 1) and `line_number` (1 through 30). Unknown keys are rejected;
clients must omit an unavailable coordinate instead of placing arbitrary renderer state in sync
history.

Reading-state writes use an atomic fixed-window limit keyed by authenticated user and device.
Direct position/bookmark writes default to `120/minute`; sync push defaults to 300 operations
per minute plus a 5,000-operation daily budget shared by all of the user's devices. A sync
request is charged by `operations.length`, not as one request.
Exhaustion returns `429 reading_rate_limited` with `Retry-After`. A user may retain at most 5,000
bookmarks by default, including deletion tombstones; a new direct or sync creation beyond the cap
returns `409 bookmark_quota_exceeded`.

## Incremental pull and cursor expiry

`GET /api/v1/sync/pull?cursor=...&limit=...` reads the per-user monotonic change log. A retained
cursor returns `mode=incremental`, ordered changes, `next_cursor`, and `has_more`.

Retention advances `UserSyncCursor.minimum_valid_cursor` in the same transaction that removes a
contiguous prefix of changes. Therefore a client is never allowed to unknowingly read across a
gap. A cursor below this floor returns `410 application/problem+json` with:

- `code: sync_cursor_expired`;
- `full_resync_required: true`;
- `minimum_valid_cursor` and `current_cursor`.

## Full resync

Start with `GET /api/v1/sync/pull?full_resync=true&limit=...`. The response contains current
reading positions, bookmarks, and reminder rules, including tombstones, plus `snapshot_cursor`.
The stable phase order is reading positions, bookmarks, then reminders; entities inside each
phase are ordered by ID. Continue with the signed `next_page_token` until `has_more=false`.
Tokens bind the authenticated user, snapshot cursor, phase, and last ID, and expire by default
after 24 hours.

The client must treat the collected snapshot as an authoritative replacement, not as a merge,
but only after all pages have arrived. It should build the snapshot in temporary state; after the
final page, any local synchronized entity absent from the snapshot is removed and any absent or
deleted reminder has its operating-system notification cancelled. The client then sets its
incremental cursor to `snapshot_cursor` and immediately calls incremental pull. Mutations
committed after the snapshot cursor are replayed. Clients must apply entity revisions
monotonically; this also makes duplicate state observed during a paginated resync harmless.

Pending local outbox operations are not discarded during a full resync. They are rebased onto
the completed authoritative snapshot and submitted afterward with new operation IDs where the
base revision changed.

## Client outbox and cursor rules

Persist the local desired state and its outbox operation atomically, retain `operation_id` until
a terminal result is received, and keep at most one unresolved operation per entity. Multiple
offline edits should be squashed into one desired update against the last known server revision;
delete wins over pending edits.

Process push results in input order. On `revision_mismatch`, first accept the returned server
snapshot, reapply still-relevant local intent, and submit a new operation with the returned
revision and a new `operation_id`. An unsynchronized create that receives
`entity_id_not_reusable` or `entity_id_unavailable` must atomically remap itself to a fresh
UUIDv7. A tombstone immediately cancels the corresponding scheduled local notification.

The cursor returned by push is informational. A client must **not** assign either a result cursor
or the outer push cursor to its persisted pull cursor: doing so can skip changes written by a
different device. After every push, pull from the previously persisted cursor until
`has_more=false`, apply changes in cursor order and revisions monotonically, and only then persist
each returned `next_cursor`. On `410 sync_cursor_expired`, preserve the outbox, complete a full
resync in temporary state, reconcile authoritatively, rebase the outbox, and resume incremental
pull.

## Bounded retention

`prune_sync_history()` is safe to call from a management process or Celery. Each run deletes only a
bounded, contiguous batch and reports `has_more`. Available entry points:

```text
python manage.py prune_reading_sync_history --dry-run
python manage.py prune_reading_sync_history
Celery task: reading.prune_sync_history
```

Optional Django settings and defaults:

| Setting | Default |
|---|---:|
| `QURAN_SYNC_CHANGE_RETENTION_DAYS` | 180 |
| `QURAN_SYNC_OPERATION_RETENTION_DAYS` | 180 |
| `QURAN_SYNC_PRUNE_BATCH_SIZE` | 5000 |
| `QURAN_SYNC_PRUNE_USER_BATCH_SIZE` | 1000 |
| `QURAN_BOOKMARK_TOMBSTONE_RETENTION_DAYS` | 365 |
| `QURAN_BOOKMARK_NEW_ID_MAX_AGE_DAYS` | 360 |
| `QURAN_BOOKMARK_ID_FUTURE_SKEW_SECONDS` | 86400 |
| `QURAN_SYNC_FULL_RESYNC_TOKEN_MAX_AGE_SECONDS` | 86400 |
| `QURAN_RETENTION_TASK_MAX_BATCHES` | 10 |
| `QURAN_BOOKMARK_MAX_PER_USER` | 5000 |
| `QURAN_RETIRED_BOOKMARK_ID_MAX_PER_USER` | 50000 |
| `QURAN_READING_MUTATION_RATE` | `120/minute` |
| `QURAN_SYNC_PUSH_RATE` | `300/minute` |
| `QURAN_SYNC_PUSH_DAILY_RATE` | `5000/day` |

Schedule the task at least daily. One Celery invocation drains up to
`QURAN_RETENTION_TASK_MAX_BATCHES` bounded batches and stops early when there is no progress. User
selection rotates by the cursor's last update time so one large account cannot monopolize every
run. An old record can remain temporarily when a newer record precedes it, because pruning must
never create a cursor gap.

An expired bookmark tombstone is deleted only after neither a retained `SyncChange` nor a
retained `SyncOperation` for that bookmark exists. Before deletion, the same transaction writes
its user/id/final-revision to a compact permanent `RetiredBookmarkId` ledger. The ledger is the
authoritative protection against revision-1 resurrection even when retention settings change;
the UUIDv7 age window is an additional stale-offline guard. Its per-user cap defaults to 50,000.
When that cap is reached, pruning leaves later tombstones in place, so the 5,000 bookmark quota
still bounds storage and no identity evidence is discarded. Tombstone retention must also be
longer than the configured unseen-ID age window plus accepted future clock skew; unsafe settings
fail the Django system check and reject unseen identifiers.

Reminder tombstones use the same history interlock: physical pruning is allowed only after no
retained `SyncChange` or `SyncOperation` references that user/reminder identity. The pruning
transaction first records the UUID and final revision in `RetiredReminderId`; this preserves
non-resurrection after the full reminder row is gone. Exact operation replay remains available
only for the configured `SyncOperation` retention window; physical tombstone pruning waits for
that window to end. An authoritative full resync then communicates an old deletion by absence,
while a retained incremental delete always carries its minimized tombstone snapshot.
