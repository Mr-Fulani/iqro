import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/home/home_dashboard_cards.dart';
import 'package:iqro_mobile/features/plan/palm_growth.dart';
import 'package:iqro_mobile/features/plan/palm_growth_view.dart';
import 'package:iqro_mobile/features/plan/plan_repository.dart';
import 'package:iqro_mobile/features/plan/plan_widget_service.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:timezone/data/latest.dart' as tz_data;

const _today = '2026-09-14';

ReadingHistoryDay _day(int daysAgo, String state, {bool? hasReading}) =>
    ReadingHistoryDay(
      localDate: DateTime.utc(2026, 9, 14).subtract(Duration(days: daysAgo)),
      state: state,
      hasReading: hasReading ?? (state == 'completed' || state == 'partial'),
      metric: ReadingGoalMetric.pages,
      target: 6,
      achieved: state == 'completed' ? 6 : 0,
      automaticSeconds: 0,
      automaticPages: 0,
      automaticAyahs: 0,
      prayerPages: 0,
    );

DailyPlan _plan({
  double achieved = 0,
  int streak = 0,
  int longestStreak = 0,
  List<ReadingHistoryDay> history = const <ReadingHistoryDay>[],
}) => DailyPlan(
  metric: ReadingGoalMetric.pages,
  target: 6,
  achieved: achieved,
  prayerPages: const <String, int>{},
  streak: streak,
  longestStreak: longestStreak,
  localDate: _today,
  timezoneName: 'Europe/Istanbul',
  history: history,
);

