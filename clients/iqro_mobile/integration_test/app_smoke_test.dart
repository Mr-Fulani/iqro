// The app's main screens on an iPhone or iPad simulator, from a fresh
// install, against https://iqro.forum. Run by ios/scripts/simulator_run.sh in
// the "iOS simulators" workflow; README.md in this folder says what it checks.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/app_shell.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/storage/preferences_store.dart';
import 'package:iqro_mobile/features/onboarding/onboarding_screen.dart';
import 'package:iqro_mobile/features/prayer/prayer_places.dart';
import 'package:iqro_mobile/features/prayer/prayer_screen.dart';
import 'package:iqro_mobile/features/quran/foundation_mushaf_page.dart';
import 'package:iqro_mobile/features/quran/mushaf_edition_picker.dart';
import 'package:iqro_mobile/features/quran/native_mushaf_page.dart';
import 'package:iqro_mobile/features/quran/reader_flow_screen.dart';
import 'package:iqro_mobile/features/quran/surah_name_art.dart';
import 'package:iqro_mobile/features/reminders/reminders_screen.dart';
import 'package:iqro_mobile/main.dart' as app;

import 'support/iqro_harness.dart';

final _locale = setting('IQRO_LOCALE', fallback: 'ru');

void main() {
  final harness = IqroHarness.initialize();

  testWidgets(
    'IQRO opens its main screens',
    (tester) => harness.run(tester, () async {
      debugPrint('IQRO DEVICE $platformName');
      await harness.prepare(
        locale: _locale,
        onboardingComplete: false,
        playIntro: true,
      );
      final l10n = harness.l10n;
      app.main();

      // The first launch: the intro video, then the welcome screen.
      await harness.waitFor(
        find.byType(OnboardingScreen),
        what: 'the welcome screen',
        timeout: const Duration(seconds: 90),
      );
      await harness.step('onboarding');
      // The rest of the welcome steps belong to their own tests; open the app.
      harness.router.go('/app');

      await _home(harness);
      await _announcement(harness);
      await _quran(harness);
      await _mushaf(harness);
      await _reader(harness);
      await _recitationCheck(harness);
      await _player(harness);
      await _prayer(harness);
      await _reminders(harness);
      await _settings(harness);
      await harness.openTab(l10n.navMore);
      await harness.waitFor(
        find.byKey(const ValueKey('app-version')),
        what: 'the More tab',
      );
      await harness.step('more');

      expect(harness.errors, isEmpty, reason: 'Dart errors were reported');
    }),
    timeout: const Timeout(Duration(minutes: 20)),
  );
}

Future<void> _home(IqroHarness harness) async {
  await harness.waitFor(find.byType(AppShell), what: 'the app');
  final reading = find.byKey(const ValueKey('home-reading'));
  await harness.waitFor(reading, what: 'Home');
  await harness.waitForNone(
    find.descendant(of: reading, matching: find.text(harness.l10n.loading)),
    what: 'the reading card loaded',
  );
  // The opening animation of the sky card lasts 6 s.
  await harness.settle(const Duration(seconds: 6));
  await harness.step('home');
}

Future<void> _announcement(IqroHarness harness) async {
  final bubble = find.byKey(const ValueKey('announcement-bubble'));
  if (bubble.evaluate().isEmpty) {
    debugPrint('IQRO STEP announcement skipped: none is active');
    return;
  }
  await harness.tap(bubble, what: 'the announcement bubble');
  final close = find.byKey(const ValueKey('announcement-close'));
  await harness.waitFor(close, what: 'the announcement');
  await harness.step('announcement');
  await harness.tap(close, what: 'the announcement close button');
}

Future<void> _quran(IqroHarness harness) async {
  await harness.openTab(harness.l10n.navQuran);
  await harness.waitFor(
    find.byType(SegmentedButton<ReaderMode>),
    what: 'the Quran tab',
  );
  await harness.waitFor(find.byType(SurahNameArt), what: 'the surah list');
  // The Mushaf must open after the editions are known (mushaf_screen.dart).
  await harness.waitFor(
    find.byType(MushafEditionThumbnail),
    what: 'the Mushaf editions',
  );
  await harness.step('quran');
}

Future<void> _mushaf(IqroHarness harness) async {
  harness.router.push('/mushaf?page=3&layout=physical');
  final page = find.byWidgetPredicate(
    (widget) => widget is NativeMushafPage && widget.page == 3,
  );
  final canvas = find.descendant(
    of: page,
    matching: find.byType(FoundationPageCanvas),
  );
  await harness.waitFor(
    canvas,
    what: 'Mushaf page 3',
    timeout: const Duration(seconds: 90),
  );
  await harness.waitFor(
    find.byKey(const ValueKey('mushaf-tajweed-legend')),
    what: 'the tajweed legend',
  );
  await harness.waitForLoaded(scope: page, what: 'Mushaf page 3');
  await harness.settle(const Duration(seconds: 2));
  final edition = (page.evaluate().first.widget.key! as ValueKey<String>).value;
  final colours = await harness.colours(canvas);
  final strong = colours.entries.where((entry) => entry.value >= 150).toList();
  await harness.step(
    'mushaf-tajweed',
    note: '$edition, colour pixels $colours',
  );
  expect(
    strong.length,
    greaterThanOrEqualTo(2),
    reason: 'The tajweed colours of the QCF V4 font are not drawn: $colours',
  );
  harness.back();
}

