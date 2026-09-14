import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/more/more_screen.dart';
import 'package:iqro_mobile/features/home/home_dashboard_cards.dart';
import 'package:iqro_mobile/core/design_system/iqro_action_grid.dart';
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
                              HomePrayerCard(
                                schedule: PrayerSchedule(
                                  date: clock,
                                  timezone: 'Europe/Istanbul',
                                  times: {'fajr': DateTime(2026, 9, 14, 5, 7)},
                                  timesUtc: const {},
                                  methodName: 'test',
                                  warnings: const [],
                                ),
                                loading: false,
                                clock: clock,
                                onTap: () => actions.add('prayer'),
                                onReminders: () => actions.add('reminders'),
                              ),
                              HomeContinueReadingCard(
                                surahName: 'Аль-Мутаффифин',
                                ayah: 1,
                                page: 587,
                                onTap: () => actions.add('read'),
                                onBookmarks: () => actions.add('bookmarks'),
                              ),
                              HomePlanCard(
                                achieved: 10,
                                target: 12,
                                metric: ReadingGoalMetric.pages,
                                loading: false,
                                error: false,
                                onTap: () => actions.add('plan'),
                              ),
                              IqroActionGrid(
                                children: [
                                  HomeFeatureCard(
                                    icon: Icons.school_outlined,
                                    title: l10n.memorization,
                                    subtitle: l10n.memorizationCreatePlan,
                                    onTap: () => actions.add('memorization'),
                                  ),
                                  HomeFeatureCard(
                                    icon: Icons.headphones_outlined,
                                    title: l10n.navAudio,
                                    subtitle: 'Ясир ад-Дусари',
                                    onTap: () => actions.add('audio'),
                                    action: IconButton.filledTonal(
                                      key: const ValueKey('play'),
                                      onPressed: () => actions.add('play'),
                                      icon: const Icon(
                                        Icons.play_arrow_rounded,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              HomeUtilityRow(
                                icon: Icons.calendar_month_outlined,
                                title: l10n.hijriCalendar,
                                subtitle: '3 Раби ас-сани 1448',
                                onTap: () => actions.add('calendar'),
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
            expect(find.text('05:07'), findsOneWidget);
            final context = tester.element(find.byType(HomePrayerCard));
            final l10n = AppLocalizations.of(context);
            expect(find.text(l10n.homePrayerIn('1:00')), findsOneWidget);
            for (final label in [
              l10n.read,
              l10n.bookmarks,
              l10n.dailyGoal,
              l10n.hijriCalendar,
            ]) {
              final target = find.text(label);
              await tester.ensureVisible(target);
              await tester.pumpAndSettle();
              await tester.tap(target);
              await tester.pump();
            }
            await tester.ensureVisible(find.byKey(const ValueKey('play')));
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const ValueKey('play')));
            expect(actions, ['read', 'bookmarks', 'plan', 'calendar', 'play']);
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
            await tester.tap(
              find.text(AppLocalizations.of(context).hijriCalendar),
            );
            await tester.pumpAndSettle();
            expect(find.text('calendar-opened'), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
