// Screenshots of every onboarding step in four languages, for the pull
// request and the Google Play listing:
//
//   flutter test test/features/onboarding_screenshots_test.dart \
//     --dart-define=SCREENSHOT_DIR=/tmp/shots
//
// Real fonts come from the Flutter SDK (Roboto, Material icons), the app's
// assets (Amiri Quran) and macOS (Georgia for `serif`, SF Arabic).
// Without SCREENSHOT_DIR the test is skipped: CI checks behaviour elsewhere.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/analytics/analytics.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/onboarding/onboarding_screen.dart';
import 'package:iqro_mobile/features/prayer/prayer_places.dart';
import 'package:iqro_mobile/features/prayer/prayer_repository.dart';
import 'package:iqro_mobile/features/reminders/reminder_models.dart';

import 'onboarding_test_support.dart';

const _directory = String.fromEnvironment('SCREENSHOT_DIR');
const _size = Size(1080, 2340); // Redmi Note 7
const _pixelRatio = 2.75;
final _boundary = GlobalKey();

const _cities = <String, String>{
  'ru': 'kazan',
  'en': 'london',
  'ar': 'makkah',
  'tr': 'istanbul',
};

Future<void> _loadFonts() async {
  final sdk = Platform.environment['FLUTTER_ROOT']!;
  final material = '$sdk/bin/cache/artifacts/material_fonts';
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final file in files) {
      final bytes = File(file).readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await family('Roboto', <String>[
    for (final weight in ['Regular', 'Medium', 'Bold'])
      '$material/Roboto-$weight.ttf',
  ]);
  await family('MaterialIcons', ['$material/MaterialIcons-Regular.otf']);
  await family('serif', <String>[
    '/System/Library/Fonts/Supplemental/Georgia.ttf',
    '/System/Library/Fonts/Supplemental/Georgia Bold.ttf',
  ]);
  await family(IqroTheme.arabicFontFamily, [
    'assets/fonts/AmiriQuran-Regular.ttf',
  ]);
  await family('SF Arabic', ['/System/Library/Fonts/SFArabic.ttf']);
}

/// The test engine has no system font fallback: name the Arabic fonts.
ThemeData _withArabic(ThemeData theme) {
  final text = theme.textTheme.apply(
    fontFamilyFallback: const [IqroTheme.arabicFontFamily, 'SF Arabic'],
  );
  final label = WidgetStatePropertyAll(text.labelLarge);
  return theme.copyWith(
    textTheme: text,
    filledButtonTheme: FilledButtonThemeData(
      style: theme.filledButtonTheme.style?.copyWith(textStyle: label),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: theme.outlinedButtonTheme.style?.copyWith(textStyle: label),
    ),
    textButtonTheme: TextButtonThemeData(
      style: theme.textButtonTheme.style?.copyWith(textStyle: label),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  String locale,
  OnboardingStep step, {
  int slide = 0,
  bool dark = false,
  bool located = false,
  bool allowed = false,
}) async {
  tester.view.padding = const FakeViewPadding(top: 66);
  final city = prayerCityById(_cities[locale]);
  await pumpOnboarding(
    tester,
    stored: <String, Object>{
      'locale': locale,
      if (step == OnboardingStep.done)
        'iqro_analytics_consent_v1': AnalyticsConsent.granted.name,
    },
    services: FakeOnboardingServices(
      location: located && city != null
          ? PrayerLocation(
              latitude: city.latitude,
              longitude: city.longitude,
              timezone: city.timezone,
              cityId: city.id,
            )
          : null,
      initialPermission: allowed
          ? ReminderPermission.granted
          : ReminderPermission.denied,
    ),
    initialStep: step,
    initialTourSlide: slide,
    dark: dark,
    themed: _withArabic,
    size: _size,
    pixelRatio: _pixelRatio,
    boundary: _boundary,
  );
  for (var index = 0; index < 3; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary =
      _boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  File('$_directory/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!);
  expect(tester.takeException(), isNull);
}

void main() {
  setUpAll(() async {
    if (_directory.isNotEmpty) await _loadFonts();
  });

  for (final locale in _cities.keys) {
    testWidgets('every step in $locale', (tester) async {
      Future<void> shot(
        String name,
        OnboardingStep step, {
        int slide = 0,
        bool located = false,
        bool allowed = false,
      }) async {
        await _pump(
          tester,
          locale,
          step,
          slide: slide,
          located: located,
          allowed: allowed,
        );
        await _capture(tester, 'onboarding-$locale-$name');
      }

      await shot('01-language', OnboardingStep.language);
      await shot('02-tour-quran', OnboardingStep.tour);
      await shot('03-tour-audio', OnboardingStep.tour, slide: 1);
      await shot('04-tour-study', OnboardingStep.tour, slide: 2);
      await shot('05-tour-daily', OnboardingStep.tour, slide: 3);
      await shot('06-plan', OnboardingStep.plan);
      await shot('07-prayer', OnboardingStep.prayer, located: true);
      await shot('08-reminders', OnboardingStep.reminders);
      await shot('09-exact-reminders', OnboardingStep.exactReminders);
      await shot('10-analytics', OnboardingStep.analytics);
      await shot('11-done', OnboardingStep.done, located: true, allowed: true);
    }, skip: _directory.isEmpty);
  }

  testWidgets('dark theme', (tester) async {
    for (final locale in <String>['ru', 'ar']) {
      await _pump(tester, locale, OnboardingStep.language, dark: true);
      await _capture(tester, 'onboarding-$locale-dark-01-language');
      await _pump(
        tester,
        locale,
        OnboardingStep.prayer,
        dark: true,
        located: true,
      );
      await _capture(tester, 'onboarding-$locale-dark-07-prayer');
      await _pump(tester, locale, OnboardingStep.tour, slide: 3, dark: true);
      await _capture(tester, 'onboarding-$locale-dark-05-tour-daily');
    }
  }, skip: _directory.isEmpty);
}
