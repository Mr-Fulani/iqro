import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/design_system/iqro_widgets.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/audio/audio_screen.dart';
import 'package:iqro_mobile/features/home/home_dashboard_cards.dart';
import 'package:iqro_mobile/features/home/home_dashboard_layout.dart';
import 'package:iqro_mobile/features/plan/plan_repository.dart';
import 'package:iqro_mobile/features/prayer/prayer_repository.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

const _features = ['After prayer', 'Memorization', 'Audio', 'Dua'];
const _utilities = ['Saved', 'Calendar', 'Downloads'];

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required double width,
  double height = 1400,
  String locale = 'ru',
  String surahName = 'Аль-Мульк',
  String memorization = 'Memorization subtitle',
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final clock = DateTime(2026, 10, 27, 11, 30);
  await tester.pumpWidget(
    MaterialApp(
      theme: IqroTheme.light(),
      locale: Locale(locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: IqroPage(
          tabletContentWidth: homeTabletContentWidth,
          child: HomeDashboardLayout(
            prayer: HomePrayerCard(
              schedule: PrayerSchedule(
                date: clock,
                timezone: 'Europe/Moscow',
                times: {'dhuhr': DateTime(2026, 10, 27, 12, 21)},
                timesUtc: const {},
                methodName: 'test',
                warnings: const [],
              ),
              loading: false,
              clock: clock,
              onTap: () {},
              onReminders: () {},
            ),
            reading: HomeContinueReadingCard(
              surahName: surahName,
              ayah: 1,
              page: 562,
              onTap: () {},
              onBookmarks: () {},
            ),
            plan: HomePlanCard(
              achieved: 4,
              target: 10,
              metric: ReadingGoalMetric.pages,
              loading: false,
              error: false,
              onTap: () {},
            ),
            features: [
              for (final title in _features)
                HomeFeatureCard(
                  icon: Icons.star_outline,
                  title: title,
                  subtitle: title == 'Memorization'
                      ? memorization
                      : '$title subtitle',
                  onTap: () {},
                ),
            ],
            utilities: [
              for (final title in _utilities)
                HomeUtilityRow(
                  icon: Icons.star_outline,
                  title: title,
                  subtitle: '$title subtitle',
                  onTap: () {},
                ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Rect _card(WidgetTester tester, String title) => tester.getRect(
  find.ancestor(of: find.text(title), matching: find.byType(IqroCard)).first,
);

void main() {
  testWidgets('a phone keeps the single column', (tester) async {
    await _pumpDashboard(tester, width: 400);

    expect(tester.takeException(), isNull);
    final prayer = tester.getRect(find.byKey(const ValueKey('home-prayer')));
    final reading = tester.getRect(find.byKey(const ValueKey('home-reading')));
    expect(reading.top, greaterThan(prayer.bottom));
    expect(prayer.width, 400 - 32);
    // Two feature cards a row, the utilities in one list card.
    expect(
      _card(tester, 'After prayer').top,
      _card(tester, 'Memorization').top,
    );
    expect(
      _card(tester, 'Audio').top,
      greaterThan(_card(tester, 'After prayer').bottom),
    );
    expect(_card(tester, 'Saved'), _card(tester, 'Downloads'));
  });

  for (final width in [700.0, 1000.0]) {
    testWidgets('a ${width.round()} dp tablet follows the site home', (
      tester,
    ) async {
      await _pumpDashboard(tester, width: width);

      expect(tester.takeException(), isNull);
      final full = width - 32;
      final reading = tester.getRect(
        find.byKey(const ValueKey('home-reading')),
      );
      final plan = tester.getRect(find.byKey(const ValueKey('home-plan')));
      final prayer = tester.getRect(find.byKey(const ValueKey('home-prayer')));
      // Reading first like the site's hero, the daily goal next, the prayer
      // times last; each across the full width.
      expect(reading.width, full);
      expect(plan.width, full);
      expect(prayer.width, full);
      expect(plan.top, greaterThan(reading.bottom));
      // Cards in pairs of equal height, 16 apart.
      final afterPrayer = _card(tester, 'After prayer');
      final memorization = _card(tester, 'Memorization');
      expect(afterPrayer.top, greaterThan(plan.bottom));
      expect(memorization.top, afterPrayer.top);
      expect(memorization.height, afterPrayer.height);
      expect(memorization.left - afterPrayer.right, 16);
      final utilities = [for (final title in _utilities) _card(tester, title)];
      for (final card in utilities) {
        expect(card.top, utilities.first.top);
      }
      expect(utilities.first.top, greaterThan(afterPrayer.bottom));
      final audio = _card(tester, 'Audio');
      expect(audio.top, greaterThan(utilities.first.bottom));
      expect(_card(tester, 'Dua').top, audio.top);
      expect(prayer.top, greaterThan(audio.bottom));
      // The whole day, as the site's prayer schedule.
      expect(
        find.byKey(const ValueKey('home-prayer-time-dhuhr')),
        findsOneWidget,
      );
    });
  }

  testWidgets('a row grows when the data of a card arrives later', (
    tester,
  ) async {
    await _pumpDashboard(tester, width: 700, memorization: 'Загрузка…');
    // The same cards rebuilt with a longer subtitle, as when the data loads.
    await _pumpDashboard(
      tester,
      width: 700,
      memorization: 'Аль-Мульк 1–30 · 3/10, Аль-Мульк 1–30 · 3/10, ещё строка',
    );

    expect(tester.takeException(), isNull);
    expect(
      _card(tester, 'After prayer').height,
      _card(tester, 'Memorization').height,
    );
  });

  testWidgets('right-to-left rows start at the right edge', (tester) async {
    await _pumpDashboard(tester, width: 1000, locale: 'ar');

    expect(tester.takeException(), isNull);
    expect(_card(tester, 'After prayer').right, 1000 - 16);
    expect(_card(tester, 'Memorization').left, 16);
  });

  testWidgets('a landscape tablet uses its width up to the limit', (
    tester,
  ) async {
    // Pixel Tablet in landscape.
    await _pumpDashboard(tester, width: 1280, height: 800);

    expect(tester.takeException(), isNull);
    final plan = tester.getRect(find.byKey(const ValueKey('home-plan')));
    expect(plan.width, homeTabletContentWidth - 32);
    expect(plan.center.dx, 640);
  });

  testWidgets('a landscape phone keeps its centered column', (tester) async {
    // Redmi Note 7 turned to landscape.
    await _pumpDashboard(tester, width: 851, height: 393);

    expect(tester.takeException(), isNull);
    final plan = tester.getRect(find.byKey(const ValueKey('home-plan')));
    expect(plan.width, iqroLandscapeContentWidth - 32);
  });

  test('reciter portraits fill their cards at every width', () {
    for (final width in [328.0, 361.0, 608.0, 736.0, 968.0, 1168.0]) {
      final grid = reciterGridLayout(width, count: 12);
      final card = (width - 10 * (grid.columns - 1)) / grid.columns;
      expect(card - grid.portrait, lessThanOrEqualTo(13), reason: '$width');
      expect(grid.extent, grid.portrait + 92, reason: '$width');
    }
    // A phone keeps three columns, a tablet shows more and larger faces.
    expect(reciterGridLayout(361, count: 12).columns, 3);
    expect(reciterGridLayout(736, count: 12).columns, 4);
    expect(reciterGridLayout(1168, count: 12).columns, 7);
    expect(
      reciterGridLayout(736, count: 12).portrait,
      greaterThan(reciterGridLayout(361, count: 12).portrait),
    );
  });
}
