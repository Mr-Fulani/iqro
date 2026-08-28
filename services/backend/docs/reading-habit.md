# Reading habit and after-prayer plan

The reading-habit API stores a revisioned daily goal, completed reading sessions, daily
progress, and a completed-day streak. It also supports an optional page plan after the five
obligatory prayers.

## Endpoints

- `GET /api/v1/me/today`
- `GET|PUT|DELETE /api/v1/me/reading-goal`
- `GET /api/v1/me/reading-sessions`
- `POST /api/v1/me/reading-sessions/automatic`
- `POST /api/v1/me/reading-sessions/manual`
- `PATCH|DELETE /api/v1/me/reading-sessions/{id}`
- `GET|PUT /api/v1/me/prayer-reading-plan`
- `POST /api/v1/me/prayer-reading-check-ins`
- `DELETE /api/v1/me/prayer-reading-check-ins/{id}`

Writes use client-generated UUIDv7 identifiers and revision checks. A prayer check-in is
unique for `(user, local_date, prayer)`, so retries and repeated clicks cannot credit the same
slot twice. Each check-in creates a manual page reading session, which also contributes to an
active page-based daily goal. Deleting a check-in discards that session and recalculates daily
progress and the streak.

The plan allows 1–20 pages per prayer. Forecasts use the published 604-page Madani Mushaf:
`ceil(604 / (pages_per_prayer * 5))`. The forecast is guidance, not a deadline. For example,
two pages after each prayer is ten pages per day and approximately 61 days for 604 pages.

When a prayer Web Push reminder belongs to a user with an active after-prayer plan, the
localized notification includes the selected page count and opens the plan on the home page.

Coordinates are not stored by this feature. The plan stores only the page count, IANA time
zone, revision metadata, device reference, and daily prayer check-ins. Account deletion removes
plans and check-ins; guest-to-account merge preserves them.
