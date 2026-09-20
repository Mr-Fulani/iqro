import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/auth/auth_repository.dart';
import 'package:iqro_mobile/core/auth/auth_session.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/notifications/notification_gateway.dart';
import 'package:iqro_mobile/core/network/api_exception.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/core/sync/sync_remote.dart';
import 'package:iqro_mobile/core/sync/sync_service.dart';
import 'package:iqro_mobile/core/sync/sync_store.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/account/account_screen.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  testWidgets('guest can request a code without an active account scope', (
    tester,
  ) async {
    final database = await tester.runAsync(
      () => databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
    );
    expect(database, isNotNull);
    addTearDown(() => tester.runAsync(database!.close));

    final accountScope = AccountScope();
    final localDatabase = LocalDatabase.forTesting(
      database!,
      accountScope: accountScope,
    );
    final auth = AuthRepository(config: _config, accountScope: accountScope);
    final notifications = NotificationGateway(database: localDatabase);
    final controller = _TestSessionController(auth, notifications);
    final syncService = SyncService.withDependencies(
      remote: _NoopSyncRemote(),
      store: _NoopSyncStore(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          localDatabaseProvider.overrideWithValue(localDatabase),
          sessionProvider.overrideWith((ref) => controller),
          syncServiceProvider.overrideWithValue(syncService),
        ],
        child: const _TestApp(),
      ),
    );
    await tester.pump();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(AccountScreen)),
    );
    await tester.enterText(find.byType(TextField), ' reader@example.com ');
    await tester.tap(find.text(l10n.sendCode));
    await tester.pump();

    expect(controller.requestedEmails, <String>['reader@example.com']);
    expect(find.text(l10n.verificationCode), findsOneWidget);
  });

  testWidgets('invalid email stays local and explains the correction', (
    tester,
  ) async {
    final database = await tester.runAsync(
      () => databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
    );
    expect(database, isNotNull);
    addTearDown(() => tester.runAsync(database!.close));

    final accountScope = AccountScope();
    final localDatabase = LocalDatabase.forTesting(
      database!,
      accountScope: accountScope,
    );
    final auth = AuthRepository(config: _config, accountScope: accountScope);
    final notifications = NotificationGateway(database: localDatabase);
    final controller = _TestSessionController(auth, notifications);
    final syncService = SyncService.withDependencies(
      remote: _NoopSyncRemote(),
      store: _NoopSyncStore(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          localDatabaseProvider.overrideWithValue(localDatabase),
          sessionProvider.overrideWith((ref) => controller),
          syncServiceProvider.overrideWithValue(syncService),
        ],
        child: const _TestApp(),
      ),
    );
    await tester.pump();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(AccountScreen)),
    );
    await tester.enterText(find.byType(TextField), 'reader@example');
    await tester.tap(find.text(l10n.sendCode));
    await tester.pump();

    expect(controller.requestedEmails, isEmpty);
    expect(find.text(l10n.invalidEmail), findsOneWidget);
    expect(find.text(l10n.verificationCode), findsNothing);
  });

  testWidgets('network timeout shows a short retryable message', (
    tester,
  ) async {
    final database = await tester.runAsync(
      () => databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
    );
    expect(database, isNotNull);
    addTearDown(() => tester.runAsync(database!.close));

    final accountScope = AccountScope();
    final localDatabase = LocalDatabase.forTesting(
      database!,
      accountScope: accountScope,
    );
    final auth = AuthRepository(config: _config, accountScope: accountScope);
    final notifications = NotificationGateway(database: localDatabase);
    final controller = _TestSessionController(auth, notifications)
      ..emailError = const ApiException(
        message: 'The request connection took longer than 0:00:12.000000.',
      );
    final syncService = SyncService.withDependencies(
      remote: _NoopSyncRemote(),
      store: _NoopSyncStore(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          localDatabaseProvider.overrideWithValue(localDatabase),
          sessionProvider.overrideWith((ref) => controller),
          syncServiceProvider.overrideWithValue(syncService),
        ],
        child: const _TestApp(),
      ),
    );
    await tester.pump();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(AccountScreen)),
    );
    await tester.enterText(find.byType(TextField), 'reader@example.com');
    await tester.tap(find.text(l10n.sendCode));
    await tester.pump();

    expect(find.text(l10n.networkError), findsOneWidget);
    expect(
      find.text('The request connection took longer than 0:00:12.000000.'),
      findsNothing,
    );
    expect(find.text(l10n.verificationCode), findsNothing);
  });

  testWidgets('sign out requires confirmation before clearing the account', (
    tester,
  ) async {
    final database = await tester.runAsync(
      () => databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
    );
    expect(database, isNotNull);
    addTearDown(() => tester.runAsync(database!.close));

    final accountScope = AccountScope.forTesting('account-a');
    final localDatabase = LocalDatabase.forTesting(
      database!,
      accountScope: accountScope,
    );
    final auth = AuthRepository(config: _config, accountScope: accountScope);
    final notifications = NotificationGateway(database: localDatabase);
    final controller = _TestSessionController(
      auth,
      notifications,
      initialSession: AuthSession(
        accessToken: 'access',
        refreshToken: 'refresh',
        accessExpiresAt: DateTime.utc(2035),
        refreshExpiresAt: DateTime.utc(2036),
        bootstrapGeneration: 1,
        userId: 'account-a',
        userStatus: 'active',
        deviceId: 'device-a',
        email: 'reader@example.com',
      ),
    );
    final syncService = SyncService.withDependencies(
      remote: _NoopSyncRemote(),
      store: _NoopSyncStore(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          localDatabaseProvider.overrideWithValue(localDatabase),
          sessionProvider.overrideWith((ref) => controller),
          syncServiceProvider.overrideWithValue(syncService),
        ],
        child: const _TestApp(),
      ),
    );
    await tester.pump();

    final l10n = AppLocalizations.of(
      tester.element(find.byType(AccountScreen)),
    );
    await tester.tap(find.text(l10n.signOut));
    await tester.pump();

    expect(find.text(l10n.signOutConfirmation), findsOneWidget);
    expect(controller.signOutCalls, 0);

    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();
    expect(controller.signOutCalls, 0);

    await tester.tap(find.text(l10n.signOut));
    await tester.pump();
    await tester.tap(find.text(l10n.signOut).last);
    await tester.pump();
    expect(controller.signOutCalls, 1);
  });
}

