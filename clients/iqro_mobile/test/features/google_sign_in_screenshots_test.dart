// Screenshots of "Continue with Google" for the pull request: the sign-in
// card of the profile, the signed-in profile with "Switch account" and the
// last onboarding step.
//
//   flutter test test/features/google_sign_in_screenshots_test.dart \
//     --dart-define=SCREENSHOT_DIR=/tmp/shots
//
// Real fonts come from the Flutter SDK (Roboto, Material icons) and macOS.
// Without SCREENSHOT_DIR the test is skipped: CI checks behaviour elsewhere.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/analytics/analytics.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/auth/auth_repository.dart';
import 'package:iqro_mobile/core/auth/auth_session.dart';
import 'package:iqro_mobile/core/auth/google_sign_in_gateway.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/notifications/notification_gateway.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/core/sync/sync_remote.dart';
import 'package:iqro_mobile/core/sync/sync_service.dart';
import 'package:iqro_mobile/core/sync/sync_store.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/account/account_screen.dart';
import 'package:iqro_mobile/features/onboarding/onboarding_screen.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'onboarding_test_support.dart';

const _directory = String.fromEnvironment('SCREENSHOT_DIR');
const _size = Size(1080, 2340); // Redmi Note 7
const _pixelRatio = 2.75;
final _boundary = GlobalKey();

const _config = AppConfig(
  apiBaseUrl: 'https://iqro.forum',
  fallbackDownloadUrl: 'https://iqro.forum',
  environment: 'production',
);

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

AuthSession _session({required bool verified}) => AuthSession(
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: DateTime.utc(2035),
  refreshExpiresAt: DateTime.utc(2036),
  bootstrapGeneration: 1,
  userId: 'account-a',
  userStatus: verified ? 'active' : 'guest',
  deviceId: 'device-a',
  email: verified ? 'reader@gmail.com' : null,
);

Future<
  ({LocalDatabase database, _ShotSessionController controller, Database raw})
>
_fixture(WidgetTester tester, AuthSession session) async {
  final raw = (await tester.runAsync(
    () => databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
  ))!;
  addTearDown(() => tester.runAsync(raw.close));
  final scope = AccountScope.forTesting('account-a');
  final database = LocalDatabase.forTesting(raw, accountScope: scope);
  final controller = _ShotSessionController(
    AuthRepository(config: _config, accountScope: scope),
    NotificationGateway(database: database),
    session,
  );
  return (database: database, controller: controller, raw: raw);
}

Future<void> _pumpAccount(
  WidgetTester tester,
  String locale, {
  required bool verified,
}) async {
  tester.view
    ..physicalSize = _size
    ..devicePixelRatio = _pixelRatio
    ..padding = const FakeViewPadding(top: 66);
  addTearDown(tester.view.reset);
  final fixture = await _fixture(tester, _session(verified: verified));
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundary,
      child: ProviderScope(
        key: UniqueKey(),
        overrides: <Override>[
          localDatabaseProvider.overrideWithValue(fixture.database),
          sessionProvider.overrideWith((ref) => fixture.controller),
          syncServiceProvider.overrideWithValue(
            SyncService.withDependencies(
              remote: _NoopSyncRemote(),
              store: _NoopSyncStore(),
            ),
          ),
          googleSignInGatewayProvider.overrideWithValue(_AvailableGoogle()),
          analyticsProvider.overrideWith(
            (ref) => AnalyticsController.disabled(),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: Locale(locale),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: IqroTheme.light(),
          home: const AccountScreen(),
        ),
      ),
    ),
  );
  for (var index = 0; index < 3; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    if (_directory.isNotEmpty) await _loadFonts();
  });

  for (final locale in <String>['ru', 'en']) {
    testWidgets('profile in $locale', (tester) async {
      await _pumpAccount(tester, locale, verified: false);
      await _capture(tester, 'google-$locale-1-profile-sign-in');
      await _pumpAccount(tester, locale, verified: true);
      await _capture(tester, 'google-$locale-2-profile-switch-account');
    }, skip: _directory.isEmpty);

    testWidgets('onboarding in $locale', (tester) async {
      tester.view.padding = const FakeViewPadding(top: 66);
      final fixture = await _fixture(tester, _session(verified: false));
      await pumpOnboarding(
        tester,
        stored: <String, Object>{
          'locale': locale,
          'iqro_analytics_consent_v1': AnalyticsConsent.granted.name,
        },
        initialStep: OnboardingStep.done,
        size: _size,
        pixelRatio: _pixelRatio,
        boundary: _boundary,
        overrides: <Override>[
          sessionProvider.overrideWith((ref) => fixture.controller),
          googleSignInGatewayProvider.overrideWithValue(_AvailableGoogle()),
        ],
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 120)),
      );
      await tester.pumpAndSettle();
      await _capture(tester, 'google-$locale-3-onboarding-done');
    }, skip: _directory.isEmpty);
  }
}

class _ShotSessionController extends SessionController {
  _ShotSessionController(
    AuthRepository auth,
    NotificationGateway notifications,
    AuthSession session,
  ) : super(auth, notifications, () => 'ru') {
    state = AsyncValue<AuthSession?>.data(session);
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<void> refreshAccountStatus() async {}
}

class _AvailableGoogle implements GoogleSignInGateway {
  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<String?> chooseAccount() async => null;

  @override
  Future<String?> signInSilently() async => null;

  @override
  Future<void> signOut() async {}
}

class _NoopSyncRemote implements SyncRemote {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Sync remote is not used by this test');
}

class _NoopSyncStore implements SyncStore {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Sync store is not used by this test');
}
