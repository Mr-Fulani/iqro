import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/auth/auth_repository.dart';
import 'package:iqro_mobile/core/auth/auth_session.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/network/api_client.dart';
import 'package:iqro_mobile/core/notifications/notification_gateway.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/share/share_repository.dart';
import 'package:iqro_mobile/features/share/share_screen.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  testWidgets(
    'reloads a personalized link when the same guest user becomes verified',
    (tester) async {
      final accountScope = AccountScope.forTesting('same-user');
      final database = await _openTestDatabase(tester, accountScope);
      final auth = AuthRepository(config: _config, accountScope: accountScope);
      final notifications = NotificationGateway(database: database);
      final sessionController = _TestSessionController(
        auth,
        notifications,
        _session(status: 'guest'),
      );
      final repository = _DelayedShareRepository(
        api: ApiClient(
          config: _config,
          authRepository: auth,
          locale: () => 'ru',
        ),
        database: database,
        auth: auth,
        verified: () => sessionController.isVerified,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            localDatabaseProvider.overrideWithValue(database),
            sessionProvider.overrideWith((ref) => sessionController),
            shareRepositoryProvider.overrideWithValue(repository),
          ],
          child: const _TestApp(),
        ),
      );
      await tester.pump();
      expect(repository.requests, hasLength(1));
      expect(repository.requests.single.verifiedAtRequest, isFalse);

      repository.requests.single.result.complete(
        const ShareExperience(
          title: 'Guest share',
          message: 'Guest message',
          ctaLabel: 'Share',
          url: 'https://iqro.forum/guest',
          remote: false,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('https://iqro.forum/guest'), findsOneWidget);

      final epochBeforeVerification = accountScope.epoch;
      sessionController.replace(_session(status: 'active'));
      await tester.pump();

      expect(accountScope.epoch, epochBeforeVerification);
      expect(find.text('https://iqro.forum/guest'), findsNothing);
      expect(repository.requests, hasLength(2));
      expect(repository.requests.last.verifiedAtRequest, isTrue);

      repository.requests.last.result.complete(
        const ShareExperience(
          title: 'Personal share',
          message: 'Personal message',
          ctaLabel: 'Share',
          url: 'https://iqro.forum/r/personal',
          remote: true,
          campaignKey: 'launch',
          referralEnabled: true,
          referralCode: 'PERSONAL',
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('https://iqro.forum/r/personal'), findsOneWidget);
      expect(find.text('https://iqro.forum/guest'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

const _config = AppConfig(
  apiBaseUrl: 'https://iqro.forum',
  fallbackDownloadUrl: 'https://iqro.forum',
  environment: 'production',
);

AuthSession _session({required String status}) => AuthSession(
  accessToken: 'access',
  refreshToken: 'refresh',
  accessExpiresAt: DateTime.utc(2035),
  refreshExpiresAt: DateTime.utc(2036),
  bootstrapGeneration: 1,
  userId: 'same-user',
  userStatus: status,
  deviceId: 'device',
  email: status == 'active' ? 'reader@example.test' : null,
);

Future<LocalDatabase> _openTestDatabase(
  WidgetTester tester,
  AccountScope accountScope,
) async {
  final database = (await tester.runAsync(
    () => databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
  ))!;
  addTearDown(() => tester.runAsync(database.close));
  return LocalDatabase.forTesting(database, accountScope: accountScope);
}

class _TestSessionController extends SessionController {
  _TestSessionController(
    AuthRepository auth,
    NotificationGateway notifications,
    AuthSession initial,
  ) : super(auth, notifications, () => 'ru') {
    state = AsyncValue<AuthSession?>.data(initial);
  }

  bool get isVerified => state.valueOrNull?.isVerified == true;

  @override
  Future<void> initialize() async {}

  void replace(AuthSession session) {
    state = AsyncValue<AuthSession?>.data(session);
  }
}

typedef _ShareRequest = ({
  bool verifiedAtRequest,
  Completer<ShareExperience> result,
});

class _DelayedShareRepository extends ShareRepository {
  _DelayedShareRepository({
    required super.api,
    required super.database,
    required super.auth,
    required bool Function() verified,
  }) : _verified = verified,
       super(config: _config);

  final bool Function() _verified;
  final List<_ShareRequest> requests = <_ShareRequest>[];

  @override
  Future<ShareExperience> experience({
    required String locale,
    required String fallbackTitle,
    required String fallbackMessage,
    required String fallbackCta,
    AccountScopeSnapshot? accountScope,
  }) {
    final result = Completer<ShareExperience>();
    requests.add((verifiedAtRequest: _verified(), result: result));
    return result.future;
  }

  @override
  Future<ReferralSummary?> summary(
    String? campaignKey, {
    AccountScopeSnapshot? accountScope,
  }) async => null;
}

class _TestApp extends StatelessWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: IqroTheme.light(),
      home: const ShareScreen(),
    );
  }
}
