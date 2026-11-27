# The app on iOS simulators

Nobody on the project has an iPhone or Xcode, so these tests are the check of every iOS build
before TestFlight. They run the real app — debug build, production server
`https://iqro.forum` — on simulators in GitHub Actions and keep a screen recording and
screenshots.

| File | What it does | Workflow |
|---|---|---|
| `app_smoke_test.dart` | From a fresh install through the main screens (below) on iPhone 6.9″ and iPad 13″, in Russian | `iOS simulators` (`.github/workflows/ios-simulators.yml`), artifact `iqro-ios-simulators` |
| `store_screenshots_test.dart` | The eight screens of the Google Play set in one language; the workflow runs ru, en, ar, tr | `App Store screenshots`, artifact `app-store-screenshots-iphone-6.9` (iPad 13″ only when started with it) |
| `support/iqro_harness.dart` | Launch with preferences, waiting for screens, screenshots, the list of Dart errors | — |
| `driver/iqro_driver.dart` | Runs on the Mac: saves the simulator screen (`simctl io screenshot`, status bar 9:41) when the test asks | — |

`ios/scripts/simulator_run.sh` creates a fresh simulator, records the screen and runs a test
with `flutter drive`; the workflows call it.

## The smoke test, step by step

1. First launch: the welcome screen (`onboarding`). The intro video before it is marked as
   seen (see "Known"). The other welcome steps are not walked; the test opens the app.
2. Home, and the active announcement if there is one.
3. The Quran tab.
4. Mushaf page 3 with the tajweed legend. The test counts strong colours on the page: the
   QCF V4 font draws tajweed with its own colour layers, so a page without them fails.
5. Al-Fatiha with its translation.
6. Reading aloud by the real swipe, the recitation check button and its notice. It stops at
   the notice: "Turn on the microphone" brings up iOS permission alerts a test cannot answer.
7. The player: "Listen to the whole Quran" must actually play (the position moves), then
   pause.
8. Prayer times: choose Istanbul from the list (no GPS), then the qibla.
9. Reminders (only looked at: a switch would change the account on the server), settings,
   the More tab.

Any Dart error the app reports (`FlutterError`) fails the test; the log lists all of them.
Each step writes an `IQRO STEP` line; `steps.txt` in the artifact has them all.

## Known

- The intro video reports, in debug builds only, "A VideoPlayerController was used after
  being disposed": when the clip ends, video_player 2.11 pauses and then seeks to the end, and
  `StartupVideo` (`lib/core/startup/startup_video.dart`) disposes the controller in between.
  Release builds skip that check, so users see nothing, but the test would fail, so it starts
  with the intro marked as seen. A fix in `StartupVideo`: after the clip ends, dispose the
  controller only once the player's own pause and seek are done (for example, finish on
  `isCompleted` but dispose a second later), then let the test play the intro again.

## What a simulator does not check

The microphone and speech recognition, the adhan sound and notifications, the lock screen and
Control Center, the home-screen widgets, background tasks, Universal Links, Sign in with
Google, the release (AOT) build — Flutter runs only debug builds on a simulator — and
anything needing the signed app (App Group, push). These stay for the owner's iPhone in
TestFlight.

Every run makes one guest account on the production server (`/auth/guest`), as a new install
does; there is no staging server.

## Running it

In GitHub: Actions → `iOS simulators` → Run workflow, on any branch. It also runs on every
push to `main` and on pull requests that change the iOS project, these tests or the packages.

On a Mac with Xcode, from `clients/iqro_mobile`:

```bash
flutter build ios --simulator --debug --target=integration_test/app_smoke_test.dart --dart-define=API_BASE_URL=https://iqro.forum --dart-define=APP_ENV=production --dart-define=APP_DOWNLOAD_URL=https://iqro.forum
```

```bash
ios/scripts/simulator_run.sh test "$(ios/scripts/simulator_run.sh create 'iPhone 17 Pro Max')" build/ios/iphonesimulator/Runner.app integration_test/app_smoke_test.dart build/simulator-results
```
