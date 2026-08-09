# Feedback MVP

The `feedback` Django app owns support tickets independently from Quran publication,
audio, ads, accounts, and reading sync. It accepts authenticated guest users as well as
registered users. A ticket can describe published content, but no feedback endpoint or
admin action can modify that content.

## Client API

All endpoints require the normal bearer access token (or an authenticated Django admin
session), are isolated by reporter, and return `Cache-Control: private, no-store`.

```text
GET/POST  /api/v1/feedback/tickets
GET       /api/v1/feedback/tickets/{public_id}
POST      /api/v1/feedback/tickets/{public_id}/messages
POST      /api/v1/feedback/tickets/{public_id}/close
POST      /api/v1/feedback/tickets/{public_id}/reopen
```

Ticket lists use cursor pagination (`next`, `previous`, `results`) with 25 records by
default and 100 at most. `status` is an optional exact filter. Looking up another user's
opaque public ID returns the same `404 feedback_ticket_not_found` response as a missing
ticket.

The client generates and persists a new UUIDv4/UUIDv7 `client_request_id` before creating
a ticket, and a `client_message_id` before every public message. Repeating exactly the
same request is safe and returns HTTP 200; reuse with different content returns HTTP 409.
This matters for Flutter background retries and Telegram/Web connection changes.

```json
{
  "client_request_id": "019c2d86-d43a-7169-a753-c173285990bd",
  "client_message_id": "019c2d86-d43a-7169-a753-c173285990be",
  "category": "religious_content",
  "subject": "Possible ayah page mismatch",
  "message": "Please verify the highlighted ayah on this page.",
  "locale": "en",
  "contact_email": "reporter@example.com",
  "context": {
    "edition_code": "madani-hafs",
    "content_version": "1.0.0",
    "surah_number": 1,
    "ayah_number": 1,
    "page_number": 1,
    "reciter_id": "alafasy",
    "recitation_id": "hafs-complete",
    "audio_track_id": "001-001",
    "playback_ms": 1234,
    "ad_campaign_id": "campaign-42",
    "ad_creative_id": "creative-7",
    "route": "/quran/madani-hafs/pages/1",
    "app_version": "1.0.0",
    "app_build": "100",
    "client_platform": "android",
    "os_version": "Android 16"
  }
}
```

The authoritative channel is taken from the authenticated device token; a Django session
is treated as web. Quran coordinates require `edition_code` and `content_version`, an ayah
requires a surah, and playback position requires a track or recitation ID. Route context
is a relative path without a query string or fragment so access tokens and personal query
parameters are not accidentally collected. Context is an immutable report of what the
client saw; it is not a foreign-key mutation request.

## Workflow and SLA

Religious-content reports are routed to `religious_editorial` with high priority and a
24-hour first-response deadline. Page/region and audio reports go to `content_quality`
with the same accelerated deadline. Technical and sync reports have a 24-hour response
deadline at normal priority. An operator can mark a confirmed canonical-content problem
critical; that recalculates the deadline to four hours.

Operator states follow the controlled graph:

```text
new -> triaged -> in_progress -> waiting_for_user -> resolved -> closed
          \             \             \-> resolved
           \-> rejected / duplicate / closed
```

The admin validates transitions and requires a reason for status, priority, team, or
assignee changes. Public and internal operator messages are separate; internal notes are
never included in client responses. Existing messages, reported context, and audit events
cannot be edited or deleted through model instances or the admin. Audit events store
metadata and IDs, not duplicate message bodies.

Reporter close is idempotent. A resolved or closed ticket can be explicitly reopened; an
incoming public reporter message also reopens it atomically. A retried reopen does not
increment the counter twice. Rejected and duplicate tickets remain terminal to the client
and need operator review.

## Input and privacy controls

- Subject: one plain-text line, 160 characters maximum.
- Message: plain text only, 4,000 characters maximum; HTML and unsafe control characters
  are rejected. Clients must continue to render it as text, never as HTML/Markdown.
- Transition reason: plain text, 500 characters maximum.
- At most 20 active tickets per user and 100 total messages per ticket by default.
- Mutating endpoints have a Redis-backed per-user `feedback_write` rate (20/hour by
  default). Keep a separately tuned ingress/WAF abuse limit in production.
- Public IDs use 144 random bits and are not sequential, but authorization never relies
  on secrecy of the ID.
- Contact email is optional and visible only to the reporter and authorized staff.

The limits are configurable with `QURAN_FEEDBACK_WRITE_RATE`,
`QURAN_FEEDBACK_MAX_OPEN_TICKETS_PER_USER`, and
`QURAN_FEEDBACK_MAX_MESSAGES_PER_TICKET`.

## Attachments and notifications

File uploads are deliberately not exposed in this MVP. There is no local-media upload
fallback and no attachment endpoint in OpenAPI. A later phase must add direct pre-signed
object-storage upload, quarantine, MIME/signature checks, size limits, malware scanning,
retention, and explicit completion before an attachment can be linked to a ticket.

Outbound email/push notifications and editorial change-request linking are also follow-up
work. The current backend records `first_response_at` and the immutable source ticket so
those integrations can be added without changing the client contract.
