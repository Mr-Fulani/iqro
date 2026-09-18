import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/plan/plan_repository.dart';
import 'package:iqro_mobile/features/plan/plan_screen.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

void main() {
  setUpAll(initializeDateFormatting);
  for (final locale in ['ru', 'en', 'ar', 'tr']) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          '$locale dark=$dark scale=$scale separates credited pages from target',
          (tester) async {
            tester.view.physicalSize = const Size(360, 900);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final database = _Database();
            final scope = database.accountScope.current!;
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  localDatabaseProvider.overrideWithValue(database),
                  activeAccountScopeKeyProvider.overrideWithValue(
                    accountScopeKey(scope),
                  ),
                  audioControllerProvider.overrideWith((ref) => _IdleAudio()),
                  planProvider.overrideWith((ref) => _Plan()),
                ],
                child: MaterialApp(
                  theme: dark ? IqroTheme.dark() : IqroTheme.light(),
                  locale: Locale(locale),
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: TextScaler.linear(scale)),
                    child: child!,
                  ),
                  home: const PlanScreen(),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final l10n = AppLocalizations.of(
              tester.element(find.byType(PlanScreen)),
            );
            expect(find.text(l10n.planCreditedToday), findsOneWidget);
            expect(find.text(l10n.planGoalLabel), findsOneWidget);
            expect(find.text(l10n.planPages(13)), findsOneWidget);
            expect(find.text(l10n.planPages(1)), findsOneWidget);
            expect(find.text(l10n.planGoalReached), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.ensureVisible(find.text(l10n.planHowCounted));
            await tester.tap(find.text(l10n.planHowCounted));
            await tester.pumpAndSettle();
            expect(find.text(l10n.planPagesHelp), findsOneWidget);
            expect(find.text(l10n.planDailyHelp), findsOneWidget);
            expect(find.text(l10n.planResetHelp), findsOneWidget);
            await tester.ensureVisible(find.text(l10n.planEditGoal));
            await tester.tap(find.text(l10n.planEditGoal));
            await tester.pumpAndSettle();
            expect(find.text(l10n.planGoalHint), findsOneWidget);
            final minutes = find.widgetWithText(ChoiceChip, l10n.minutes);
            await tester.ensureVisible(minutes);
            await tester.tap(minutes);
            await tester.pumpAndSettle();
            expect(tester.widget<ChoiceChip>(minutes).selected, isTrue);
            expect(tester.takeException(), isNull);
            final cancel = find.widgetWithText(OutlinedButton, l10n.cancel);
            await tester.ensureVisible(cancel);
            await tester.tap(cancel);
            await tester.pumpAndSettle();
            expect(find.text(l10n.planPages(13)), findsOneWidget);
          },
        );
      }
    }
  }
}

class _Plan extends StateNotifier<AsyncValue<DailyPlan>>
    implements PlanController {
  _Plan()
    : super(
        AsyncData(const DailyPlan.initial(target: 1).copyWith(achieved: 13)),
      );
  @override
  bool isBoundTo(AccountScopeSnapshot scope) => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Database implements LocalDatabase {
  @override
  final accountScope = AccountScope.forTesting();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IdleAudio extends StateNotifier<IqroAudioState>
    implements AudioController {
  _IdleAudio() : super(const IqroAudioState());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
