import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/auth/auth_repository.dart';
import 'package:iqro_mobile/core/auth/auth_session.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/network/api_exception.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('account deletion', () {
    test('a request adopts the pending status and keeps the tokens', () async {
      final storage = _storageWith(_activeSession());
      late RequestOptions sent;
      final repository = _repository(storage, (request) {
        sent = request;
        return _jsonResponse(_summary(status: 'pending_deletion'), 202);
      });
      final events = <AuthSession?>[];
      final subscription = repository.sessionChanges.listen(events.add);

      final session = await repository.requestAccountDeletion(
        'challenge-1',
        locale: 'ru',
      );

      expect(sent.path, '/me/deletion-request');
      expect(sent.data, <String, Object?>{
        'reauth_challenge_id': 'challenge-1',
      });
      expect(sent.headers['Authorization'], 'Bearer access-account-a');
      expect(session.isPendingDeletion, isTrue);
      expect(session.isVerified, isFalse);
      expect(session.email, 'reader@example.test');
      expect(session.accessToken, 'access-account-a');
      expect(session.deletionScheduledFor, DateTime.utc(2026, 10, 26, 9));
      expect(repository.current, same(session));
      expect(events.last, same(session));
      final stored = AuthSession.fromJson(
        jsonDecode(storage.values['session.v1']!) as Map<String, Object?>,
      );
      expect(stored.isPendingDeletion, isTrue);
      expect(stored.deletionScheduledFor, DateTime.utc(2026, 10, 26, 9));
      await subscription.cancel();
    });

    test('a cancellation restores the active account', () async {
      final storage = _storageWith(_pendingSession());
      late String path;
      final repository = _repository(storage, (request) {
        path = request.path;
        return _jsonResponse(_summary(status: 'active'));
      });

      final session = await repository.cancelAccountDeletion(
        'challenge-2',
        locale: 'ru',
      );

      expect(path, '/me/deletion-cancel');
      expect(session.isVerified, isTrue);
      expect(session.deletionScheduledFor, isNull);
      expect(session.deletionRequestedAt, isNull);
    });

    test(
      'a stale or wrong verification leaves the account unchanged',
      () async {
        final storage = _storageWith(_activeSession());
        final before = storage.values['session.v1'];
        final repository = _repository(
          storage,
          (_) => _jsonResponse(<String, Object?>{
            'code': 'account_reauthentication_required',
            'detail': 'A recent email verification is required.',
          }, 403),
        );

        final error = await _apiError(
          repository.requestAccountDeletion('challenge-1', locale: 'ru'),
        );

        expect(error.statusCode, 403);
        expect(error.code, 'account_reauthentication_required');
        expect(repository.current?.isVerified, isTrue);
        expect(storage.values['session.v1'], before);
      },
    );

    test('a network failure surfaces as offline and changes nothing', () async {
      final storage = _storageWith(_activeSession());
      final repository = _repository(
        storage,
        (request) => throw DioException.connectionError(
          requestOptions: request,
          reason: 'offline',
        ),
      );

      final error = await _apiError(
        repository.requestAccountDeletion('challenge-1', locale: 'ru'),
      );

      expect(error.isOffline, isTrue);
      expect(repository.current?.isVerified, isTrue);
    });

    test('a wrong code is rejected before any lifecycle request', () async {
      final storage = _storageWith(_activeSession());
      final paths = <String>[];
      final repository = _repository(storage, (request) {
        paths.add(request.path);
        return _jsonResponse(<String, Object?>{
          'code': 'email_challenge_invalid',
          'detail': 'Email verification could not be completed.',
        }, 400);
      });
      await repository.loadCachedSession();

      final error = await _apiError(
        repository.verifyEmail(
          challenge: EmailChallenge(
            id: 'challenge-1',
            expiresAt: DateTime.utc(2035),
          ),
          code: '000000',
          locale: 'ru',
        ),
      );

      expect(error.statusCode, 400);
      expect(paths, <String>['/auth/email/verify']);
      expect(repository.current?.isVerified, isTrue);
      expect(storage.values['pending_email_verification.v1'], isNull);
    });

    test('the account summary picks up a deletion made elsewhere', () async {
      final storage = _storageWith(_activeSession());
      late RequestOptions sent;
      final repository = _repository(storage, (request) {
        sent = request;
        return _jsonResponse(_summary(status: 'pending_deletion'));
      });

      final session = await repository.refreshAccountSummary(locale: 'ru');

      expect(sent.method, 'GET');
      expect(sent.path, '/me');
      expect(session.isPendingDeletion, isTrue);
    });

    test('a summary racing a token refresh keeps the rotated token', () async {
      final storage = _storageWith(_activeSession());
      final summaryReply = Completer<void>();
      final refreshReply = Completer<void>();
      final refreshTokensSent = <Object?>[];
      final repository = _repository(storage, (request) async {
        if (request.path == '/me') {
          await summaryReply.future;
          return _jsonResponse(_summary(status: 'pending_deletion'));
        }
        refreshTokensSent.add((request.data as Map)['refresh_token']);
        await refreshReply.future;
        return _jsonResponse(<String, Object?>{
          'access_token': 'access-rotated',
          'refresh_token': 'refresh-rotated',
          'access_expires_at': '2035-01-01T00:00:00Z',
          'refresh_expires_at': '2036-01-01T00:00:00Z',
        });
      });

      final summary = repository.refreshAccountSummary(locale: 'ru');
      await pumpEventQueue();
      final refreshed = repository.refresh();
      await pumpEventQueue();
      summaryReply.complete();
      await pumpEventQueue();
      refreshReply.complete();
      await refreshed;
      final session = await summary;

      expect(session.refreshToken, 'refresh-rotated');
      expect(session.isPendingDeletion, isTrue);
      expect(repository.current, same(session));
      await repository.refresh();
      expect(refreshTokensSent, <Object?>[
        'refresh-account-a',
        'refresh-rotated',
      ]);
    });
  });

  group('sign out everywhere', () {
    test('revokes all sessions, then logs out locally only once', () async {
      final storage = _storageWith(_activeSession());
      final requests = <RequestOptions>[];
      final repository = _repository(storage, (request) {
        requests.add(request);
        return ResponseBody.fromString('', 204);
      });

      await repository.revokeAllSessions(locale: 'ru');
      await repository.clearSession(revokeRemote: false);

      expect(requests.map((request) => request.path), <String>[
        '/auth/logout-all',
      ]);
      expect(
        requests.single.headers['Authorization'],
        'Bearer access-account-a',
      );
      expect(repository.current, isNull);
      expect(storage.values['session.v1'], isNull);
      expect(
        jsonDecode(storage.values['logout_tombstone.v1']!)['active'],
        isTrue,
      );
    });

    test('a failed revocation keeps this device signed in', () async {
      for (final failure in <Object>[
        _jsonResponse(<String, Object?>{'detail': 'Server error'}, 500),
        'offline',
      ]) {
        final storage = _storageWith(_activeSession());
        final repository = _repository(
          storage,
          (request) => failure is ResponseBody
              ? failure
              : throw DioException.connectionError(
                  requestOptions: request,
                  reason: 'offline',
                ),
        );

        final error = await _apiError(
          repository.revokeAllSessions(locale: 'ru'),
        );

        expect(error.isOffline, failure is! ResponseBody);
        expect(repository.current?.isVerified, isTrue);
        expect(storage.values['session.v1'], isNotNull);
        expect(storage.values['logout_tombstone.v1'], isNull);
      }
    });
  });
}

