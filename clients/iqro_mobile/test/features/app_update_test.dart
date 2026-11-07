import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/platform/play_app_update.dart';
import 'package:iqro_mobile/core/storage/preferences_store.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/app_update/app_release_source.dart';
import 'package:iqro_mobile/features/app_update/app_update_card.dart';
import 'package:iqro_mobile/features/app_update/app_update_controller.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

PlayUpdateInfo _info({
  bool available = true,
  PlayInstallStatus status = PlayInstallStatus.unknown,
  int versionCode = 3,
  int priority = 0,
}) => PlayUpdateInfo(
  available: available,
  installStatus: status,
  versionCode: versionCode,
  priority: priority,
  flexibleAllowed: available,
);

class _FakeGateway implements AppUpdateGateway {
  _FakeGateway(this.info);

  /// Null: the build was not installed from Play.
  PlayUpdateInfo? info;
  var checks = 0;
  var starts = 0;
  var completes = 0;
  var acceptStart = true;
  final statuses = StreamController<PlayInstallStatus>.broadcast();

  @override
  Future<PlayUpdateInfo?> check() async {
    checks++;
    return info;
  }

  @override
  Future<bool> startFlexibleUpdate() async {
    starts++;
    return acceptStart;
  }

  @override
  Future<void> completeUpdate() async => completes++;

  var storeOpens = 0;

  @override
  Future<bool> openStorePage() async {
    storeOpens++;
    return true;
  }

  @override
  Stream<PlayInstallStatus> get installStatus => statuses.stream;
}

class _FakeRelease implements AppReleaseSource {
  _FakeRelease({this.latest});

  /// What the admin names; null: unknown or «не проверять».
  int? latest;
  final int installed = 6;
  var asks = 0;

  @override
  Future<int?> latestAndroidVersionCode() async {
    asks++;
    return latest;
  }

  @override
  Future<int?> installedVersionCode() async => installed;
}

