import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:iqro_mobile/app/app_shell.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/app/router.dart';
import 'package:iqro_mobile/core/audio/audio_controller.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/auth/auth_session.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/core/widgets/home_widget_routes.dart';
import 'package:iqro_mobile/features/plan/plan_repository.dart';
import 'package:iqro_mobile/features/plan/plan_screen.dart';
import 'package:iqro_mobile/features/prayer/prayer_screen.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

void main() {
  setUpAll(initializeDateFormatting);
  for (final locale in ['ru', 'en', 'ar', 'tr']) {
    testWidgets('$locale widget routes keep navigation on cold and repeat taps', (
      tester,
    ) async {
      final router = createRouter(onboardingComplete: true);
      addTearDown(router.dispose);
      // Cold start receives the raw native URI, before the plugin maps it.
      router.go('iqro://open/plan?homeWidget');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith((ref) => _SignedOut()),
            audioControllerProvider.overrideWith((ref) => _IdleAudio()),
            localDatabaseProvider.overrideWithValue(_Database()),
            activeAccountScopeKeyProvider.overrideWithValue(null),
            planProvider.overrideWith((ref) => _UnavailablePlan()),
            prayerMethodsProvider.overrideWith((ref) async => []),
          ],
          child: MaterialApp.router(
            theme: IqroTheme.light(),
            routerConfig: router,
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PlanScreen), findsOneWidget);
      expect(router.routerDelegate.currentConfiguration.error, isNull);
      await _platformLink(tester, 'iqro://open/prayer?homeWidget');
      expect(find.byType(PrayerScreen), findsOneWidget);
      expect(find.byType(NavigationBar), findsOneWidget);
      final l10n = AppLocalizations.of(tester.element(find.byType(AppShell)));
      for (var attempt = 0; attempt < 2; attempt++) {
        router.go(
          homeWidgetRoute(Uri.parse('iqro://open/after-prayer?homeWidget'))!,
        );
        await tester.pumpAndSettle();
        expect(find.byType(AfterPrayerScreen), findsOneWidget);
        expect(find.byType(NavigationBar), findsOneWidget);
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(l10n.navPlan),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          router.routeInformationProvider.value.uri.toString(),
          '/app?tab=2',
        );
        expect(find.byType(PlanScreen), findsOneWidget);
        expect(find.byType(AfterPrayerScreen), findsNothing);
        expect(find.byType(NavigationBar), findsOneWidget);
        // The plugin and Flutter's native-link handler can fire in either order.
        for (final nativeUri in [
          'iqro://open/plan?homeWidget',
          '/plan?homeWidget',
        ]) {
          router.go('/prayer');
          await tester.pumpAndSettle();
          router.go(homeWidgetRoute(Uri.parse('iqro://open/plan?homeWidget'))!);
          await _platformLink(tester, nativeUri);
          expect(find.byType(PlanScreen), findsOneWidget);
          expect(find.byType(NavigationBar), findsOneWidget);
          expect(router.routerDelegate.currentConfiguration.error, isNull);
          await _platformLink(tester, nativeUri);
          router.go(homeWidgetRoute(Uri.parse('iqro://open/plan?homeWidget'))!);
          await tester.pumpAndSettle();
          expect(find.byType(PlanScreen), findsOneWidget);
          expect(router.routerDelegate.currentConfiguration.error, isNull);
        }
        await _platformLink(tester, 'iqro://open/after-prayer?homeWidget');
        expect(find.byType(AfterPrayerScreen), findsOneWidget);
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  }
}

Future<void> _platformLink(WidgetTester tester, String uri) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(
      MethodCall('pushRouteInformation', {'location': uri}),
    ),
    (_) {},
  );
  await tester.pumpAndSettle();
}

class _SignedOut extends StateNotifier<AsyncValue<AuthSession?>>
    implements SessionController {
  _SignedOut() : super(const AsyncData(null));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IdleAudio extends StateNotifier<IqroAudioState>
    implements AudioController {
  _IdleAudio() : super(const IqroAudioState());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnavailablePlan extends StateNotifier<AsyncValue<DailyPlan>>
    implements PlanController {
  _UnavailablePlan()
    : super(AsyncError(StateError('offline'), StackTrace.empty));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Database implements LocalDatabase {
  @override
  final accountScope = AccountScope();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