const _config = AppConfig(
  apiBaseUrl: 'https://iqro.forum',
  fallbackDownloadUrl: 'https://iqro.forum',
  environment: 'production',
);

Future<ApiException> _apiError(Future<Object?> future) async {
  try {
    await future;
  } on ApiException catch (error) {
    return error;
  }
  fail('Expected an ApiException');
}

AuthRepository _repository(
  _MemorySecureStorage storage,
  FutureOr<ResponseBody> Function(RequestOptions request) handler,
) {
  final dio = Dio(BaseOptions(baseUrl: _config.apiV1));
  dio.httpClientAdapter = _ScriptedAdapter(handler);
  return AuthRepository(config: _config, secureStorage: storage, dio: dio);
}

_MemorySecureStorage _storageWith(AuthSession session) =>
    _MemorySecureStorage(<String, String>{
      'session.v1': jsonEncode(session.toJson()),
      'installation_id.v1': 'installation-a',
      'installation_credential.v1': 'credential-a',
    });

AuthSession _activeSession() => AuthSession(
  accessToken: 'access-account-a',
  refreshToken: 'refresh-account-a',
  accessExpiresAt: DateTime.utc(2035),
  refreshExpiresAt: DateTime.utc(2036),
  bootstrapGeneration: 1,
  userId: 'account-a',
  userStatus: 'active',
  deviceId: 'device-a',
  email: 'reader@example.test',
);

AuthSession _pendingSession() => AuthSession(
  accessToken: 'access-account-a',
  refreshToken: 'refresh-account-a',
  accessExpiresAt: DateTime.utc(2035),
  refreshExpiresAt: DateTime.utc(2036),
  bootstrapGeneration: 1,
  userId: 'account-a',
  userStatus: 'pending_deletion',
  deviceId: 'device-a',
  email: 'reader@example.test',
  deletionRequestedAt: DateTime.utc(2026, 10, 19, 9),
  deletionScheduledFor: DateTime.utc(2026, 10, 26, 9),
);

Map<String, Object?> _summary({required String status}) => <String, Object?>{
  'user': <String, Object?>{
    'id': 'account-a',
    'status': status,
    'preferred_locale': 'ru',
    'email': 'reader@example.test',
    'deletion_requested_at': status == 'pending_deletion'
        ? '2026-10-19T09:00:00Z'
        : null,
    'deletion_scheduled_for': status == 'pending_deletion'
        ? '2026-10-26T09:00:00Z'
        : null,
  },
  'device': <String, Object?>{'id': 'device-a', 'bootstrap_generation': 1},
};

ResponseBody _jsonResponse(Map<String, Object?> value, [int status = 200]) =>
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
