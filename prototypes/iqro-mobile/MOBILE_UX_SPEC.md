# IQRO mobile UX specification

## 1. Product frame

IQRO mobile is a calm daily practice companion around the Quran. The product is organized around one primary loop: open the app, see the next meaningful action, complete a small reading or listening session, and understand the day's progress without navigating a content portal.

The prototype is local and interactive. It validates information architecture, state transitions, responsive behavior, Arabic RTL, dark theme, and the fit with the existing backend. It does not introduce production APIs, real authentication, notifications, downloads, or analytics.

### Principles

1. The Home screen answers “what should I do next?” before showing a catalog.
2. Reading, listening, the daily plan, prayer support, memorization, and dua share one progress language.
3. Text mode and Mushaf mode remain explicit, persistent reader choices.
4. Local use stays useful when offline; sync is explained in human language.
5. Future modules are visible only as disabled `Soon` affordances, never as fake working features.
6. Quran and dua text use repository sources; unconnected translations and tafsir never receive invented copy.

## 2. Information architecture

The bottom navigation has five stable destinations:

| Destination | Primary job | Important child routes |
| --- | --- | --- |
| Home | Today, next action, resume | reader, prayer reading, memorization, dua entry |
| Quran | Find and read | text reader, Mushaf reader, quick jump |
| Plan | Daily target and history | after-prayer plan, manual reading entry |
| Audio | Reciters and tracks | full player, timer, repeat/range settings |
| More | Supporting tools and account | prayer, memorization, dua, favorites, account, settings |

Player state is global. A compact player sits immediately above the bottom navigation, and the full player is a route. Selecting a different reciter stops the current session before playback can resume with the new source.

### Screen map

```text
Onboarding
├── Language: RU / EN / AR / TR
├── Main goal
└── Daily norm → guest mode → Home

Home
├── Continue Quran → Text reader / Mushaf
├── After-prayer reading → Prayer reading
├── Memorization → Training
└── Dua → Dua entry

Quran
├── Search and catalog
├── Text reader
│   ├── reader preferences
│   ├── translation / footnote state
│   └── on-demand tafsir state
└── Mushaf reader
    ├── page zoom and ayah selection
    └── quick jump: surah / ayah / page / juz

Plan
├── Daily goal and streak
├── History
├── Manual entry
└── After-prayer plan

Audio
├── Reciter selection
├── Track selection
└── Full player: repeat / range / speed / pause / timer

More
├── Prayer
├── Memorization
├── Dua
├── Unified favorites
├── Account and devices
└── Settings and system-state lab
```

## 3. Core journeys

### 3.1 First launch

1. Choose RU, EN, AR, or TR. Arabic immediately switches the whole shell to RTL.
2. Choose a primary goal: reading, memorization, prayer support, or dua.
3. Choose a small daily norm in minutes, pages, or ayahs.
4. Continue as a guest. Notification permission is not requested during the introduction; context and benefit are explained at the relevant prayer or reminder action.

### 3.2 Read Al-Fatiha in Text mode and bookmark an ayah

1. Open Quran from the bottom navigation.
2. Keep the persisted `Text` mode and open Al-Fatiha.
3. Read Arabic from the verified local sample.
4. Tap the bookmark control for an ayah. The control, toast, and unified Favorites view update immediately.
5. Translation, footnote, and tafsir areas expose loading/availability boundaries. They do not fabricate religious content while editions are unconnected.

### 3.3 Switch to Mushaf and jump to an ayah

1. Switch the Quran catalog to the persisted `Mushaf` mode and choose a Mushaf edition.
2. Open quick jump, enter surah and ayah (or page/juz), and confirm.
3. The page opens with the target ayah visually selected.
4. Zoom changes are independent from the selected ayah, and the current page/ayah position persists.

### 3.4 Change reciter and start playback

1. Open Audio and choose a reciter.
2. Start a track; a global compact player appears above navigation.
3. Change the reciter. Active playback stops so old audio is never presented as the new reciter.
4. Start playback again. Full player controls show repeat mode, range, speed, inter-ayah pause, and sleep timer.