Future<PreferencesStore> _store() async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return PreferencesStore(await SharedPreferences.getInstance());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  var now = DateTime(2026, 10, 27, 9);
  setUp(() => now = DateTime(2026, 10, 27, 9));

  AppUpdateController controller(
    _FakeGateway gateway,
    PreferencesStore store, {
    int mandatoryPriority = 0,
    AppReleaseSource? release,
  }) => AppUpdateController(
    gateway,
    store,
    release: release,
    now: () => now,
    mandatoryPriority: mandatoryPriority,
  );

  group('AppUpdateController', () {
    test('asks Play at most once every 30 minutes, across launches', () async {
      final store = await _store();
      final gateway = _FakeGateway(_info(available: false));
      final first = controller(gateway, store);
      await first.checkIfDue();
      now = now.add(const Duration(minutes: 29));
      await first.checkIfDue();
      // A new launch reads the same record.
      await controller(gateway, store).checkIfDue();
      expect(gateway.checks, 1);

      now = now.add(const Duration(minutes: 1));
      await controller(gateway, store).checkIfDue();
      expect(gateway.checks, 2);
    });

    test('a clock moved back does not block checks', () async {
      final store = await _store();
      final gateway = _FakeGateway(_info(available: false));
      await controller(gateway, store).checkIfDue();
      now = now.subtract(const Duration(hours: 2));
      await controller(gateway, store).checkIfDue();
      expect(gateway.checks, 2);
    });

    test('offers a new version', () async {
      final store = await _store();
      final updates = controller(_FakeGateway(_info()), store);
      await updates.checkIfDue();
      expect(updates.state.stage, AppUpdateStage.offer);
      expect(updates.state.versionCode, 3);
      expect(updates.state.mandatory, isFalse);
    });

    test('outside Play nothing is shown and nothing fails', () async {
      final store = await _store();
      final gateway = _FakeGateway(null);
      final updates = controller(gateway, store);
      await updates.checkIfDue();
      expect(updates.state.stage, AppUpdateStage.none);
      // Still throttled, not asked on every return to the app.
      await updates.checkIfDue();
      expect(gateway.checks, 1);
    });

    test('the disabled controller (iOS) never asks', () async {
      final updates = AppUpdateController.disabled();
      await updates.checkIfDue();
      await updates.update();
      expect(updates.state.stage, AppUpdateStage.none);
    });

    test('«Позже» hides this version for three days', () async {
      final store = await _store();
      final gateway = _FakeGateway(_info());
      final updates = controller(gateway, store);
      await updates.checkIfDue();
      await updates.later();
      expect(updates.state.stage, AppUpdateStage.none);

      now = now.add(const Duration(days: 2));
      final later = controller(gateway, store);
      await later.checkIfDue();
      expect(gateway.checks, 2);
      expect(later.state.stage, AppUpdateStage.none);

      now = now.add(const Duration(days: 1));
      final again = controller(gateway, store);
      await again.checkIfDue();
      expect(again.state.stage, AppUpdateStage.offer);
    });

    test('«Позже» does not hide the next version', () async {
      final store = await _store();
      final gateway = _FakeGateway(_info());
      final updates = controller(gateway, store);
      await updates.checkIfDue();
      await updates.later();

      gateway.info = _info(versionCode: 4);
      now = now.add(const Duration(days: 1));
      final next = controller(gateway, store);
      await next.checkIfDue();
      expect(next.state.stage, AppUpdateStage.offer);
      expect(next.state.versionCode, 4);
    });

    test('a required update has no «Позже» and ignores it', () async {
      final store = await _store();
      final gateway = _FakeGateway(_info(priority: 4));
      final optional = controller(gateway, store);
      await optional.checkIfDue();
      expect(optional.state.mandatory, isFalse);

      now = now.add(const Duration(days: 1));
      final required = controller(gateway, store, mandatoryPriority: 4);
      await required.checkIfDue();
      expect(required.state.mandatory, isTrue);
      await required.later();
      expect(required.state.stage, AppUpdateStage.offer);
    });

    test('«Обновить» downloads, then offers the restart', () async {
      final store = await _store();
      final gateway = _FakeGateway(_info());
      final updates = controller(gateway, store);
      await updates.checkIfDue();
      await updates.update();
      expect(gateway.starts, 1);
      expect(updates.state.stage, AppUpdateStage.downloading);

      // Returning from Play's dialog resumes the app before Play reports
      // the download; the check is not held back by the daily interval.
      await updates.checkIfDue();
      expect(gateway.checks, 2);
      expect(updates.state.stage, AppUpdateStage.downloading);

      gateway.statuses.add(PlayInstallStatus.downloading);
      gateway.statuses.add(PlayInstallStatus.downloaded);
      await Future<void>.delayed(Duration.zero);
      expect(updates.state.stage, AppUpdateStage.readyToInstall);

      await updates.restart();
      expect(gateway.completes, 1);
    });

    test('a download finished while the app was closed', () async {
      final store = await _store();
      final gateway = _FakeGateway(_info());
      final updates = controller(gateway, store);
      await updates.checkIfDue();
      await updates.update();
      updates.dispose();

      gateway.info = _info(status: PlayInstallStatus.downloaded);
      now = now.add(const Duration(hours: 1));
      final next = controller(gateway, store);
      await next.checkIfDue();
      expect(next.state.stage, AppUpdateStage.readyToInstall);

      next.postponeRestart();
      expect(next.state.stage, AppUpdateStage.none);
      await next.checkIfDue();
      expect(next.state.stage, AppUpdateStage.none);
    });

    test('declined in Play\'s dialog counts as «Позже»', () async {
      final store = await _store();
      final gateway = _FakeGateway(_info())..acceptStart = false;
      final updates = controller(gateway, store);
      await updates.checkIfDue();
      await updates.update();
      expect(updates.state.stage, AppUpdateStage.none);

      now = now.add(const Duration(days: 1));
      final next = controller(gateway, store);
      await next.checkIfDue();
      expect(next.state.stage, AppUpdateStage.none);
    });

    test('a failed download clears the offer until the next check', () async {
      final store = await _store();
      final gateway = _FakeGateway(_info());
      final updates = controller(gateway, store);
      await updates.checkIfDue();
      await updates.update();
      gateway.statuses.add(PlayInstallStatus.failed);
      await Future<void>.delayed(Duration.zero);
      expect(updates.state.stage, AppUpdateStage.none);

      // No accepted download any more: the daily interval applies again.
      await updates.checkIfDue();
      expect(gateway.checks, 1);
    });

    test(
      'Play silent, the server knows a newer build: Google Play opens',
      () async {
        final store = await _store();
        final gateway = _FakeGateway(_info(available: false));
        final updates = controller(
          gateway,
          store,
          release: _FakeRelease(latest: 7),
        );
        await updates.checkIfDue();
        expect(updates.state.stage, AppUpdateStage.offer);
        expect(updates.state.viaStore, isTrue);
        expect(updates.state.versionCode, 7);

        await updates.update();
        expect(gateway.storeOpens, 1);
        expect(gateway.starts, 0);
        expect(updates.state.stage, AppUpdateStage.none);
      },
    );

    test('the server build is not newer: nothing is offered', () async {
      final store = await _store();
      for (final latest in <int?>[null, 5, 6]) {
        now = now.add(const Duration(hours: 1));
        final updates = controller(
          _FakeGateway(_info(available: false)),
          store,
          release: _FakeRelease(latest: latest),
        );
        await updates.checkIfDue();
        expect(updates.state.stage, AppUpdateStage.none, reason: '$latest');
      }
    });

    test('Play\'s own offer wins and the server is not asked', () async {
      final store = await _store();
      final release = _FakeRelease(latest: 7);
      final updates = controller(
        _FakeGateway(_info()),
        store,
        release: release,
      );
      await updates.checkIfDue();
      expect(updates.state.viaStore, isFalse);
      expect(release.asks, 0);
    });

    test('outside Play the server is not asked either', () async {
      final store = await _store();
      final release = _FakeRelease(latest: 7);
      final updates = controller(_FakeGateway(null), store, release: release);
      await updates.checkIfDue();
      expect(updates.state.stage, AppUpdateStage.none);
      expect(release.asks, 0);
    });

    test('«Позже» hides the server build for three days too', () async {
      final store = await _store();
      final release = _FakeRelease(latest: 7);
      final gateway = _FakeGateway(_info(available: false));
      final updates = controller(gateway, store, release: release);
      await updates.checkIfDue();
      await updates.later();
      expect(updates.state.stage, AppUpdateStage.none);

      now = now.add(const Duration(days: 1));
      final later = controller(gateway, store, release: release);
      await later.checkIfDue();
      expect(later.state.stage, AppUpdateStage.none);

      now = now.add(const Duration(days: 2));
      final again = controller(gateway, store, release: release);
      await again.checkIfDue();
      expect(again.state.viaStore, isTrue);
    });

    test('a damaged record is ignored', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'iqro_app_update_v1': '{not json',
      });
      final store = PreferencesStore(await SharedPreferences.getInstance());
      final updates = controller(_FakeGateway(_info()), store);
      await updates.checkIfDue();
      expect(updates.state.stage, AppUpdateStage.offer);
    });
  });

  group('AppUpdateCard', () {
    Future<_FakeGateway> pumpCard(
      WidgetTester tester, {
      required PlayUpdateInfo? info,
      int mandatoryPriority = 0,
      AppReleaseSource? release,
    }) async {
      final store = await _store();
      final gateway = _FakeGateway(info);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appUpdateProvider.overrideWith(
              (ref) => controller(
                gateway,
                store,
                mandatoryPriority: mandatoryPriority,
                release: release,
              ),
            ),
          ],
          child: MaterialApp(
            theme: IqroTheme.light(),
            locale: const Locale('ru'),
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: Column(
                  children: <Widget>[
                    TextButton(
                      onPressed: () =>
                          ref.read(appUpdateProvider.notifier).checkIfDue(),
                      child: const Text('check'),
                    ),
                    const AppUpdateCard(),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('check'));
      await tester.pumpAndSettle();
      return gateway;
    }

    testWidgets('a server build says it opens Google Play', (tester) async {
      final gateway = await pumpCard(
        tester,
        info: _info(available: false),
        release: _FakeRelease(latest: 7),
      );
      expect(find.text('Доступна новая версия IQRO'), findsOneWidget);
      expect(
        find.text(
          'Откроется страница IQRO в Google Play, там нажмите «Обновить».',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Открыть Google Play'));
      await tester.pumpAndSettle();
      expect(gateway.storeOpens, 1);
      expect(find.byKey(const ValueKey('app-update')), findsNothing);
    });

    testWidgets('shows nothing outside Play', (tester) async {
      await pumpCard(tester, info: null);
      expect(find.byKey(const ValueKey('app-update')), findsNothing);
    });

    testWidgets('«Позже» hides the card', (tester) async {
      await pumpCard(tester, info: _info());
      expect(find.text('Доступна новая версия IQRO'), findsOneWidget);
      await tester.tap(find.text('Позже'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('app-update')), findsNothing);
    });

    testWidgets('«Обновить», then «Перезапустить»', (tester) async {
      final gateway = await pumpCard(tester, info: _info());
      await tester.tap(find.text('Обновить'));
      // The loading bar never settles while Play downloads.
      await tester.pump(const Duration(milliseconds: 100));
      expect(gateway.starts, 1);
      expect(find.text('Обновление загружается'), findsOneWidget);
      expect(find.byKey(const ValueKey('app-update-progress')), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);

      gateway.statuses.add(PlayInstallStatus.downloaded);
      await tester.pumpAndSettle();
      expect(find.text('Обновление загружено'), findsOneWidget);
      await tester.tap(find.text('Перезапустить'));
      await tester.pumpAndSettle();
      expect(gateway.completes, 1);
    });

    testWidgets('shows the installed version', (tester) async {
      PackageInfo.setMockInitialValues(
        appName: 'IQRO',
        packageName: 'forum.iqro.app',
        version: '1.0.5',
        buildNumber: '6',
        buildSignature: '',
      );
      await pumpCard(tester, info: _info());
      expect(find.text('У вас 1.0.5 (6)'), findsOneWidget);
    });

    testWidgets('a required update has no «Позже»', (tester) async {
      await pumpCard(tester, info: _info(priority: 5), mandatoryPriority: 4);
      expect(find.text('Обновить'), findsOneWidget);
      expect(find.text('Позже'), findsNothing);
    });
  });
}
