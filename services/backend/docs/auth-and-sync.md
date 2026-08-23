# Guest authentication and reading sync

## Guest bootstrap

Before the first request, the client generates and persists two independent values:

- `installation_id`: UUIDv4 used only as a stable installation identifier;
- `installation_credential`: at least 32 cryptographically random bytes encoded as
  unpadded base64url (normally 43 characters).

The credential must be generated with the operating system CSPRNG and stored before the
request. Flutter stores it in Keychain/Keystore. It must never be logged, included in
analytics, or reused between installations. A browser client should call this API through
the same-origin Next.js BFF and must not put credentials in `localStorage`.

Verified email login, the browser HttpOnly-cookie boundary and transactional guest merge are
specified separately in [email-auth-and-guest-merge.md](email-auth-and-guest-merge.md).

```http
POST /api/v1/auth/guest
Content-Type: application/json

{
  "installation_id": "64a3883a-680e-44c7-b2ee-6ee0da8efad8",
  "installation_credential": "<base64url-encoded-32-random-bytes>",
  "platform": "android",
  "locale": "ru",
  "app_version": "1.0.0"
}
```

The server stores only keyed digests of both installation values. Repeating the request
with the same pair returns the same guest/device identity and a fresh token family. The
same UUID with a different credential is rejected without revealing whether it exists.
Every successful response also contains the device's monotonically increasing
`bootstrap_generation`. A client MUST single-flight bootstrap calls per installation and
MUST persist a response only when its generation is greater than the generation already
stored locally. This prevents a delayed response from replacing a newer token family with
credentials that the server has already revoked. The generation and token update must be
one atomic secure-storage transaction.

Access tokens live for 15 minutes by default. Refresh tokens live for at most 30 days,
are bound to one device/session family, and rotate on every use. Replaying an already-used
refresh token revokes the whole family. This strict policy intentionally treats concurrent
refresh of the same token as compromise; clients must serialize refresh calls.

```http
POST /api/v1/auth/token/refresh
POST /api/v1/auth/logout
POST /api/v1/auth/logout-all
Authorization: Bearer <access-token>
```

Production requires independent stable secrets for installation IDs, guest credentials,
and refresh-token digests. Authentication endpoints use two Redis-backed limits: the
primary quota is keyed by an HMAC installation proof or a cryptographically verified
refresh-token family, while a deliberately high per-IP burst limit is only an emergency
circuit breaker. This prevents unrelated users behind the same carrier CGNAT from sharing
the normal quota. The ingress/WAF must still enforce a separately tuned, risk-aware edge
limit; `DJANGO_NUM_PROXIES` must match the trusted proxy topology exactly. The application
origin must not be publicly reachable. The trusted ingress must replace, not blindly append
to, client-supplied `Forwarded`, `X-Forwarded-For`, and `X-Forwarded-Proto` headers before
proxying a request.

Expired or revoked refresh-token families are retained for 90 days by default so replay
and incident evidence remains available, then removed in bounded batches by the
`accounts.prune_auth_sessions` Celery task. One invocation drains at most
`QURAN_RETENTION_TASK_MAX_BATCHES` batches and stops early if it cannot make progress, so
maintenance remains bounded without leaving a permanent backlog after a traffic spike.
Used tokens in an otherwise active family are never pruned early because they are required
for replay detection.

## Device inventory and account deletion

Registered users can inspect and revoke installation-bound sessions without exposing
installation digests or refresh-token identifiers:

```text
GET    /api/v1/me/devices
DELETE /api/v1/me/devices/{device_id}
POST   /api/v1/me/deletion-request
POST   /api/v1/me/deletion-cancel
```

The device list is scoped to the authenticated user and returns platform, locale, app version,
creation/last-seen timestamps, active-family count and an `is_current` marker. Revoking another
device atomically marks the installation revoked and invalidates all of its refresh families.
The current installation cannot be revoked through the device endpoint; the client must use the
normal `logout` action so the local HttpOnly credential is cleared as part of the same flow.

Deletion request and cancellation both require a newly consumed email challenge for the same
user, device and verified primary email. The proof is valid for 10 minutes by default
(`QURAN_ACCOUNT_REAUTH_MAX_AGE_SECONDS`). A cancellation proof must have been issued after the
deletion request, so the earlier code cannot be reused.

