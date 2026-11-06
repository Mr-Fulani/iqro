import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/design_system/iqro_widgets.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/audio/audio_screen.dart';
import 'package:iqro_mobile/features/home/home_dashboard_cards.dart';
import 'package:iqro_mobile/features/home/home_dashboard_layout.dart';
import 'package:iqro_mobile/features/home/home_plan_progress.dart';
import 'package:iqro_mobile/features/home/home_section_tiles.dart';
import 'package:iqro_mobile/features/home/home_sky_card.dart';
import 'package:iqro_mobile/features/plan/plan_repository.dart';
import 'package:iqro_mobile/features/prayer/prayer_repository.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

// Ids of the shared line icons, titled as themselves.
const _sections = [
  'mushaf',
  'dua',
  'courses',
  'memorization',
  'qibla',
  'favorites',
  'calendar',
  'notes',
  'all',
];

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required double width,
  double height = 1400,
  String locale = 'ru',
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final clock = DateTime(2026, 10, 27, 11, 30);
  DateTime at(int hour, int minute) => DateTime(2026, 10, 27, hour, minute);
  await tester.pumpWidget(
    MaterialApp(
      theme: IqroTheme.light(),
      locale: Locale(locale),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: IqroPage(
          tabletContentWidth: homeTabletContentWidth,
          child: HomeDashboardLayout(
            prayer: HomePrayerSkyCard(
              schedule: PrayerSchedule(
                date: clock,
                timezone: 'Europe/Moscow',
                times: {
                  'fajr': at(6, 2),
                  'sunrise': at(7, 49),
                  'dhuhr': at(12, 21),
                  'asr': at(14, 30),
                  'maghrib': at(16, 50),
                  'isha': at(18, 31),
                },
                timesUtc: const {},
                methodName: 'test',
                warnings: const [],
              ),
              loading: false,
              clock: clock,
              onTap: () {},
              onQibla: () {},
              onReminders: () {},
            ),
            reading: HomeContinueReadingCard(
              surahName: 'Аль-Мульк',
              ayah: 1,
              page: 562,
              onTap: () {},
              footer: HomePlanProgress(
                achieved: 4,
                target: 10,
                metric: ReadingGoalMetric.pages,
                loading: false,
                error: false,
                onTap: () {},
              ),
            ),
            sections: HomeSectionTiles(
              tiles: [
                for (final title in _sections)
                  HomeSectionTile(id: title, title: title, onTap: () {}),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Rect _tile(WidgetTester tester, String id) =>
    tester.getRect(find.byKey(ValueKey('home-section-$id')));

void main() {
  testWidgets('a phone shows the sky, the reading and three tiles a row', (
    tester,
  ) async {
    await _pumpDashboard(tester, width: 400);

    expect(tester.takeException(), isNull);
    final prayer = tester.getRect(find.byKey(const ValueKey('home-prayer')));
    final reading = tester.getRect(find.byKey(const ValueKey('home-reading')));
    final plan = tester.getRect(find.byKey(const ValueKey('home-plan')));
    expect(reading.top, greaterThan(prayer.bottom));
    expect(prayer.width, 400 - 32);
    // The day's plan sits inside the reading card.
    expect(reading.contains(plan.center), isTrue);
    expect(_tile(tester, 'mushaf').top, _tile(tester, 'courses').top);
    expect(
      _tile(tester, 'memorization').top,
      greaterThan(_tile(tester, 'mushaf').bottom),
    );
    expect(_tile(tester, 'mushaf').top, greaterThan(reading.bottom));
  });

  testWidgets('the mark travels to the day\'s share of the plan', (
    tester,
  ) async {
    await _pumpDashboard(tester, width: 400);

    final plan = tester.getRect(find.byKey(const ValueKey('home-plan')));
    final mark = tester.getRect(find.byKey(const ValueKey('home-plan-mark')));
    // 4 of 10 pages: well before the middle of the bar, past its start.
    expect(mark.center.dx, greaterThan(plan.left + 40));
    expect(mark.center.dx, lessThan(plan.center.dx));
  });

  testWidgets('large text puts two wide tiles a row', (tester) async {
    await _pumpDashboard(tester, width: 400, scale: 1.8, height: 2400);

    expect(tester.takeException(), isNull);
    expect(_tile(tester, 'mushaf').top, _tile(tester, 'dua').top);
    expect(
      _tile(tester, 'courses').top,
      greaterThan(_tile(tester, 'mushaf').bottom),
    );
  });

  testWidgets('a wide tablet lays the tiles in one row', (tester) async {
    await _pumpDashboard(tester, width: 1000);

    expect(tester.takeException(), isNull);
    for (final title in _sections) {
      expect(_tile(tester, title).top, _tile(tester, 'mushaf').top);
    }
    final prayer = tester.getRect(find.byKey(const ValueKey('home-prayer')));
    expect(prayer.width, 1000 - 32);
  });

  testWidgets('right-to-left tiles start at the right edge', (tester) async {
    await _pumpDashboard(tester, width: 400, locale: 'ar');

    expect(tester.takeException(), isNull);
    expect(_tile(tester, 'mushaf').right, 400 - 16);
    expect(_tile(tester, 'courses').left, 16);
  });

  testWidgets('a landscape tablet uses its width up to the limit', (
    tester,
  ) async {
    // Pixel Tablet in landscape.
    await _pumpDashboard(tester, width: 1280, height: 800);

    expect(tester.takeException(), isNull);
    final reading = tester.getRect(find.byKey(const ValueKey('home-reading')));
    expect(reading.width, homeTabletContentWidth - 32);
    expect(reading.center.dx, 640);
  });

  testWidgets('a landscape phone keeps its centered column', (tester) async {
    // Redmi Note 7 turned to landscape.
    await _pumpDashboard(tester, width: 851, height: 393);

    expect(tester.takeException(), isNull);
    final reading = tester.getRect(find.byKey(const ValueKey('home-reading')));
    expect(reading.width, iqroLandscapeContentWidth - 32);
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
