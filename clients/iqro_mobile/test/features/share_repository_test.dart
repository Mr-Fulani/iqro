import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/auth/auth_repository.dart';
import 'package:iqro_mobile/core/auth/auth_session.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/network/api_client.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/share/share_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('share analytics keeps only a coarse OS major version', () {
    expect(shareOsMajor('17.6.1'), '17');
    expect(shareOsMajor('Android 14'), '14');
    expect(shareOsMajor('unknown'), 'unknown');
  });

  test('does not create a referral for B from config requested by A', () async {
    final sqlDatabase = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(sqlDatabase.close);
    final accountScope = AccountScope.forTesting('account-a');
    final database = LocalDatabase.forTesting(
      sqlDatabase,
      accountScope: accountScope,
    );
    final auth = _MutableAuthRepository(
      accountScope: accountScope,
      session: _session('account-a'),
    );
    final api = _DelayedShareApi(auth);
    final repository = ShareRepository(
      api: api,
      config: _config,
      database: database,
      auth: auth,
    );
    final captured = accountScope.current!;

    final result = repository.experience(
      locale: 'ru',
      fallbackTitle: 'Share',
      fallbackMessage: 'Message',
      fallbackCta: 'Open',
      accountScope: captured,
    );

    accountScope.activate('account-b');
    auth.session = _session('account-b');
    api.configResult.complete(<String, Object?>{
      'available': true,
      'campaign': <String, Object?>{
        'title': 'Campaign',
        'message': 'Message',
        'cta_label': 'Share',
        'canonical_download_url': 'https://iqro.forum/download',
        'key': 'launch',
        'config_version': '2',
        'referral_enabled': true,
      },
    });

    await expectLater(result, throwsA(isA<AccountScopeChanged>()));
    expect(api.privatePostPaths, isEmpty);
  });
}

const _config = AppConfig(
  apiBaseUrl: 'https://iqro.forum',
  fallbackDownloadUrl: 'https://iqro.forum',
  environment: 'production',
);

AuthSession _session(String userId) => AuthSession(
  accessToken: 'access-$userId',
  refreshToken: 'refresh-$userId',
  accessExpiresAt: DateTime.utc(2035),
  refreshExpiresAt: DateTime.utc(2036),
  bootstrapGeneration: 1,
  userId: userId,
  userStatus: 'active',
  deviceId: 'device-$userId',
  email: '$userId@example.test',
);

class _MutableAuthRepository extends AuthRepository {
  _MutableAuthRepository({
    required AccountScope accountScope,
    required AuthSession session,
  }) : _session = session,
       super(config: _config, accountScope: accountScope);

  AuthSession _session;

  set session(AuthSession value) => _session = value;

  @override
  AuthSession? get current => _session;
}

class _DelayedShareApi extends ApiClient {
  _DelayedShareApi(AuthRepository auth)
    : super(config: _config, authRepository: auth, locale: () => 'ru');

  final Completer<Object?> configResult = Completer<Object?>();
  final List<String> privatePostPaths = <String>[];

  @override
  Future<Object?> get(
    String path, {
    Map<String, Object?>? query,
    bool public = false,
    String? etag,
    AccountScopeSnapshot? accountScope,
  }) {
    if (path != '/share/config') {
      throw StateError('Unexpected GET $path');
    }
    return configResult.future;
  }

  @override
  Future<Object?> post(
    String path, {
    Object? data,
    bool public = false,
    AccountScopeSnapshot? accountScope,
  }) async {
    privatePostPaths.add(path);
    return <String, Object?>{
      'code': 'B-CODE',
      'short_url': 'https://iqro.forum/r/B-CODE',
    };
  }
}
