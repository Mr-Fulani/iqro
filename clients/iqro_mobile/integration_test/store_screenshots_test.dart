// The App Store screenshots: the eight screens of the Google Play set
// (docs/release/play-store-screenshots/README.md) in one language, on the
// simulator the "App Store screenshots" workflow starts. The language comes
// from IQRO_LOCALE; the runs share one install, so the account and the city
// carry over from one language to the next.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/app_shell.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/storage/preferences_store.dart';
import 'package:iqro_mobile/features/courses/course_catalog_screen.dart';
import 'package:iqro_mobile/features/prayer/prayer_places.dart';
import 'package:iqro_mobile/features/prayer/prayer_screen.dart';
import 'package:iqro_mobile/features/quran/foundation_mushaf_page.dart';
import 'package:iqro_mobile/features/quran/mushaf_edition_picker.dart';
import 'package:iqro_mobile/features/quran/native_mushaf_page.dart';
import 'package:iqro_mobile/features/quran/reader_flow_screen.dart';
import 'package:iqro_mobile/features/quran/surah_name_art.dart';
import 'package:iqro_mobile/main.dart' as app;

import 'support/iqro_harness.dart';

void main() {
  final harness = IqroHarness.initialize();

  testWidgets(
    'App Store screenshots',
    (tester) => harness.run(tester, () async {
      debugPrint('IQRO DEVICE $platformName');
      await harness.prepare(quiet: true);
      final l10n = harness.l10n;
      app.main();
      await harness.waitFor(
        find.byType(AppShell),
        what: 'the app',
        timeout: const Duration(seconds: 90),
      );
      final reading = find.byKey(const ValueKey('home-reading'));
      await harness.waitFor(reading, what: 'Home');

      // Home's prayer card needs a city; Istanbul, as in the Google Play set.
      await _chooseIstanbul(harness);
      harness.router.go('/app');
      await harness.waitFor(reading, what: 'Home');
      await harness.waitForNone(
        find.descendant(of: reading, matching: find.text(l10n.loading)),
        what: 'the reading card loaded',
      );
      // An active announcement floats over Home until it has been opened
      // once and the app restarted: the setup run opens it, so the language
      // runs after it show Home without it.
      await _openAnnouncement(harness);
      if (harness.mode == 'setup') {
        expect(harness.errors, isEmpty, reason: 'Dart errors were reported');
        return;
      }
      await harness.settle(const Duration(seconds: 7));
      await harness.screenshot('home');

      // The Mushaf opens on the page asked for only once the editions are
      // known (mushaf_screen.dart); the Quran tab loads them.
      await harness.openTab(l10n.navQuran);
      await harness.waitFor(
        find.byType(MushafEditionThumbnail),
        what: 'the Mushaf editions',
      );
      await _mushafPage(harness, 3);
      await harness.waitFor(
        find.byKey(const ValueKey('mushaf-tajweed-legend')),
        what: 'the tajweed legend',
      );
      await harness.settle(const Duration(seconds: 2));
      await harness.screenshot('mushaf-tajweed');
      harness.back();

      harness.router.push('/names');
      await harness.waitFor(
        find.byKey(const ValueKey('names-number')),
        what: 'the Names of Allah',
      );
      await harness.settle(const Duration(seconds: 3));
      await harness.screenshot('names-of-allah');
      harness.back();

      if (harness.locale == 'ar') {
        // No translation in the Arabic interface: the Quran tab instead.
        await harness.openTab(l10n.navQuran);
        await harness.waitFor(
          find.byType(SegmentedButton<ReaderMode>),
          what: 'the Quran tab',
        );
        await harness.waitFor(find.byType(SurahNameArt), what: 'the surahs');
        await harness.waitFor(
          find.byType(MushafEditionThumbnail),
          what: 'the Mushaf editions',
        );
        await harness.settle(const Duration(seconds: 2));
        await harness.screenshot('quran');
        await harness.openTab(l10n.navHome);
      } else {
        harness.router.push('/reader/1');
        await harness.waitFor(
          find.byKey(const ValueKey('reader-translation-7')),
          what: 'the translation',
        );
        await harness.waitForLoaded(
          scope: find.byKey(const ValueKey('reader-translation-7')),
          what: 'the translations',
        );
        await harness.settle(const Duration(seconds: 2));
        await harness.screenshot('reader');
        harness.back();
      }

      // Reading aloud; listening itself needs a microphone the simulator in
      // CI does not have (README.md).
      final navigator = Navigator.of(
        tester.element(find.byType(AppShell).first),
      );
      navigator.push(ReaderFlowScreen.route(surah: 1, ayah: 1));
      await harness.waitFor(
        find.byKey(const ValueKey('reader-flow-follow')),
        what: 'reading aloud',
      );
      await harness.settle(const Duration(seconds: 2));
      await harness.screenshot('reading-aloud');
      navigator.pop();
      await harness.settle();

      harness.router.go('/prayer');
      await harness.waitFor(find.byType(PrayerScreen), what: 'prayer times');
      await harness.waitForLoaded(
        scope: find.byType(PrayerScreen),
        what: 'the prayer times',
      );
      await harness.settle(const Duration(seconds: 2));
      await harness.screenshot('prayer-qibla');

      harness.router.go('/app');
      harness.router.push('/courses');
      await harness.waitFor(
        find.byKey(const ValueKey('courses-salah')),
        what: 'the courses',
      );
      await harness.waitForLoaded(
        scope: find.byType(CourseCatalogScreen),
        what: 'the course covers',
      );
      await harness.settle(const Duration(seconds: 2));
      await harness.screenshot('courses');
      harness.back();

      final preferences = harness.container.read(
        appPreferencesProvider.notifier,
      );
      await preferences.setMushafNight(true);
      await _mushafPage(harness, 2);
      await _showMushafControls(harness, 2);
      await harness.screenshot('mushaf-night');
      harness.back();
      await preferences.setMushafNight(false);
      await harness.settle();

      expect(harness.errors, isEmpty, reason: 'Dart errors were reported');
    }),
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

Future<void> _chooseIstanbul(IqroHarness harness) async {
  harness.router.go('/prayer');
  final choose = find.widgetWithText(TextButton, harness.l10n.chooseCity);
  await harness.waitFor(choose, what: 'the prayer times screen');
  await harness.waitUntil(
    () => harness.tester.widget<TextButton>(choose.first).onPressed != null,
    what: 'the city button enabled',
  );
  await harness.tap(choose, what: 'Choose city');
  final istanbul = prayerCities.firstWhere((city) => city.id == 'istanbul');
  final name = istanbul.names[harness.locale] ?? istanbul.names['en']!;
  await harness.tap(find.text(name).last, what: name);
  await harness.waitForNone(find.byType(BottomSheet), what: 'the city list');
  await harness.waitFor(find.textContaining(name), what: 'the times for $name');
  await harness.waitForLoaded(
    scope: find.byType(PrayerScreen),
    what: 'the prayer times',
  );
}

Future<void> _openAnnouncement(IqroHarness harness) async {
  final bubble = find.byKey(const ValueKey('announcement-bubble'));
  if (bubble.evaluate().isEmpty) return;
  await harness.tap(bubble, what: 'the announcement bubble');
  final close = find.byKey(const ValueKey('announcement-close'));
  await harness.tap(close, what: 'the announcement close button');
  await harness.waitForNone(close, what: 'the announcement closed');
}

Future<void> _mushafPage(IqroHarness harness, int number) async {
  harness.router.push('/mushaf?page=$number&layout=physical');
  final page = find.byWidgetPredicate(
    (widget) => widget is NativeMushafPage && widget.page == number,
  );
  await harness.waitFor(
    find.descendant(of: page, matching: find.byType(FoundationPageCanvas)),
    what: 'Mushaf page $number',
    timeout: const Duration(seconds: 90),
  );
  await harness.waitForLoaded(scope: page, what: 'Mushaf page $number');
  await harness.settle(const Duration(seconds: 2));
}

/// A tap on the paper beside the lines shows the Mushaf's bars; a tap on a
/// word would select its ayah instead, so it tries spots below the text.
Future<void> _showMushafControls(IqroHarness harness, int number) async {
  final tester = harness.tester;
  final night = find.byKey(const ValueKey('mushaf-night'));
  final opacity = find.ancestor(
    of: night,
    matching: find.byType(AnimatedOpacity),
  );
  bool shown() => tester.widget<AnimatedOpacity>(opacity.first).opacity == 1;
  final canvas = find.descendant(
    of: find.byWidgetPredicate(
      (widget) => widget is NativeMushafPage && widget.page == number,
    ),
    matching: find.byType(FoundationPageCanvas),
  );
  final area = tester.getRect(canvas.first);
  for (final spot in <Offset>[
    Offset(area.center.dx, area.bottom - 6),
    Offset(area.left + 6, area.bottom - 6),
    Offset(area.right - 6, area.bottom - 6),
    Offset(area.center.dx, area.top + 6),
  ]) {
    await tester.tapAt(spot);
    await harness.settle(const Duration(milliseconds: 800));
    if (shown()) {
      await harness.settle(const Duration(milliseconds: 1200));
      return;
    }
  }
  debugPrint('IQRO NOTE the Mushaf bars did not open');
}
