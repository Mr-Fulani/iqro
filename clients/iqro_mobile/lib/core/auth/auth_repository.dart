import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../network/api_exception.dart';
import 'auth_session.dart';

class AuthRepository {
  AuthRepository({
    required AppConfig config,
    FlutterSecureStorage? secureStorage,
    Dio? dio,
    Uuid? uuid,
  }) : _storage =
           secureStorage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(
               resetOnError: false,
               migrateOnAlgorithmChange: true,
               migrateWithBackup: true,
               preferencesKeyPrefix: 'iqro',
               storageNamespace: 'auth',
             ),
           ),
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: config.apiV1,
               connectTimeout: const Duration(seconds: 12),
               receiveTimeout: const Duration(seconds: 20),
               sendTimeout: const Duration(seconds: 12),
               headers: const <String, Object>{'Accept': 'application/json'},
             ),
           ),
       _uuid = uuid ?? const Uuid();

  static const _sessionKey = 'session.v1';
  static const _installationIdKey = 'installation_id.v1';
  static const _installationCredentialKey = 'installation_credential.v1';

  final FlutterSecureStorage _storage;
  final Dio _dio;
  final Uuid _uuid;
  AuthSession? _session;
  Future<AuthSession>? _refreshFlight;

  AuthSession? get current => _session;

  Future<AuthSession?> loadCachedSession() async {
    if (_session != null) return _session;
    final encoded = await _storage.read(key: _sessionKey);
    if (encoded == null) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return null;
      _session = AuthSession.fromJson(Map<String, Object?>.from(decoded));
      return _session;
    } on Object {
      await _storage.delete(key: _sessionKey);
      return null;
    }
  }

  Future<AuthSession> ensureSession({required String locale}) async {
    final cached = await loadCachedSession();
    if (cached?.accessIsFresh ?? false) return cached!;
    if (cached?.canRefresh ?? false) {
      try {
        return await refresh();
      } on ApiException {
        // A rejected family is replaced through the stable installation proof.
      }
    }
    return bootstrapGuest(locale: locale);
  }

  Future<String> validAccessToken({required String locale}) async {
    final session = await ensureSession(locale: locale);
    return session.accessToken;
  }

  Future<AuthSession> bootstrapGuest({required String locale}) async {
    final identity = await _installationIdentity();
    final package = await PackageInfo.fromPlatform();
    try {
      final response = await _dio.post<Object?>(
        '/auth/guest',
        data: <String, Object?>{
          'installation_id': identity.$1,
          'installation_credential': identity.$2,
          'platform': 'android',
          'locale': locale,
          'app_version': _safeVersion(package.version),
        },
      );
      final json = _jsonMap(response.data);
      final next = AuthSession.fromApi(json, previous: _session);
      if (_session != null &&
          next.bootstrapGeneration < _session!.bootstrapGeneration) {
        return _session!;
      }
      await _persist(next);
      return next;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<AuthSession> refresh() {
    final active = _refreshFlight;
    if (active != null) return active;
    final flight = _refreshOnce();
    _refreshFlight = flight;
    return flight.whenComplete(() => _refreshFlight = null);
  }

  Future<AuthSession> _refreshOnce() async {
    final session = _session ?? await loadCachedSession();
    if (session == null || !session.canRefresh) {
      throw const ApiException(
        message: 'No refresh credential is available',
        code: 'refresh_token_missing',
        statusCode: 401,
      );
    }
    try {
      final response = await _dio.post<Object?>(
        '/auth/token/refresh',
        data: <String, Object?>{'refresh_token': session.refreshToken},
      );
      final next = AuthSession.fromApi(
        _jsonMap(response.data),
        previous: session,
      );
      await _persist(next);
      return next;
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        await _storage.delete(key: _sessionKey);
        _session = null;
      }
      throw ApiException.fromDio(error);
    }
  }

  Future<EmailChallenge> startEmailVerification(
    String email, {
    required String locale,
  }) async {
    final token = await validAccessToken(locale: locale);
    try {
      final response = await _dio.post<Object?>(
        '/auth/email/start',
        data: <String, Object?>{'email': email.trim().toLowerCase()},
        options: Options(
          headers: <String, Object?>{'Authorization': 'Bearer $token'},
        ),
      );
      final json = _jsonMap(response.data);
      return EmailChallenge(
        id: json['challenge_id']!.toString(),
        expiresAt: DateTime.parse(json['expires_at']!.toString()),
      );
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<AuthSession> verifyEmail({
    required EmailChallenge challenge,
    required String code,
    required String locale,
  }) async {
    final identity = await _installationIdentity();
    final token = await validAccessToken(locale: locale);
    try {
      final response = await _dio.post<Object?>(
        '/auth/email/verify',
        data: <String, Object?>{
          'challenge_id': challenge.id,
          'code': code,
          'installation_credential': identity.$2,
          'idempotency_key': _uuid.v7(),
        },
        options: Options(
          headers: <String, Object?>{'Authorization': 'Bearer $token'},
        ),
      );
      final next = AuthSession.fromApi(
        _jsonMap(response.data),
        previous: _session,
      );
      await _persist(next);
      return next;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }

  Future<void> clearSession() async {
    final session = _session ?? await loadCachedSession();
    if (session != null) {
      try {
        await _dio.post<Object?>(
          '/auth/logout',
          options: Options(
            headers: <String, Object?>{
              'Authorization': 'Bearer ${session.accessToken}',
            },
          ),
        );
      } on DioException {
        // Local logout must still succeed when the network is unavailable.
      }
    }
    _session = null;
    await _storage.delete(key: _sessionKey);
  }

  Future<(String, String)> _installationIdentity() async {
    var installationId = await _storage.read(key: _installationIdKey);
    var credential = await _storage.read(key: _installationCredentialKey);
    if (installationId == null) {
      installationId = _uuid.v4();
      await _storage.write(key: _installationIdKey, value: installationId);
    }
    if (credential == null) {
      final random = Random.secure();
      final bytes = Uint8List.fromList(
        List<int>.generate(32, (_) => random.nextInt(256)),
      );
      credential = base64UrlEncode(bytes).replaceAll('=', '');
      await _storage.write(key: _installationCredentialKey, value: credential);
    }
    return (installationId, credential);
  }

  Future<void> _persist(AuthSession session) async {
    await _storage.write(key: _sessionKey, value: jsonEncode(session.toJson()));
    _session = session;
  }

  static String _safeVersion(String raw) {
    final safe = raw.replaceAll(RegExp(r'[^A-Za-z0-9._+()\-]'), '-');
    return safe.isEmpty ? '1.0.0' : safe.substring(0, min(32, safe.length));
  }

  static Map<String, Object?> _jsonMap(Object? value) {
    if (value is Map) return Map<String, Object?>.from(value);
    throw const ApiException(
      message: 'Invalid API response',
      code: 'invalid_response',
    );
  }
}