const _config = AppConfig(
  apiBaseUrl: 'https://iqro.forum',
  fallbackDownloadUrl: 'https://iqro.forum',
  environment: 'production',
);

class _TestSessionController extends SessionController {
  _TestSessionController(
    AuthRepository auth,
    NotificationGateway notifications, {
    AuthSession? initialSession,
  }) : super(auth, notifications, () => 'ru') {
    state = AsyncValue<AuthSession?>.data(
      initialSession ??
          AuthSession(
            accessToken: 'access',
            refreshToken: 'refresh',
            accessExpiresAt: DateTime.utc(2035),
            refreshExpiresAt: DateTime.utc(2036),
            bootstrapGeneration: 1,
            userId: 'guest-user',
            userStatus: 'guest',
            deviceId: 'device',
          ),
    );
  }

  final requestedEmails = <String>[];
  var signOutCalls = 0;
  ApiException? emailError;

  @override
  Future<void> initialize() async {}

  @override
  Future<EmailChallenge> startEmail(String email) async {
    requestedEmails.add(email);
    if (emailError != null) throw emailError!;
    return EmailChallenge(id: 'challenge', expiresAt: DateTime.utc(2035));
  }

  @override
  Future<void> signOut() async {
    signOutCalls += 1;
  }
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
      home: const AccountScreen(),
    );
  }
}