void main() {
  group('palm growth rules', () {
    test('a new reader starts with a seed waiting to be planted', () {
      final growth = palmGrowthFor(_plan());
      expect(growth.stage, PalmStage.seed);
      expect(growth.mood, PalmMood.planting);
      expect(growth.points, 0);
      expect(growth.nextStage, PalmStage.sprout);
    });

    test('reading today sprouts the seed at once', () {
      final partial = palmGrowthFor(_plan(achieved: 2));
      expect(partial.stage, PalmStage.sprout);
      expect(partial.mood, PalmMood.growing);
      expect(partial.points, 1);

      final complete = palmGrowthFor(_plan(achieved: 6));
      expect(complete.mood, PalmMood.flourishing);
      expect(complete.points, 2);
    });

    test('a completed goal is worth two points, a reading day one', () {
      final growth = palmGrowthFor(
        _plan(
          streak: 3,
          history: [
            _day(1, 'completed'),
            _day(2, 'partial'),
            _day(3, 'completed'),
            _day(4, 'no_goal', hasReading: true),
            _day(5, 'missed'),
          ],
        ),
      );
      expect(growth.points, 6);
      expect(growth.stage, PalmStage.seedling);
      expect(growth.mood, PalmMood.waiting);
    });

    test('today is counted from the live goal, never twice', () {
      final growth = palmGrowthFor(
        _plan(achieved: 6, history: [_day(0, 'completed')]),
      );
      expect(growth.points, 2);
    });

    test('missed days never take growth away; the palm only rests', () {
      final steady = [for (var i = 1; i <= 8; i++) _day(i, 'completed')];
      final before = palmGrowthFor(_plan(streak: 8, history: steady));
      final after = palmGrowthFor(
        _plan(
          history: [
            for (var i = 1; i <= 5; i++) _day(i, 'missed'),
            for (var i = 6; i <= 13; i++) _day(i, 'completed'),
          ],
        ),
      );
      expect(before.stage, PalmStage.youngPalm);
      expect(after.stage, before.stage);
      expect(after.points, before.points);
      expect(after.mood, PalmMood.resting);
    });

    test('the longest streak keeps a grown palm after a long pause', () {
      final growth = palmGrowthFor(_plan(longestStreak: 30));
      expect(growth.stage, PalmStage.fruitingPalm);
      expect(growth.mood, PalmMood.resting);
      expect(palmGrowthFor(_plan(longestStreak: 1)).stage, PalmStage.sprout);
      expect(palmGrowthFor(_plan(longestStreak: 7)).stage, PalmStage.youngPalm);
    });

    test('only the 90-day planner window counts', () {
      final growth = palmGrowthFor(
        _plan(history: [_day(89, 'completed'), _day(90, 'completed')]),
      );
      expect(growth.points, 2);
    });

    test('stage thresholds and progress to the next stage', () {
      List<ReadingHistoryDay> completed(int days) => [
        for (var i = 1; i <= days; i++) _day(i, 'completed'),
      ];
      expect(
        palmGrowthFor(_plan(history: completed(8))).stage,
        PalmStage.youngPalm,
      );
      expect(
        palmGrowthFor(_plan(history: completed(16))).stage,
        PalmStage.palm,
      );
      final top = palmGrowthFor(_plan(history: completed(28)));
      expect(top.stage, PalmStage.fruitingPalm);
      expect(top.nextStage, isNull);
      expect(top.progressToNext, 1);
      final halfway = palmGrowthFor(_plan(history: completed(12)));
      expect(halfway.stage, PalmStage.youngPalm);
      expect(halfway.progressToNext, closeTo(0.5, 0.001));
    });

    test('every stage and mood has text in every language', () {
      for (final locale in AppLocalizations.supportedLocales) {
        final l10n = lookupAppLocalizations(locale);
        for (final stage in PalmStage.values) {
          expect(palmStageLabel(l10n, stage), isNotEmpty);
        }
        for (final mood in PalmMood.values) {
          expect(palmMoodLabel(l10n, mood), isNotEmpty);
        }
      }
    });
  });

  group('palm rendering', () {
    for (final stage in PalmStage.values) {
      testWidgets('${stage.name} paints and settles to rest', (tester) async {
        await tester.pumpWidget(
          Center(
            child: PalmGrowthArt(stage: stage, mood: PalmMood.growing),
          ),
        );
        expect(tester.hasRunningAnimations, isTrue);
        await tester.pumpAndSettle();
        final painter = _painter(tester);
        expect(painter.stage, stage);
        expect(painter.growth, 1);
        expect(painter.sway, 0);
        expect(
          find.byType(PalmGrowthArt),
          paints
            ..circle(color: PalmColors.mint.withValues(alpha: .75))
            ..path(),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('reduced motion draws the grown palm without animating', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Center(
            child: PalmGrowthArt(
              stage: PalmStage.palm,
              mood: PalmMood.flourishing,
            ),
          ),
        ),
      );
      expect(tester.hasRunningAnimations, isFalse);
      expect(_painter(tester).growth, 1);
      expect(_painter(tester).sway, 0);
    });

    testWidgets('a new stage grows again', (tester) async {
      Widget art(PalmStage stage) => Center(
        child: PalmGrowthArt(stage: stage, mood: PalmMood.growing),
      );
      await tester.pumpWidget(art(PalmStage.sprout));
      await tester.pumpAndSettle();
      await tester.pumpWidget(art(PalmStage.seedling));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      expect(_painter(tester).stage, PalmStage.seedling);
    });

    testWidgets('resting shows a crescent instead of a wilted palm', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Center(
            child: PalmGrowthArt(stage: PalmStage.palm, mood: PalmMood.resting),
          ),
        ),
      );
      expect(
        find.byType(PalmGrowthArt),
        paints
          ..circle(color: PalmColors.dusk.withValues(alpha: .75))
          ..path(color: PalmColors.gold),
      );
    });

    test('painter repaints only when its input changes', () {
      const base = PalmPainter(stage: PalmStage.palm, mood: PalmMood.growing);
      expect(
        base.shouldRepaint(
          const PalmPainter(stage: PalmStage.palm, mood: PalmMood.growing),
        ),
        isFalse,
      );
      expect(
        base.shouldRepaint(
          const PalmPainter(stage: PalmStage.palm, mood: PalmMood.resting),
        ),
        isTrue,
      );
      expect(
        base.shouldRepaint(
          const PalmPainter(
            stage: PalmStage.palm,
            mood: PalmMood.growing,
            sway: .05,
          ),
        ),
        isTrue,
      );
    });

    for (final locale in ['ru', 'en', 'ar', 'tr']) {
      testWidgets('$locale plan card names the stage and the way ahead', (
        tester,
      ) async {
        final growth = palmGrowthFor(
          _plan(achieved: 2, history: [_day(1, 'completed')]),
        );
        await tester.pumpWidget(_app(locale, PalmGrowthCard(growth: growth)));
        await tester.pumpAndSettle();
        final l10n = lookupAppLocalizations(Locale(locale));
        expect(find.text(l10n.palmStageSprout), findsOneWidget);
        expect(find.text(l10n.palmMoodGrowing), findsOneWidget);
        expect(
          find.text(l10n.palmNextStage(l10n.palmStageSeedling)),
          findsOneWidget,
        );
        expect(find.bySemanticsLabel(l10n.palmStageSprout), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a fully grown palm has no next stage bar', (tester) async {
      final growth = palmGrowthFor(_plan(longestStreak: 40));
      await tester.pumpWidget(_app('ru', PalmGrowthCard(growth: growth)));
      await tester.pumpAndSettle();
      final l10n = lookupAppLocalizations(const Locale('ru'));
      expect(find.text(l10n.palmFullyGrown), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('home plan card shows the palm once the plan is loaded', (
      tester,
    ) async {
      Widget card(PalmGrowth? palm) => _app(
        'ru',
        HomePlanCard(
          achieved: 2,
          target: 6,
          metric: ReadingGoalMetric.pages,
          loading: palm == null,
          error: false,
          palm: palm,
          onTap: () {},
        ),
      );
      await tester.pumpWidget(card(null));
      expect(find.byType(PalmGrowthArt), findsNothing);
      expect(find.byIcon(Icons.track_changes_rounded), findsOneWidget);

      await tester.pumpWidget(card(palmGrowthFor(_plan(achieved: 2))));
      await tester.pumpAndSettle();
      expect(find.byType(PalmGrowthArt), findsOneWidget);
      expect(find.byIcon(Icons.track_changes_rounded), findsNothing);
    });
  });

  group('home-screen widget', () {
    setUpAll(tz_data.initializeTimeZones);

    test('snapshot carries the static palm stage and its label', () {
      final snapshot = buildPlanWidgetSnapshot(
        plan: _plan(achieved: 6, longestStreak: 14),
        locale: 'ru',
        now: DateTime.utc(2026, 9, 14, 10),
      );
      expect(snapshot['palmStage'], PalmStage.palm.index);
      expect(
        snapshot['palmLabel'],
        lookupAppLocalizations(const Locale('ru')).palmStagePalm,
      );
    });

    test('every stage has rendered widget art', () {
      for (final stage in PalmStage.values) {
        final file = File(
          'android/app/src/main/res/drawable-nodpi/'
          'reading_plan_palm_${stage.index}.png',
        );
        expect(file.existsSync(), isTrue, reason: file.path);
      }
    });
  });
}

PalmPainter _painter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byType(PalmGrowthArt),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!
        as PalmPainter;

Widget _app(String locale, Widget child) => MaterialApp(
  theme: IqroTheme.light(),
  locale: Locale(locale),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);
