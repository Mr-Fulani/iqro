# IQRO mobile prototype report

## What is delivered

- A standalone interactive mobile prototype under `prototypes/iqro-mobile`.
- RU, EN, AR RTL, and TR UI; light and dark themes.
- 360, 390, and 430 px responsive shells with safe-area handling.
- Onboarding, Home, Quran catalog, Text reader, Mushaf, Audio, full/compact player, Plan, after-prayer reading, Prayer, Memorization, Dua, Favorites, Account, and Settings.
- Persisted mock state and deterministic query parameters for walkthroughs and screenshots.
- Explicit loading, offline, API failure, expired session, sync conflict, denied permission, missing audio, and missing offline content states.
- Backend contract matrix and a Flutter-oriented architecture boundary.

No backend or current web code was changed. No deployment was performed.

## What was inherited from the current web product

- Existing backend vocabulary and resource identities for Quran editions, reader preferences, reading positions, bookmarks, reciters/recitations, reading goals/sessions, prayer plans/reminders, memorization, dua, devices, and sync.
- The project's current content sources: Madani Hafs Quran data and Hisn al-Muslim dua data.
- Offline/sync rules already documented in the repository: stable client mutations, outbox, incremental pull cursor, full resync, tombstones, and bounded retention.
- Existing capability boundaries. The prototype does not pretend that books, quizzes, Q&A, nature sounds, native notification scheduling, or full offline packages already exist.

## What changed for mobile

- A five-item, task-centered bottom navigation replaces portal-style discovery.
- Home becomes a daily action hierarchy rather than a module catalog.
- Player state is global and has compact/full forms designed around background continuity.
- Text and Mushaf readers are first-class persisted modes with a mobile quick-jump sheet.
- Plan and after-prayer check-ins are joined into one daily progress language.
- Settings exposes mobile-owned concerns: language/RTL, theme, content defaults, permission states, offline copy, devices, and sync wording.
- Future modules are visible but disabled with `Soon`, protecting scope while preserving the product map.

## Suggested Flutter decomposition

```text
apps/iqro_mobile
├── app/                 # routing, localization, theme, bootstrap
├── core/
│   ├── api/             # generated client, auth refresh, error mapping
│   ├── database/        # local projections, migrations, outbox, cursor
│   ├── sync/            # push/pull worker and conflict policies
│   ├── audio/           # playback, cache, media session bridge
│   ├── notifications/   # timezone-aware local scheduling
│   └── design_system/   # tokens and shared widgets
└── features/
    ├── onboarding/
    ├── home/
    ├── quran/
    ├── audio/
    ├── plan/
    ├── prayer/
    ├── memorization/
    ├── dua/
    ├── favorites/
    └── account/
```

Each feature owns presentation state and use cases. Repositories expose domain objects and streams; raw JSON, HTTP status codes, SQLite rows, and platform channels stay outside widgets. This allows the same feature tests to run with memory repositories and production adapters.

## Decisions needed from the product owner

1. Approve exact Quran translation and tafsir editions per locale, including licensing, attribution, versioning, and scholarly review.
2. Approve the production Quran font and tajweed rendering source after diacritic/waqf/platform QA.
3. Decide whether full offline Quran, Mushaf, translations, and audio are launch scope; define package sizes, Wi-Fi policy, storage limits, and deletion behavior.
4. Decide the prayer-location consent flow, manual fallback, calculation-method default by region, and notification copy/timing.
5. Define reciter download rights and whether background/lock-screen controls are required for the first mobile release.
6. Confirm whether nature sounds belong in IQRO. If yes, define rights, mixing behavior with recitation, and safeguarding/product rationale.
7. Confirm memorization launch scope: simple repetitions only or a reviewed spaced-repetition model.
8. Decide guest-to-account merge policy and user-facing behavior when local and server progress differ.
9. Approve privacy/retention rules for reading history, prayer profile/location inputs, device inventory, notification tokens, and analytics.
10. Confirm that Books, Quizzes, and Q&A remain post-launch until content governance and backend contracts are ready.

## Verification performed

- ESLint and TypeScript checks.
- Production build.
- Browser walkthroughs for all seven requested journeys.
- Horizontal-overflow checks across 360/390/430 widths and LTR/RTL.
- Compact-player/bottom-navigation collision check.
- Visual screenshots at 390×844 for RU light, EN light, AR RTL light, and RU dark.

See `screenshots/` for the final reference set.