### 3.5 Read two pages after Fajr and see daily progress

1. Open Plan → After-prayer plan.
2. Add two pages to Fajr. Each prayer maintains an independent target and actual value.
3. The plan summary and Home daily progress update from the same state.
4. Prayer reminders and the after-prayer prompt remain separate toggles.

### 3.6 Complete a memorization repetition and reset

1. Choose an ayah range, repetition target, and pause.
2. Start a repetition, then assess it as Again, Hard, or Good.
3. The completed counter and assessment update.
4. `Reset today` requires confirmation and clears only today's repetition result.

### 3.7 Add a dua to favorites and reopen it

1. Open Dua → a topic → an entry.
2. Add the entry to favorites.
3. Open unified Favorites and filter by Dua.
4. Reopen the exact entry from the filtered list.

## 4. Screen-to-backend contract matrix

The prototype uses local mock state, but its boundaries follow the current OpenAPI and backend documentation. The Flutter client should put generated DTOs and transport code behind repositories so the UI does not depend on raw endpoints.

| Mobile surface | Existing backend contract | Offline and sync decision |
| --- | --- | --- |
| Guest start and verification | `POST /api/v1/auth/guest`, `/auth/email/start`, `/auth/email/verify`, `/auth/token/refresh`, `/auth/logout`, `/auth/logout-all` | Keep tokens only in secure storage. Guest mode is fully functional locally. Queue eligible user mutations; never queue login operations. |
| Account and devices | `GET/PATCH /api/v1/me`, `GET /me/devices`, `DELETE /me/devices/{device_id}`, deletion request/cancel | Cache display metadata. Device revocation and deletion require online confirmation and are never optimistic. |
| Quran catalog | `/api/v1/quran/editions`, edition detail, surah/juz/hizb/rub/page endpoints | Cache catalog metadata and the current reading slice. Full offline editions require a future versioned package manifest. |
| Text reader | `/quran/editions/{edition}/surahs/{surah}/ayahs`, `/translations`, `/translations/{translation}/surahs/{surah}`, `/tafsirs`, `/tafsirs/{tafsir}/surahs/{surah}` | Arabic source and approved edition IDs are versioned. Translation/tafsir availability is explicit; absence is a state, not fallback copy. Tafsir is fetched on demand. |
| Mushaf reader | `/api/v1/quran/foundation/mushafs`, `/mushafs/{mushaf}/pages/{page}` | Cache the current and adjacent pages. A complete Mushaf download waits for a package API with checksums, size, license, and version. |
| Reader preferences and position | `GET/PUT /api/v1/me/quran-reader-preferences/{locale}`, `GET/PUT /api/v1/me/reading-position/{edition}` | Local-first write. The latest accepted position is sent through the outbox; preferences are scoped by locale. |
| Quran bookmarks | `GET/POST /api/v1/me/bookmarks`, `DELETE /api/v1/me/bookmarks/{bookmark_id}` | Apply locally, enqueue an idempotent mutation, preserve tombstones until acknowledged. |
| Audio catalog and playback | `/api/v1/reciters`, `/recitations`, track/surah/ayah endpoints, Quran.Foundation ayah recitations | Stream from published URLs. Downloaded audio uses repository IDs, checksums, and quota-aware cache metadata; switching reciter cancels the old source. |
| Daily reading | `/api/v1/me/reading-goal`, `/me/today`, `/me/reading-planner`, `/me/reading-sessions`, `/automatic`, `/manual` | Sessions are local-first with stable client IDs. Totals are derived from acknowledged plus pending sessions and reconciled after pull. |
| After-prayer reading | `/api/v1/me/prayer-reading-plan`, `/me/prayer-reading-check-ins`, `/check-ins/{check_in_id}` | Store independent prayer targets/check-ins. Mutations use the same outbox and deduplication rules as reading sessions. |
| Prayer schedule and reminders | `/api/v1/prayer/methods`, `/prayer/calculate`, `/me/prayer-profile`, `/me/reminders`, `/me/web-push` | Calculation/profile is cached by date, location parameters, method, timezone, and Asr rule. Native reminders are scheduled locally from synced rules; notification permission remains platform-owned. |
| Memorization | `GET/PUT /api/v1/me/memorization`, `POST /me/memorization-sessions` | Range and current counters work locally. Queue completed sessions. Spaced repetition is explicitly future scope. |
| Dua | `/api/v1/dua/collections`, `/dua/categories`, `/dua/entries`, `/dua/entries/{id}`, `/me/dua-favorites` | Cache the approved collection index and recently opened entries. Favorites are local-first with stable collection slug/source number identity. |
| Cross-device synchronization | `POST /api/v1/sync/push`, `GET /api/v1/sync/pull` | Persist an ordered outbox and pull cursor. Push first, pull until complete, acknowledge only server-confirmed mutations, handle expired cursors with full resync, and retain server tombstones. |
| Support | `/api/v1/feedback/tickets` and message/close/reopen endpoints | Draft text can be local; ticket creation and status changes require online confirmation. |

