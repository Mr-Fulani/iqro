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

  testWidgets('verified account offers deletion and sign-out everywhere', (
    tester,
  ) async {
    final (_, l10n) = await _pumpAccount(tester, _session('active'));

    expect(find.text(l10n.accountSignOutEverywhere), findsOneWidget);
    expect(find.text(l10n.accountDeletionTitle), findsOneWidget);
    expect(find.text(l10n.accountDeletionDescription), findsOneWidget);
    expect(find.text(l10n.accountDelete), findsOneWidget);
    expect(find.text(l10n.accountPendingDeletionTitle), findsNothing);
  });

  testWidgets('deletion is confirmed with an email code', (tester) async {
    final (controller, l10n) = await _pumpAccount(tester, _session('active'));

    await _tapVisible(tester, find.text(l10n.accountDelete));
    expect(find.text(l10n.accountDeletionRequestTitle), findsOneWidget);
    expect(find.text(l10n.accountDeletionRequestDescription), findsOneWidget);

    await tester.tap(find.text(l10n.accountSendCodeTo('reader@example.com')));
    await tester.pumpAndSettle();
    expect(controller.requestedEmails, <String>['reader@example.com']);
    final confirm = find.widgetWithText(
      FilledButton,
      l10n.accountConfirmDeletion,
    );
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    controller.reauthError = const ApiException(
      message: 'Email verification could not be completed.',
      code: 'email_challenge_invalid',
      statusCode: 400,
    );
    await tester.enterText(find.byType(TextField), '111111');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text(l10n.accountCodeVerifyError), findsOneWidget);
    expect(controller.deletionRequests, isEmpty);

    controller.reauthError = null;
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(controller.reauthCodes, <String>['111111', '123456']);
    expect(controller.deletionRequests, <String>['challenge']);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text(l10n.accountDeletionScheduledNotice), findsOneWidget);
    expect(find.text(l10n.accountPendingDeletionTitle), findsOneWidget);
    expect(find.text(l10n.accountDelete), findsNothing);
  });

  testWidgets('a failed deletion request is retried without a new code', (
    tester,
  ) async {
    final (controller, l10n) = await _pumpAccount(tester, _session('active'));
    controller.lifecycleError = const ApiException(message: 'offline');

    await _tapVisible(tester, find.text(l10n.accountDelete));
    await tester.tap(find.text(l10n.accountSendCodeTo('reader@example.com')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    final confirm = find.text(l10n.accountConfirmDeletion);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text(l10n.networkError), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);

    controller.lifecycleError = null;
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(controller.reauthCodes, <String>['123456']);
    expect(controller.deletionRequests, <String>['challenge', 'challenge']);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('an expired verification asks for a new code', (tester) async {
    final (controller, l10n) = await _pumpAccount(tester, _session('active'));
    controller.lifecycleError = const ApiException(
      message: 'A recent email verification is required.',
      code: 'account_reauthentication_required',
      statusCode: 403,
    );

    await _tapVisible(tester, find.text(l10n.accountDelete));
    await tester.tap(find.text(l10n.accountSendCodeTo('reader@example.com')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    await tester.tap(find.text(l10n.accountConfirmDeletion));
    await tester.pumpAndSettle();

    expect(find.text(l10n.accountCodeExpired), findsOneWidget);
    expect(
      find.text(l10n.accountSendCodeTo('reader@example.com')),
      findsOneWidget,
    );
  });

  testWidgets('closing the deletion dialog changes nothing', (tester) async {
    final (controller, l10n) = await _pumpAccount(tester, _session('active'));

    await _tapVisible(tester, find.text(l10n.accountDelete));
    await tester.tap(find.text(l10n.back));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(controller.requestedEmails, isEmpty);
    expect(controller.deletionRequests, isEmpty);
  });

  testWidgets('pending deletion shows the date and can be cancelled', (
    tester,
  ) async {
    final (controller, l10n) = await _pumpAccount(
      tester,
      _session(
        'pending_deletion',
        deletionScheduledFor: DateTime.utc(2026, 10, 26, 9),
      ),
    );

    expect(find.text(l10n.accountPendingDeletionTitle), findsOneWidget);
    expect(find.textContaining('2026'), findsOneWidget);
    expect(find.text(l10n.accountDelete), findsNothing);
    expect(find.text(l10n.syncNow), findsNothing);
    expect(find.text(l10n.signOut), findsOneWidget);

    await _tapVisible(tester, find.text(l10n.accountCancelDeletion));
    expect(find.text(l10n.accountDeletionCancelTitle), findsOneWidget);
    await tester.tap(find.text(l10n.accountSendCodeTo('reader@example.com')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '654321');
    await tester.pump();
    await tester.tap(find.text(l10n.accountRestore));
    await tester.pumpAndSettle();

    expect(controller.deletionCancellations, <String>['challenge']);
    expect(find.text(l10n.accountDeletionCancelledNotice), findsOneWidget);
    expect(find.text(l10n.accountPendingDeletionTitle), findsNothing);
    expect(find.text(l10n.accountDelete), findsOneWidget);
  });

  testWidgets('pending deletion is laid out right-to-left in Arabic', (
    tester,
  ) async {
    final (_, l10n) = await _pumpAccount(
      tester,
      _session(
        'pending_deletion',
        deletionScheduledFor: DateTime.utc(2026, 10, 26, 9),
      ),
      locale: const Locale('ar'),
    );

    final title = find.text(l10n.accountPendingDeletionTitle);
    expect(title, findsOneWidget);
    expect(l10n.accountPendingDeletionTitle, 'تمت جدولة حذف الحساب');
    expect(Directionality.of(tester.element(title)), TextDirection.rtl);
  });

  testWidgets('sign out everywhere requires confirmation', (tester) async {
    final (controller, l10n) = await _pumpAccount(tester, _session('active'));

    await _tapVisible(tester, find.text(l10n.accountSignOutEverywhere));
    expect(find.text(l10n.accountSignOutEverywhereTitle), findsOneWidget);
    expect(find.text(l10n.accountSignOutEverywhereDescription), findsOneWidget);
    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();
    expect(controller.signOutEverywhereCalls, 0);

    await _tapVisible(tester, find.text(l10n.accountSignOutEverywhere));
    await tester.tap(find.text(l10n.accountSignOutEverywhereConfirm));
    await tester.pumpAndSettle();
    expect(controller.signOutEverywhereCalls, 1);
    expect(controller.signOutCalls, 0);
  });

  testWidgets('a failed sign out everywhere keeps the account and explains', (
    tester,
  ) async {
    final (controller, l10n) = await _pumpAccount(tester, _session('active'));
    controller.signOutEverywhereError = const ApiException(
      message: 'Server error',
      statusCode: 500,
    );

    await _tapVisible(tester, find.text(l10n.accountSignOutEverywhere));
    await tester.tap(find.text(l10n.accountSignOutEverywhereConfirm));
    await tester.pumpAndSettle();

    expect(find.text(l10n.accountSignOutEverywhereError), findsOneWidget);
    expect(find.text(l10n.accountDelete), findsOneWidget);
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
  final reauthCodes = <String>[];
  ApiException? reauthError;
  final deletionRequests = <String>[];
  final deletionCancellations = <String>[];
  ApiException? lifecycleError;
  var signOutEverywhereCalls = 0;
  ApiException? signOutEverywhereError;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> refreshAccountStatus() async {}

  @override
  Future<void> reauthenticate(EmailChallenge challenge, String code) async {
    reauthCodes.add(code);
    if (reauthError != null) throw reauthError!;
  }

  @override
  Future<void> requestAccountDeletion(String challengeId) async {
    deletionRequests.add(challengeId);
    if (lifecycleError != null) throw lifecycleError!;
    state = AsyncValue<AuthSession?>.data(
      _session(
        'pending_deletion',
        deletionScheduledFor: DateTime.utc(2026, 10, 26, 9),
      ),
    );
  }

  @override
  Future<void> cancelAccountDeletion(String challengeId) async {
    deletionCancellations.add(challengeId);
    if (lifecycleError != null) throw lifecycleError!;
    state = AsyncValue<AuthSession?>.data(_session('active'));
  }

  @override
  Future<void> signOutEverywhere() async {
    signOutEverywhereCalls += 1;
    if (signOutEverywhereError != null) throw signOutEverywhereError!;
  }

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

AuthSession _session(String status, {DateTime? deletionScheduledFor}) =>
    AuthSession(
      accessToken: 'access',
      refreshToken: 'refresh',
      accessExpiresAt: DateTime.utc(2035),
      refreshExpiresAt: DateTime.utc(2036),
      bootstrapGeneration: 1,
      userId: 'account-a',
      userStatus: status,
      deviceId: 'device-a',
      email: 'reader@example.com',
      deletionScheduledFor: deletionScheduledFor,
    );

/// Pumps the account screen for `account-a` with [session].
Future<(_TestSessionController, AppLocalizations)> _pumpAccount(
  WidgetTester tester,
  AuthSession session, {
  Locale locale = const Locale('ru'),
}) async {
  final database = await tester.runAsync(
    () => databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
  );
  addTearDown(() => tester.runAsync(database!.close));
  final accountScope = AccountScope.forTesting('account-a');
  final localDatabase = LocalDatabase.forTesting(
    database!,
    accountScope: accountScope,
  );
  final auth = AuthRepository(config: _config, accountScope: accountScope);
  final controller = _TestSessionController(
    auth,
    NotificationGateway(database: localDatabase),
    initialSession: session,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        localDatabaseProvider.overrideWithValue(localDatabase),
        sessionProvider.overrideWith((ref) => controller),
        syncServiceProvider.overrideWithValue(
          SyncService.withDependencies(
            remote: _NoopSyncRemote(),
            store: _NoopSyncStore(),
          ),
        ),
      ],
      child: _TestApp(locale: locale),
    ),
  );
  await tester.pump();
  return (
    controller,
    AppLocalizations.of(tester.element(find.byType(AccountScreen))),
  );
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

class _TestApp extends StatelessWidget {
  const _TestApp({this.locale = const Locale('ru')});

  final Locale locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: IqroTheme.light(),
      home: const AccountScreen(),
    );
  }
}
