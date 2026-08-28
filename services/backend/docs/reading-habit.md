# Reading habit and after-prayer plan

The reading-habit API stores a revisioned daily goal, completed reading sessions, daily
progress, and a reading-day streak. It also supports an optional page plan after the five
obligatory prayers.

## Endpoints

- `GET /api/v1/me/today`
- `GET /api/v1/me/reading-planner?days=7|30|90&timezone_name=...`
- `GET|PUT|DELETE /api/v1/me/reading-goal`
- `GET /api/v1/me/reading-sessions?source=manual|automatic`
- `POST /api/v1/me/reading-sessions/automatic`
- `POST /api/v1/me/reading-sessions/manual`
- `PATCH|DELETE /api/v1/me/reading-sessions/{id}`
- `GET|PUT /api/v1/me/prayer-reading-plan`
- `POST /api/v1/me/prayer-reading-check-ins`
- `PATCH|DELETE /api/v1/me/prayer-reading-check-ins/{id}`

Writes use client-generated UUIDv7 identifiers and revision checks. A prayer check-in is
unique for `(user, local_date, prayer)`, so retries and repeated clicks cannot credit the same
slot twice. The create request may include the actual number of pages read; without it, the
plan target is used for backward compatibility. A check-in may then be patched from 1 to 604
pages, so partial reading and extra reading are both recorded honestly. Each check-in creates a
manual page reading session, which also contributes to an active page-based daily goal. Updating
or deleting a check-in recalculates daily progress and the streak.

The plan allows 1–20 pages per prayer. Forecasts use the published 604-page Madani Mushaf:
`ceil(604 / (pages_per_prayer * 5))`. The forecast is guidance, not a deadline. For example,
two pages after each prayer is ten pages per day and approximately 61 days for 604 pages.

Any completed reading session keeps the reading-day streak, even when the daily target was not
fully reached. Goal completion remains a separate signal. Unread pages are not carried into the
next day automatically, and an after-prayer check-in never marks a later prayer slot.

The planner endpoint returns an oldest-to-newest calendar window of 7–90 local dates. Each day
has one of `no_goal`, `pending`, `missed`, `partial`, or `completed`, plus the goal snapshot and
actual prayer check-ins for that date. `has_reading` remains true for factual reading activity
even when no daily goal was active. Automatic heartbeat sessions are aggregated per day, so the
90-day response remains bounded. Historical prayer targets are intentionally not inferred:
the current plan can change and is not versioned by date, so the API reports only factual prayer
pages and check-in counts. Responses are private and `no-store`.

The web planner groups automatic heartbeat sessions into a compact daily summary and keeps every
standalone manual entry individually editable or deletable. Sessions owned by an after-prayer
check-in are changed only through that check-in and are immutable through the generic session
endpoint. Manual entries may be edited for seven days,
matching the API's correction window; deletion remains available later. A missed day stays as a
historical fact and never creates debt or silently increases a future target.

When a prayer Web Push reminder belongs to a user with an active after-prayer plan, the
localized notification includes the selected page count and opens a guided reading session for
that prayer and local date.

The guided reader records full active minutes through automatic reading sessions with zero
credited pages. Its prayer check-in records the actual pages separately. Consequently, a
time-based daily goal receives only measured active time, while a page-based daily goal receives
only the check-in pages; the same guided reading is never credited twice to either metric. The
timer pauses when the tab is hidden, the window loses focus, or the reader is idle, and stops
after the check-in is saved.

Coordinates are not stored by this feature. The plan stores only the page count, IANA time
zone, revision metadata, device reference, and daily prayer check-ins. Account deletion removes
plans and check-ins; guest-to-account merge preserves them.
