import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/auth/auth_repository.dart';
import 'package:iqro_mobile/core/auth/auth_session.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/network/api_exception.dart';
import 'package:iqro_mobile/core/notifications/notification_gateway.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    PackageInfo.setMockInitialValues(
      appName: 'IQRO',
      packageName: 'forum.iqro.mobile',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  test(
    'invalid verification preserves the current account and rethrows',
    () async {
      final storage = _MemorySecureStorage(<String, String>{
        'session.v1': jsonEncode(_storedSession('account-a').toJson()),
        'installation_id.v1': 'installation-a',
        'installation_credential.v1': 'credential-a',
      });
      final auth = _repository(
        storage,
        _ScriptedAdapter((request) {
          if (request.path == '/auth/email/verify') {
            return _jsonResponse(const <String, Object?>{
              'code': 'invalid_code',
            }, status: 400);
          }
          throw StateError('Unexpected request ${request.path}');
        }),
      );
      final fixture = await _notificationFixture();
      addTearDown(fixture.database.close);
      final controller = SessionController(auth, fixture.gateway, () => 'ru');
      addTearDown(controller.dispose);
      await _waitFor(() => controller.state.valueOrNull?.userId == 'account-a');

      await expectLater(
        controller.verify(
          EmailChallenge(id: 'challenge-a', expiresAt: DateTime.utc(2035)),
          '000000',
        ),
        throwsA(isA<ApiException>()),
      );

      expect(controller.state.valueOrNull?.userId, 'account-a');
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.hasError, isFalse);
    },
  );

  test(
    'notification failure cannot block verification account handoff',
    () async {
      final storage = _MemorySecureStorage(<String, String>{
        'session.v1': jsonEncode(_storedSession('guest-a').toJson()),
        'installation_id.v1': 'installation-a',
        'installation_credential.v1': 'credential-a',
      });
      final auth = _repository(
        storage,
        _ScriptedAdapter((request) {
          if (request.path == '/auth/email/verify') {
            return _jsonResponse(<String, Object?>{
              ..._apiSession('verified-b', status: 'active'),
              'merged_guest': true,
            });
          }
          throw StateError('Unexpected request ${request.path}');
        }),
      );
      auth.accountScope.configure(
        transfer: (source, target) async {},
        finalizeTransfer: (source, target) async {},
      );
      final fixture = await _notificationFixture(failCancellation: true);
      addTearDown(fixture.database.close);
      final controller = SessionController(auth, fixture.gateway, () => 'ru');
      addTearDown(controller.dispose);
      await _waitFor(() => controller.state.valueOrNull?.userId == 'guest-a');

      await controller.verify(
        EmailChallenge(id: 'challenge-a', expiresAt: DateTime.utc(2035)),
        '123456',
      );

      await _waitFor(
        () => controller.state.valueOrNull?.userId == 'verified-b',
      );
      expect(controller.state.isLoading, isFalse);
      expect(controller.state.hasError, isFalse);
    },
  );

  test(
    'notification failure cannot prevent logout and guest rotation',
    () async {
      final storage = _MemorySecureStorage(<String, String>{
        'session.v1': jsonEncode(_storedSession('account-a').toJson()),
        'installation_id.v1': 'installation-a',
        'installation_credential.v1': 'credential-a',
      });
      final auth = _repository(
        storage,
        _ScriptedAdapter((request) {
          if (request.path == '/auth/logout') {
            return _jsonResponse(const <String, Object?>{});
          }
          if (request.path == '/auth/guest') {
            return _jsonResponse(_apiSession('guest-b', status: 'guest'));
          }
          throw StateError('Unexpected request ${request.path}');
        }),
      );
      final fixture = await _notificationFixture(failCancellation: true);
      addTearDown(fixture.database.close);
      final controller = SessionController(auth, fixture.gateway, () => 'ru');
      addTearDown(controller.dispose);
      await _waitFor(() => controller.state.valueOrNull?.userId == 'account-a');

      await controller.signOut();

      expect(controller.state.valueOrNull?.userId, 'guest-b');
      expect(auth.current?.userId, 'guest-b');
      expect(storage.values['installation_id.v1'], isNot('installation-a'));
      expect(controller.state.isLoading, isFalse);
    },
  );
}

const _config = AppConfig(
  apiBaseUrl: 'https://staging.iqro.forum',
  fallbackDownloadUrl: 'https://iqro.forum',
  environment: 'staging',
);

AuthRepository _repository(
  FlutterSecureStorage storage,
  HttpClientAdapter adapter,
) {
  final dio = Dio(BaseOptions(baseUrl: _config.apiV1));
  dio.httpClientAdapter = adapter;
  return AuthRepository(config: _config, secureStorage: storage, dio: dio);
}

Future<({Database database, NotificationGateway gateway})>
_notificationFixture({bool failCancellation = false}) async {
  final database = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await database.execute('''
    CREATE TABLE device_state (
      state_key TEXT PRIMARY KEY,
      payload TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  final local = LocalDatabase.forTesting(database);
  if (failCancellation) {
    await local.writeDeviceState(
      'managed_notification_ids_v1',
      <String, Object?>{
        'ids': <int>[17],
        'owner_id': 'account-a',
        'generation': 1,
        'in_progress': false,
      },
    );
  }
  return (
    database: database,
    gateway: NotificationGateway(
      database: local,
      cancelForTesting: failCancellation
          ? (id) async => throw StateError('notification plugin unavailable')
          : (id) async {},
    ),
  );
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  throw StateError('Timed out waiting for controller state');
}

AuthSession _storedSession(String userId) => AuthSession(
  accessToken: 'access-$userId',
  refreshToken: 'refresh-$userId',
  accessExpiresAt: DateTime.utc(2035),
  refreshExpiresAt: DateTime.utc(2036),
  bootstrapGeneration: 1,
  userId: userId,
  userStatus: 'guest',
  deviceId: 'device-$userId',
);

Map<String, Object?> _apiSession(String userId, {required String status}) =>
    <String, Object?>{
      'access_token': 'access-$userId',
      'refresh_token': 'refresh-$userId',
      'access_expires_at': DateTime.utc(2035).toIso8601String(),
      'refresh_expires_at': DateTime.utc(2036).toIso8601String(),
      'user': <String, Object?>{
        'id': userId,
        'status': status,
        if (status == 'active') 'email': '$userId@example.test',
      },
      'device': <String, Object?>{
        'id': 'device-$userId',
        'bootstrap_generation': 1,
      },
    };

ResponseBody _jsonResponse(Map<String, Object?> value, {int status = 200}) =>
    ResponseBody.fromString(
      jsonEncode(value),
      status,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter(this._handler);

  final FutureOr<ResponseBody> Function(RequestOptions request) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => _handler(options);

  @override
  void close({bool force = false}) {}
}

class _MemorySecureStorage extends FlutterSecureStorage {
  _MemorySecureStorage(this.values);

  final Map<String, String> values;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}
