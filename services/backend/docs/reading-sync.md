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
reading positions and bookmarks, including tombstones, plus `snapshot_cursor`. Continue with the
signed `next_page_token` until `has_more=false`. Tokens are bound to the authenticated user and
expire by default after 24 hours.

The client must treat the collected snapshot as an authoritative replacement, not as a merge:
after all pages arrive, any local synchronized entity absent from the snapshot must be removed.
It then sets its incremental cursor to `snapshot_cursor` and immediately calls incremental pull.
Mutations committed after the snapshot cursor are replayed. Clients must apply entity revisions
monotonically; this also makes duplicate state observed during a paginated resync harmless.

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