### Explicitly future, not simulated as complete

- Nature sounds: rights, audio catalog, mixing policy, and background behavior are undecided.
- Books, quizzes, and Q&A: no production contracts or approved content workflow exist.
- Full Quran/Mushaf offline packages: current endpoints support reading slices, not a signed package lifecycle.
- Advanced spaced repetition: the current memorization contract does not define a full scheduler.
- Lock-screen and native media controls: UI mapping is demonstrated, but implementation belongs to the Flutter platform layer.

## 5. Local data and synchronization model

The scalable mobile target uses four layers:

```text
Feature UI → feature controller/use cases → repositories → local DB / API / platform services
```

The local database is the UI source of truth. An outbox records mutations with a stable client mutation ID, entity identity, operation, payload, base version where required, and creation time. A sync worker serializes push/pull, retries transient failures with backoff, and never drops a mutation merely because the process restarts.

Conflict copy must remain human:

- Reading position: “Your other device is further ahead. Keep this position or continue there?”
- Deleted favorite/bookmark: remove it locally after the server tombstone is accepted; do not resurrect it from stale cache.
- Expired cursor: “Updating your library…” while a full resync rebuilds the local projection.
- Session expired: preserve offline work, pause sync, and ask the user to sign in again.

## 6. Responsive, accessibility, and RTL rules

- Reference viewports: 360×800, 390×844, and 430×932.
- The app shell consumes safe-area insets; bottom navigation and sheets add the bottom inset.
- Interactive targets are at least 44×44 CSS pixels.
- Typography uses `rem`/`clamp` where it materially affects reading and respects user font scaling without fixed-height text containers.
- Arabic locale sets the root document direction to RTL. Logical CSS properties keep navigation, cards, back controls, and form alignment correct while Quran text preserves its own Arabic direction.
- Light and dark themes use semantic tokens; state is not communicated by color alone.
- Reduced-motion preference collapses nonessential transitions.
- Loading, offline, API error, expired session, sync conflict, denied notifications/location, missing audio, and missing offline copy each have a dedicated user-facing state.

## 7. Analytics events for implementation

No analytics are emitted by this local prototype. The Flutter implementation should use an allow-listed, privacy-reviewed schema such as:

- `onboarding_completed` with goal and daily-unit categories, no free text.
- `reader_opened` with mode, edition ID, and resume/source entry point.
- `ayah_bookmark_toggled` with action and edition, avoiding Arabic text in the payload.
- `audio_play_started` with recitation ID and content identity.
- `daily_progress_changed` with source (`automatic`, `manual`, `after_prayer`).
- `sync_state_changed` with coarse state and error class, never token or religious-content payloads.

Location, prayer profile, reading history, and account data require a clear retention and consent policy before instrumentation ships.
