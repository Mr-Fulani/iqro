import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/more/more_screen.dart';
import 'package:iqro_mobile/features/home/home_dashboard_cards.dart';
import 'package:iqro_mobile/features/home/home_plan_walker.dart';
import 'package:iqro_mobile/features/home/home_section_tiles.dart';
import 'package:iqro_mobile/features/home/home_sky_card.dart';
import 'package:iqro_mobile/features/plan/plan_repository.dart';
import 'package:iqro_mobile/features/prayer/prayer_repository.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

void main() {
  for (final locale in ['ru', 'en', 'ar', 'tr']) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.8]) {
        testWidgets(
          '$locale dark=$dark scale=$scale Home cards fit and actions work',
          (tester) async {
            tester.view.physicalSize = const Size(360, 900);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final actions = <String>[];
            final clock = DateTime(2026, 9, 14, 4, 7);
            DateTime at(int hour, int minute) =>
                DateTime(2026, 9, 14, hour, minute);
            await tester.pumpWidget(
              MaterialApp(
                theme: dark ? IqroTheme.dark() : IqroTheme.light(),
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
                  body: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Builder(
                        builder: (context) {
                          final l10n = AppLocalizations.of(context);
                          return Column(
                            children: [
                              HomePrayerSkyCard(
                                schedule: PrayerSchedule(
                                  date: clock,
                                  timezone: 'Europe/Istanbul',
                                  times: {
                                    'fajr': at(5, 7),
                                    'sunrise': at(6, 40),
                                    'dhuhr': at(13, 5),
                                    'asr': at(16, 30),
                                    'maghrib': at(19, 20),
                                    'isha': at(20, 40),
                                  },
                                  timesUtc: const {},
                                  methodName: 'test',
                                  warnings: const [],
                                ),
                                loading: false,
                                clock: clock,
                                onTap: () => actions.add('prayer'),
                                onQibla: () => actions.add('qibla'),
                                onReminders: () => actions.add('reminders'),
                              ),
                              HomeContinueReadingCard(
                                surahName: 'Аль-Мутаффифин',
                                ayah: 1,
                                page: 587,
                                onTap: () => actions.add('read'),
                                footer: HomePlanWalker(
                                  achieved: 10,
                                  target: 12,
                                  metric: ReadingGoalMetric.pages,
                                  loading: false,
                                  error: false,
                                  onTap: () => actions.add('plan'),
                                ),
                              ),
                              HomeSectionTiles(
                                tiles: [
                                  for (final (id, art, title) in [
                                    ('dua', 'dua', l10n.dua),
                                    ('qibla', 'qibla', l10n.qibla),
                                    (
                                      'calendar',
                                      'hijri-calendar',
                                      l10n.hijriCalendar,
                                    ),
                                    ('all', 'sections', l10n.homeAllSections),
                                  ])
                                    HomeSectionTile(
                                      id: id,
                                      art: art,
                                      title: title,
                                      color: Colors.white,
                                      onTap: () => actions.add(id),
                                    ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final context = tester.element(find.byType(HomePrayerSkyCard));
            final l10n = AppLocalizations.of(context);
            expect(find.text('${l10n.fajr} 05:07'), findsOneWidget);
            expect(find.text(l10n.homePrayerIn('1:00')), findsOneWidget);
            Future<void> tap(Finder target) async {
              await tester.ensureVisible(target);
              await tester.pumpAndSettle();
              await tester.tap(target);
              await tester.pump();
            }

            await tap(find.text('${l10n.fajr} 05:07'));
            await tap(find.byKey(const ValueKey('home-prayer-qibla')));
            await tap(find.byKey(const ValueKey('home-prayer-reminders')));
            await tap(find.text(l10n.read));
            await tap(find.text(l10n.dailyGoal));
            for (final id in ['dua', 'qibla', 'calendar', 'all']) {
              await tap(find.byKey(ValueKey('home-section-$id')));
            }
            expect(actions, [
              'prayer',
              'qibla',
              'reminders',
              'read',
              'plan',
              'dua',
              'qibla',
              'calendar',
              'all',
            ]);
            expect(tester.takeException(), isNull);
          },
        );
        testWidgets(
          '$locale dark=$dark scale=$scale More cards fit and calendar opens',
          (tester) async {
            tester.view.physicalSize = Size(scale == 1 ? 360 : 320, 900);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final router = GoRouter(
              routes: [
                GoRoute(
                  path: '/',
                  builder: (_, _) => const Scaffold(
                    body: SingleChildScrollView(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: MoreToolsGrid(),
                      ),
                    ),
                  ),
                ),
                GoRoute(
                  path: '/calendar',
                  builder: (_, _) =>
                      const Scaffold(body: Text('calendar-opened')),
                ),
                GoRoute(
                  path: '/notes',
                  builder: (_, _) => const Scaffold(body: Text('notes-opened')),
                ),
              ],
            );
            addTearDown(router.dispose);
            await tester.pumpWidget(
              MaterialApp.router(
                routerConfig: router,
                theme: dark ? IqroTheme.dark() : IqroTheme.light(),
                locale: Locale(locale),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
              ),
            );
            await tester.pumpAndSettle();
            final context = tester.element(find.byType(MoreToolsGrid));
            final l10n = AppLocalizations.of(context);
            expect(find.text(l10n.notes), findsOneWidget);
            final names = find.byKey(const ValueKey('more-names-of-allah'));
            await tester.ensureVisible(names);
            await tester.pumpAndSettle();
            for (final text in <String>[l10n.namesOfAllah, l10n.soon]) {
              expect(
                find.descendant(of: names, matching: find.text(text)),
                findsOneWidget,
              );
            }
            await tester.tap(names);
            await tester.pumpAndSettle();
            expect(find.byType(MoreToolsGrid), findsOneWidget);
            final notes = find.text(l10n.notes);
            await tester.ensureVisible(notes);
            await tester.pumpAndSettle();
            await tester.tap(notes);
            await tester.pumpAndSettle();
            expect(find.text('notes-opened'), findsOneWidget);
            router.go('/');
            await tester.pumpAndSettle();
            final calendar = find.text(l10n.hijriCalendar);
            await tester.ensureVisible(calendar);
            await tester.pumpAndSettle();
            await tester.tap(calendar);
            await tester.pumpAndSettle();
            expect(find.text('calendar-opened'), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