Future<void> _reader(IqroHarness harness) async {
  harness.router.push('/reader/1');
  await harness.waitFor(
    find.byKey(const ValueKey('reader-ayah-1')),
    what: 'Al-Fatiha',
  );
  final translation = find.byKey(const ValueKey('reader-translation-1'));
  await harness.waitFor(translation, what: 'the translation');
  await harness.waitForLoaded(scope: translation, what: 'the translation');
  await harness.settle(const Duration(seconds: 2));
  await harness.step('reader');
}

Future<void> _recitationCheck(IqroHarness harness) async {
  final tester = harness.tester;
  // The swipe that opens reading aloud, as a person makes it.
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  await tester.flingFrom(
    Offset(size.width * 0.25, size.height * 0.55),
    Offset(size.width * 0.5, 0),
    1500,
  );
  final flow = find.byKey(const ValueKey('reader-flow'));
  try {
    await harness.waitFor(
      flow,
      what: 'reading aloud',
      timeout: const Duration(seconds: 10),
    );
  } on TestFailure {
    debugPrint('IQRO NOTE the swipe did not open reading aloud; opening it');
    Navigator.of(
      tester.element(find.byKey(const ValueKey('reader-ayah-1'))),
    ).push(ReaderFlowScreen.route(surah: 1, ayah: 1));
    await harness.waitFor(flow, what: 'reading aloud');
  }
  final follow = find.byKey(const ValueKey('reader-flow-follow'));
  await harness.tap(follow, what: 'the recitation check button');
  final notice = find.byKey(const ValueKey('recitation-notice'));
  await harness.waitFor(notice, what: 'the recitation check notice');
  await harness.step('recitation-check');
  // "Turn on the microphone" would bring up iOS's permission alerts, which a
  // test cannot answer; the notice is the way in.
  await harness.tap(
    find.descendant(of: notice, matching: find.text(harness.l10n.cancel)),
    what: 'Cancel',
  );
  await harness.waitForNone(notice, what: 'the notice closed');
  await Navigator.of(tester.element(flow)).maybePop();
  await harness.settle();
  harness.back();
  await harness.settle();
}

Future<void> _player(IqroHarness harness) async {
  await harness.openTab(harness.l10n.navAudio);
  await harness.tap(
    find.byKey(const ValueKey('audio-listen-whole-quran')),
    what: 'Listen to the whole Quran',
  );
  await harness.waitFor(
    find.byKey(const ValueKey('player-controls-toggle')),
    what: 'the player',
  );
  // Streaming from the server: wait until the position moves.
  final started = DateTime.now();
  var audio = harness.container.read(audioControllerProvider);
  while (DateTime.now().difference(started) < const Duration(seconds: 45)) {
    audio = harness.container.read(audioControllerProvider);
    if (audio.playing && audio.position > const Duration(seconds: 2)) break;
    if (audio.error != null) break;
    await harness.settle(const Duration(milliseconds: 500));
  }
  await harness.step(
    'player',
    note: 'playing ${audio.playing}, at ${audio.position.inSeconds} s',
  );
  expect(audio.error, isNull, reason: 'The player reported an error');
  expect(
    audio.position,
    greaterThan(const Duration(seconds: 2)),
    reason: 'The audio did not play',
  );
  await harness.tap(find.byTooltip(harness.l10n.pause), what: 'Pause');
  harness.back();
  await harness.settle();
}

Future<void> _prayer(IqroHarness harness) async {
  harness.router.go('/prayer');
  final choose = find.widgetWithText(TextButton, harness.l10n.chooseCity);
  await harness.waitFor(choose, what: 'the prayer times screen');
  // Enabled once the methods and the profile have loaded.
  await harness.waitUntil(
    () => harness.tester.widget<TextButton>(choose.first).onPressed != null,
    what: 'the city button enabled',
  );
  await harness.tap(choose, what: 'Choose city');
  final istanbul = prayerCities.firstWhere((city) => city.id == 'istanbul');
  final name = istanbul.names[harness.l10n.localeName] ?? istanbul.names['en']!;
  await harness.tap(find.text(name).last, what: name);
  await harness.waitForNone(find.byType(BottomSheet), what: 'the city list');
  await harness.waitFor(find.textContaining(name), what: 'the times for $name');
  await harness.waitForLoaded(
    scope: find.byType(PrayerScreen),
    what: 'the prayer times',
  );
  await harness.settle(const Duration(seconds: 2));
  await harness.step('prayer');

  // The same screen opened with the qibla, as from Home's qibla tile.
  harness.router.go('/prayer?qibla=1');
  final dial = find.byKey(const ValueKey('qibla-dial'));
  await harness.waitFor(dial, what: 'the qibla');
  await harness.step('qibla');
  await Navigator.of(harness.tester.element(dial)).maybePop();
  await harness.waitForNone(dial, what: 'the qibla closed');
}

Future<void> _reminders(IqroHarness harness) async {
  harness.router.push('/reminders');
  await harness.waitFor(
    find.text(harness.l10n.prayerReminders),
    what: 'the reminders screen',
  );
  await harness.waitForLoaded(
    scope: find.byType(RemindersScreen),
    what: 'the reminders',
  );
  // Only look: a switch would change the account on the server.
  await harness.step('reminders');
  harness.back();
}

Future<void> _settings(IqroHarness harness) async {
  harness.router.push('/settings');
  await harness.waitFor(
    find.byKey(const ValueKey('settings-theme')),
    what: 'the settings',
  );
  await harness.step('settings');
  harness.back();
}