A deletion request starts a configurable seven-day grace period
(`QURAN_ACCOUNT_DELETION_GRACE_DAYS`) and moves the account to `pending_deletion`. Ordinary Quran,
sync, prayer, reminder and feedback APIs then reject its access tokens. Token refresh, `/me`,
logout and the email challenge flow remain available only to support recovery. After a fresh
email verification, `deletion-cancel` returns the account to `active` before the deadline.

Celery Beat runs `accounts.finalize_due_deletions` hourly. Each invocation processes at most
`QURAN_ACCOUNT_DELETION_BATCH_SIZE` accounts. Finalization removes devices, credentials,
consents, reading state, bookmarks, sync history, prayer profile and reminder rules; it scrubs
email identities and leaves an inactive anonymized user shell for immutable merge/editorial audit
references. Feedback retained under its separate category policy loses contact email and direct
message/actor links; its reporter points only to that anonymized shell while immutable message
and audit evidence is preserved. The task is idempotent and never touches accounts before their
grace deadline.

## Reading position and bookmarks

All personal endpoints require authentication and return `Cache-Control: private,
no-store`.

```text
GET/PUT     /api/v1/me/reading-position/{edition}
GET/POST    /api/v1/me/bookmarks
GET/PATCH/DELETE /api/v1/me/bookmarks/{id}
POST        /api/v1/sync/push
GET         /api/v1/sync/pull?cursor=0&limit=100
```

Bookmark IDs are mandatory client-generated UUIDv7 values, so retrying creation cannot create
a second logical bookmark. Unseen stale identifiers are rejected after the documented offline
window; the client then atomically remaps the local bookmark to a fresh UUIDv7. Physically
pruned tombstones leave a compact retired-ID marker, so later configuration changes cannot make
an old identifier reusable. The list uses cursor pagination (`next`, `previous`, `results`) and
supports `include_deleted=true` for tombstones.

Every mutation carries `base_revision` and `client_updated_at`. Server revisions and the
per-user monotonically increasing sync cursor are authoritative. A stale revision returns
a deterministic conflict instead of overwriting newer state. Bearer-authenticated calls
are always bound to the device encoded in the access token.

`POST /api/v1/sync/push` accepts up to 100 operations. The v1 entity union contains reading
positions, bookmarks, and reminder rules; the prayer profile remains a separate singleton API.
Each operation has a UUID `operation_id`; replaying the same normalized request returns the
stored result, while reusing the ID for different data returns `sync_operation_reuse`. Pull
responses are bounded and contain accepted snapshots, including bookmark and reminder
tombstones. Direct reminder mutations append to this same change log atomically, so direct CRUD
and offline sync cannot diverge.

Celery Beat runs bounded auth and sync retention tasks hourly; production must run exactly
one Beat scheduler. Sync changes are retained for 180 days by default. When an older cursor
has been pruned, `/sync/pull` returns `410 sync_cursor_expired` instead of silently
skipping data. The client starts `full_resync=true`; subsequent pages use short-lived,
user-bound signed continuation tokens. Full resync visits reading positions, bookmarks, then
reminders, and includes active reminder rules and tombstones. It must complete that full-resync
protocol before treating absence as authoritative or resuming incremental pull from the returned
snapshot cursor.

The push response cursor is informational and must never replace the client's persisted pull
cursor: that would skip concurrent changes from another device. After push, the client pulls from
its previously persisted cursor until `has_more=false`. A pending outbox survives cursor expiry;
the client builds full resync in temporary state, reconciles only after the final page, then
rebases pending operations and resumes incremental pull. Reminder tombstones are physically
pruned only after their retained sync changes and operation-replay records are gone, and their
identity is recorded in the compact retired-ID ledger first.

## Browser origins

`DJANGO_CORS_ALLOWED_ORIGINS` is an exact comma-separated allowlist for `/api/**` only.
Wildcard origins and cross-origin cookies are disabled. Add the deployed Next.js and
Telegram Mini App origins explicitly. Admin routes never receive CORS headers.
