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
import 'account_scope.dart';
import 'auth_session.dart';

class AuthRepository {
  AuthRepository({
    required AppConfig config,
    FlutterSecureStorage? secureStorage,
    Dio? dio,
    Uuid? uuid,
    AccountScope? accountScope,
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
       _uuid = uuid ?? const Uuid(),
       accountScope = accountScope ?? AccountScope();

  static const _sessionKey = 'session.v1';
  static const _installationIdKey = 'installation_id.v1';
  static const _installationCredentialKey = 'installation_credential.v1';
  static const _pendingHandoffKey = 'pending_account_handoff.v1';
  static const _pendingVerificationKey = 'pending_email_verification.v1';
  static const _logoutTombstoneKey = 'logout_tombstone.v1';

  final FlutterSecureStorage _storage;
  final Dio _dio;
  final Uuid _uuid;
  final AccountScope accountScope;
  final StreamController<AuthSession?> _sessionChanges =
      StreamController<AuthSession?>.broadcast(sync: true);
  AuthSession? _session;
  Future<AuthSession>? _refreshFlight;
  _AuthTransitionStamp? _refreshStamp;
  Future<AuthSession?>? _startupRecoveryFlight;
  Future<AuthSession?>? _verificationRecoveryFlight;
  bool _startupResolved = false;
  bool _verificationGatePending = false;
  bool _logoutGatePending = false;
  Future<void> _transitionTail = Future<void>.value();

  AuthSession? get current => _session;
  Stream<AuthSession?> get sessionChanges => _sessionChanges.stream;

  Future<AuthSession?> loadCachedSession() {
    if (_startupResolved) return Future<AuthSession?>.value(_session);
    final active = _startupRecoveryFlight;
    if (active != null) return active;
    late final Future<AuthSession?> flight;
    flight = _resolveStartupSession().whenComplete(() {
      if (identical(_startupRecoveryFlight, flight)) {
        _startupRecoveryFlight = null;
      }
    });
    _startupRecoveryFlight = flight;
    return flight;
  }

  Future<AuthSession?> _resolveStartupSession() async {
    if (await _hasActiveLogoutTombstone()) {
      _logoutGatePending = true;
      _session = null;
      accountScope.deactivate();
      _verificationGatePending = false;
      // The tombstone is authoritative. Old credentials may still exist when
      // a platform keystore rejected deletion/overwrite, but they must never
      // be adopted after explicit logout.
      await _neutralizeSecureValue(_sessionKey, fallback: '{}');
      await _neutralizeSecureValue(_pendingHandoffKey, fallback: '{}');
      await _neutralizeSecureValue(_pendingVerificationKey, fallback: '{}');
      _startupResolved = true;
      _publishSession();
      return null;
    }
    final loaded = await _serializeTransition(
      () => _loadCachedSessionUnlocked(publish: false),
    );
    final intent = await _readPendingVerification();
    if (intent != null) {
      _verificationGatePending = true;
      final session = _session;
      if (session == null || session.userId != intent.sourceOwnerId) {
        await _clearVerificationIntent(intent);
        _verificationGatePending = false;
      } else {
        try {
          await _retryPendingVerificationGate();
        } on ApiException catch (error) {
          if (_isTerminalVerificationError(error)) {
            // The backend authoritatively rejected the intent and
            // _submitVerificationIntent removed it. The cached account can
            // continue normally and the user may start a new challenge.
            _verificationGatePending = false;
          }
          // Offline/lost-response recovery must not brick local-only startup.
          // The gate remains set, so no refresh/bootstrap/private request can
          // bypass the idempotent replay when connectivity returns.
        } on AccountScopeChanged {
          rethrow;
        } on Object {
          // A malformed/lost success response is ambiguous: keep the durable
          // intent and gate exactly like a transport failure.
          _verificationGatePending = true;
        }
      }
    }
    _startupResolved = true;
    _publishSession();
    return _session ?? loaded;
  }

  Future<AuthSession?> _loadCachedSessionUnlocked({
    required bool publish,
  }) async {
    final recovered = await _recoverPendingHandoff(publish: publish);
    if (recovered != null) return recovered;
    if (_session != null) return _session;
    final encoded = await _storage.read(key: _sessionKey);
    if (encoded == null) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return null;
      _session = AuthSession.fromJson(Map<String, Object?>.from(decoded));
      accountScope.activate(_session!.userId);
      if (publish) _publishSession();
      return _session;
    } on Object {
      await _deleteSecureBestEffort(_sessionKey);
      return null;
    }
  }

  Future<String?> legacyOwnerIdForMigration() async {
    // A definite active logout marker requires quarantine. A keystore I/O
    // failure must propagate so the SQLite upgrade rolls back and can retry;
    // silently treating an unreadable marker as logout would permanently
    // strand otherwise attributable v3 account rows.
    if (await _hasActiveLogoutTombstone()) return null;
    final canonical = await _readCanonicalSession();
    final pending = await _readPendingHandoff();
    if (pending != null) {
      try {
        final handoff = _decodePendingHandoff(pending);
        final canonicalOwner = canonical?.userId;
        if (canonicalOwner == handoff.sourceOwnerId ||
            canonicalOwner == handoff.target.userId) {
          return handoff.sourceOwnerId;
        }
      } on FormatException {
        // A partial journal is not ownership evidence. Fall through to the
        // independently validated canonical session.
      }
    }
    return canonical?.userId;
  }

  Future<AuthSession> ensureSession({required String locale}) async {
    var cached = await loadCachedSession();
    if (_verificationGatePending) {
      cached = await _retryPendingVerificationGate();
    }
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

  Future<String> validAccessTokenFor(
    AccountScopeSnapshot expected, {
    required String locale,
  }) async {
    final session = await ensureSession(locale: locale);
    accountScope.ensureCurrent(expected);
    if (session.userId != expected.userId) throw const AccountScopeChanged();
    return session.accessToken;
  }

  Future<AuthSession> bootstrapGuest({required String locale}) async {
    if (!_startupResolved) await loadCachedSession();
    if (_verificationGatePending) {
      final recovered = await _retryPendingVerificationGate();
      if (recovered != null) return recovered;
    }
    final stamp = _stamp();
    final identity = await _installationIdentity(expected: stamp);
    final package = await PackageInfo.fromPlatform();
    _ensureMatches(stamp);
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
      final next = AuthSession.fromApi(json, previous: stamp.session);
      if (stamp.session != null &&
          next.bootstrapGeneration < stamp.session!.bootstrapGeneration) {
        return stamp.session!;
      }
      await _persist(next, expected: stamp);
      return next;
    } on DioException catch (error) {
      _ensureMatches(stamp);
      throw ApiException.fromDio(error);
    }
  }

  Future<AuthSession> refresh() async {
    await loadCachedSession();
    if (_verificationGatePending) await _retryPendingVerificationGate();
    final requestedStamp = _stamp();
    final active = _refreshFlight;
    final activeStamp = _refreshStamp;
    if (active != null &&
        activeStamp != null &&
        _sameStamp(activeStamp, requestedStamp)) {
      return active;
    }
    final flight = _refreshOnce();
    _refreshFlight = flight;
    _refreshStamp = requestedStamp;
    return flight.whenComplete(() {
      if (identical(_refreshFlight, flight)) {
        _refreshFlight = null;
        _refreshStamp = null;
      }
    });
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
    final stamp = _stamp();
    if (!identical(stamp.session, session)) throw const AccountScopeChanged();
    try {
      final response = await _dio.post<Object?>(
        '/auth/token/refresh',
        data: <String, Object?>{'refresh_token': session.refreshToken},
      );
      final next = AuthSession.fromApi(
        _jsonMap(response.data),
        previous: session,
      );
      await _persist(next, expected: stamp);
      return next;
    } on DioException catch (error) {
      _ensureMatches(stamp);
      if (error.response?.statusCode == 401) {
        await _serializeTransition(() async {
          if (_matches(stamp)) {
            _session = null;
            accountScope.deactivate();
            _startupResolved = true;
            _verificationGatePending = false;
            _logoutGatePending = true;
            _publishSession();
            try {
              await _writeLogoutTombstone(active: true);
            } on Object {
              // A neutralized canonical session is the fallback durable fence.
            }
            await _neutralizeSecureValue(_sessionKey, fallback: '{}');
            await _neutralizeSecureValue(_pendingHandoffKey, fallback: '{}');
            await _neutralizeSecureValue(
              _pendingVerificationKey,
              fallback: '{}',
            );
            await _neutralizeSecureValue(
              _installationIdKey,
              fallback: _uuid.v4(),
            );
            await _neutralizeSecureValue(
              _installationCredentialKey,
              fallback: _newInstallationCredential(),
            );
          }
        });
      }
      throw ApiException.fromDio(error);
    }
  }

  Future<EmailChallenge> startEmailVerification(
    String email, {
    required String locale,
  }) async {
    final token = await validAccessToken(locale: locale);
    final stamp = _stamp();
    try {
      final response = await _dio.post<Object?>(
        '/auth/email/start',
        data: <String, Object?>{'email': email.trim().toLowerCase()},
        options: Options(
          headers: <String, Object?>{'Authorization': 'Bearer $token'},
        ),
      );
      final json = _jsonMap(response.data);
      await _serializeTransition(() async {
        _ensureMatches(stamp);
        await _storage.delete(key: _pendingVerificationKey);
        _verificationGatePending = false;
      });
      return EmailChallenge(
        id: json['challenge_id']!.toString(),
        expiresAt: DateTime.parse(json['expires_at']!.toString()),
      );
    } on DioException catch (error) {
      _ensureMatches(stamp);
      throw ApiException.fromDio(error);
    }
  }

  Future<AuthSession> verifyEmail({
    required EmailChallenge challenge,
    required String code,
    required String locale,
  }) async {
    final session = _session ?? await loadCachedSession();
    if (session == null) {
      throw const ApiException(
        message: 'No session is available for email verification',
        code: 'session_missing',
        statusCode: 401,
      );
    }
    final stamp = _stamp();
    if (!identical(stamp.session, session)) throw const AccountScopeChanged();
    final identity = await _installationIdentity(expected: stamp);
    _ensureMatches(stamp);
    final intent = await _prepareVerificationIntent(
      challenge: challenge,
      code: code,
      installationCredential: identity.$2,
      expected: stamp,
    );
    return _submitVerificationIntent(intent, expected: stamp);
  }

  /// Retries a verification whose response may have been lost after the
  /// server committed it. The original idempotency key and payload are kept
  /// in secure storage, so a restart never creates a second merge request.
  Future<AuthSession?> recoverPendingEmailVerification({
    required String locale,
  }) async {
    await loadCachedSession();
    if (!_verificationGatePending) return _session;
    return _retryPendingVerificationGate();
  }

  Future<AuthSession?> _retryPendingVerificationGate() {
    final active = _verificationRecoveryFlight;
    if (active != null) return active;
    late final Future<AuthSession?> flight;
    flight = _retryPendingVerificationGateOnce().whenComplete(() {
      if (identical(_verificationRecoveryFlight, flight)) {
        _verificationRecoveryFlight = null;
      }
    });
    _verificationRecoveryFlight = flight;
    return flight;
  }

  Future<AuthSession?> _retryPendingVerificationGateOnce() async {
    final intent = await _readPendingVerification();
    if (intent == null) {
      _verificationGatePending = false;
      return _session;
    }
    _verificationGatePending = true;
    final session = _session;
    if (session == null || session.userId != intent.sourceOwnerId) {
      await _clearVerificationIntent(intent);
      _verificationGatePending = false;
      return null;
    }
    return _submitVerificationIntent(intent, expected: _stamp());
  }

  Future<AuthSession> _submitVerificationIntent(
    _PendingEmailVerification intent, {
    required _AuthTransitionStamp expected,
  }) async {
    _ensureMatches(expected);
    try {
      final response = await _dio.post<Object?>(
        '/auth/email/verify',
        data: <String, Object?>{
          'challenge_id': intent.challengeId,
          'code': intent.code,
          'installation_credential': intent.installationCredential,
          'idempotency_key': intent.idempotencyKey,
        },
      );
      final json = _jsonMap(response.data);
      final previous = expected.session;
      final next = AuthSession.fromApi(json, previous: previous);
      await _persist(
        next,
        expected: expected,
        transferFrom:
            json['merged_guest'] == true &&
                previous != null &&
                previous.userId != next.userId
            ? previous.userId
            : null,
      );
      await _clearVerificationIntent(intent);
      _verificationGatePending = false;
      return next;
    } on DioException catch (error) {
      _ensureMatches(expected);
      final mapped = ApiException.fromDio(error);
      if (_isTerminalVerificationError(mapped)) {
        await _clearVerificationIntent(intent);
        _verificationGatePending = false;
      } else {
        _verificationGatePending = true;
      }
      throw mapped;
    }
  }

  Future<void> clearSession() async {
    AuthSession? session;
    var durableLogoutRecorded = false;
    var sessionNeutralized = false;
    var handoffNeutralized = false;
    var verificationNeutralized = false;
    var installationIdNeutralized = false;
    var installationCredentialNeutralized = false;
    await _serializeTransition(() async {
      // Resolve the session only after all earlier serialized auth transitions
      // finish. A handoff may have committed A -> B while this logout waited;
      // the remote revocation must therefore use B's bearer, never stale A.
      session = _session;
      if (session == null) {
        try {
          session = await _readCanonicalSession();
        } on Object {
          // A broken secure-storage read must not prevent local logout.
        }
      }
      try {
        await _writeLogoutTombstone(active: true);
        durableLogoutRecorded = true;
      } on Object {
        // Continue clearing credentials. If neither persistence strategy
        // succeeds, report it only after local state has failed closed.
        try {
          durableLogoutRecorded = await _hasActiveLogoutTombstone();
        } on Object {
          // An unreadable marker cannot be relied on as a durable fence.
        }
      }
      _session = null;
      accountScope.deactivate();
      _startupResolved = true;
      _verificationGatePending = false;
      _logoutGatePending = true;
      try {
        // Deletions are independent and retried. If a platform keystore can
        // read/write but temporarily cannot delete, overwrite auth artifacts
        // with inert values so a later startup cannot resurrect the account.
        sessionNeutralized = await _neutralizeSecureValue(
          _sessionKey,
          fallback: '{}',
        );
        handoffNeutralized = await _neutralizeSecureValue(
          _pendingHandoffKey,
          fallback: '{}',
        );
        verificationNeutralized = await _neutralizeSecureValue(
          _pendingVerificationKey,
          fallback: '{}',
        );
        installationIdNeutralized = await _neutralizeSecureValue(
          _installationIdKey,
          fallback: _uuid.v4(),
        );
        installationCredentialNeutralized = await _neutralizeSecureValue(
          _installationCredentialKey,
          fallback: _newInstallationCredential(),
        );
      } finally {
        // Notification/provider cleanup listens to this event. It must happen
        // even when the device keystore is partially unavailable.
        _publishSession();
      }
    });
    final sessionToLogout = session;
    if (sessionToLogout != null) {
      try {
        await _dio.post<Object?>(
          '/auth/logout',
          options: Options(
            headers: <String, Object?>{
              'Authorization': 'Bearer ${sessionToLogout.accessToken}',
            },
          ),
        );
      } on Object {
        // Local logout must still succeed when the network is unavailable.
      }
    }
    final allResurrectionArtifactsNeutralized =
        sessionNeutralized &&
        handoffNeutralized &&
        verificationNeutralized &&
        installationIdNeutralized &&
        installationCredentialNeutralized;
    if (!durableLogoutRecorded && !allResurrectionArtifactsNeutralized) {
      throw StateError('Secure logout could not be persisted');
    }
  }

  Future<(String, String)> _installationIdentity({
    required _AuthTransitionStamp expected,
  }) => _serializeTransition(() async {
    _ensureMatches(expected);
    var installationId = _logoutGatePending
        ? null
        : await _storage.read(key: _installationIdKey);
    var credential = _logoutGatePending
        ? null
        : await _storage.read(key: _installationCredentialKey);
    _ensureMatches(expected);
    if (installationId == null) {
      installationId = _uuid.v4();
      await _storage.write(key: _installationIdKey, value: installationId);
    }
    if (credential == null) {
      credential = _newInstallationCredential();
      await _storage.write(key: _installationCredentialKey, value: credential);
    }
    _ensureMatches(expected);
    return (installationId, credential);
  });

  Future<_PendingEmailVerification> _prepareVerificationIntent({
    required EmailChallenge challenge,
    required String code,
    required String installationCredential,
    required _AuthTransitionStamp expected,
  }) => _serializeTransition(() async {
    _ensureMatches(expected);
    final sourceOwnerId = expected.session?.userId;
    if (sourceOwnerId == null || sourceOwnerId.isEmpty) {
      throw const AccountScopeChanged();
    }
    final existing = await _readPendingVerification();
    if (existing != null &&
        existing.challengeId == challenge.id &&
        existing.sourceOwnerId == sourceOwnerId) {
      return existing;
    }
    final intent = _PendingEmailVerification(
      challengeId: challenge.id,
      expiresAt: challenge.expiresAt.toUtc(),
      code: code,
      idempotencyKey: _uuid.v7(),
      installationCredential: installationCredential,
      sourceOwnerId: sourceOwnerId,
    );
    await _storage.write(
      key: _pendingVerificationKey,
      value: jsonEncode(intent.toJson()),
    );
    _verificationGatePending = true;
    _ensureMatches(expected);
    return intent;
  });

  Future<_PendingEmailVerification?> _readPendingVerification() async {
    final encoded = await _storage.read(key: _pendingVerificationKey);
    if (encoded == null) return null;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) return null;
      return _PendingEmailVerification.fromJson(
        Map<String, Object?>.from(decoded),
      );
    } on Object {
      await _deleteSecureBestEffort(_pendingVerificationKey);
      return null;
    }
  }

  Future<void> _clearVerificationIntent(_PendingEmailVerification expected) =>
      _serializeTransition(() async {
        final current = await _readPendingVerification();
        if (current?.idempotencyKey == expected.idempotencyKey) {
          await _neutralizeSecureValue(_pendingVerificationKey, fallback: '{}');
        }
      });

  static bool _isTerminalVerificationError(ApiException error) {
    final status = error.statusCode;
    return status != null &&
        status >= 400 &&
        status < 500 &&
        status != 408 &&
        status != 425 &&
        status != 429;
  }

  Future<void> _persist(
    AuthSession session, {
    String? transferFrom,
    _AuthTransitionStamp? expected,
  }) => _serializeTransition(() async {
    if (expected != null) _ensureMatches(expected);
    if (transferFrom == null) {
      if (_logoutGatePending) {
        // A stale valid handoff outranks the canonical session at startup.
        // Never lower the logout fence until every such journal is proven
        // absent/inert, otherwise a fresh guest could later be replaced by
        // the pre-logout target account.
        final handoffNeutralized = await _neutralizeSecureValue(
          _pendingHandoffKey,
          fallback: '{}',
        );
        final verificationNeutralized = await _neutralizeSecureValue(
          _pendingVerificationKey,
          fallback: '{}',
        );
        if (!handoffNeutralized || !verificationNeutralized) {
          throw StateError('Secure logout journals are still active');
        }
      }
      await _storage.write(
        key: _sessionKey,
        value: jsonEncode(session.toJson()),
      );
      if (expected != null) _ensureMatches(expected);
      if (_logoutGatePending) {
        // Disable the fence only after a fresh canonical session is durable.
        // If this write fails, the app remains logged out and a restart still
        // refuses to adopt any stale session value.
        await _writeLogoutTombstone(active: false);
        _logoutGatePending = false;
      }
      _session = session;
      accountScope.activate(session.userId);
      _publishSession();
      return;
    }

    final sourceScope = accountScope.current;
    if (sourceScope == null || sourceScope.userId != transferFrom) {
      throw const AccountScopeChanged();
    }
    await _storage.write(
      key: _pendingHandoffKey,
      value: jsonEncode(<String, Object?>{
        'version': 1,
        'source_owner_id': transferFrom,
        'target_session': session.toJson(),
      }),
    );
    _ensureMatches(expected!);
    final transition = accountScope.beginTransition(sourceScope);
    var targetActivated = false;
    try {
      await accountScope.transferConfirmedData(transferFrom, session.userId);
      await _storage.write(
        key: _sessionKey,
        value: jsonEncode(session.toJson()),
      );
      _session = session;
      accountScope.completeTransition(transition, targetUserId: session.userId);
      targetActivated = true;
      await _finalizeHandoffBestEffort(transferFrom, session.userId);
      _publishSession();
    } on Object {
      if (!targetActivated) accountScope.rollbackTransition(transition);
      rethrow;
    }
  });

  Future<AuthSession?> _recoverPendingHandoff({required bool publish}) async {
    final pending = await _readPendingHandoff();
    if (pending == null) return null;
    late final _PendingAccountHandoff handoff;
    try {
      handoff = _decodePendingHandoff(pending);
    } on Object {
      await _neutralizeSecureValue(_pendingHandoffKey, fallback: '{}');
      return null;
    }
    final sourceOwnerId = handoff.sourceOwnerId;
    final journalTarget = handoff.target;
    final canonical = await _readCanonicalSession();
    if (canonical == null ||
        (canonical.userId != sourceOwnerId &&
            canonical.userId != journalTarget.userId)) {
      // The journal is not related to the currently durable account. It may
      // be stale residue from before an explicit logout/fresh bootstrap and
      // must never replace that newer canonical session.
      await _neutralizeSecureValue(_pendingHandoffKey, fallback: '{}');
      return null;
    }
    final targetIsCanonical = canonical.userId == journalTarget.userId;
    final target = targetIsCanonical ? canonical : journalTarget;
    AccountScopeTransition? transition;
    final currentScope = accountScope.current;
    if (currentScope != null) {
      if (currentScope.userId != sourceOwnerId &&
          currentScope.userId != target.userId) {
        throw const AccountScopeChanged();
      }
      if (currentScope.userId == sourceOwnerId) {
        transition = accountScope.beginTransition(currentScope);
      }
    }
    try {
      if (!targetIsCanonical) {
        // The journal is written before copy. A canonical target session is
        // therefore durable proof that copy already committed in an earlier
        // process; do not make target startup depend on replaying that copy.
        await accountScope.transferConfirmedData(sourceOwnerId, target.userId);
        await _storage.write(
          key: _sessionKey,
          value: jsonEncode(target.toJson()),
        );
      }
      _session = target;
      if (transition != null) {
        accountScope.completeTransition(
          transition,
          targetUserId: target.userId,
        );
      } else {
        accountScope.activate(target.userId);
      }
      await _finalizeHandoffBestEffort(sourceOwnerId, target.userId);
      if (publish) _publishSession();
      return target;
    } on Object {
      if (transition != null) accountScope.rollbackTransition(transition);
      rethrow;
    }
  }

  Future<Map<String, Object?>?> _readPendingHandoff() async {
    final encoded = await _storage.read(key: _pendingHandoffKey);
    if (encoded == null) return null;
    try {
      final decoded = jsonDecode(encoded);
      return decoded is Map ? Map<String, Object?>.from(decoded) : null;
    } on Object {
      await _deleteSecureBestEffort(_pendingHandoffKey);
      return null;
    }
  }

  Future<AuthSession?> _readCanonicalSession() async {
    final encoded = await _storage.read(key: _sessionKey);
    if (encoded == null) return null;
    try {
      final decoded = jsonDecode(encoded);
      return decoded is Map
          ? AuthSession.fromJson(Map<String, Object?>.from(decoded))
          : null;
    } on Object {
      return null;
    }
  }

  Future<bool> _neutralizeSecureValue(
    String key, {
    required String fallback,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await _storage.delete(key: key);
        return true;
      } on Object {
        // Retry once before using an inert replacement value.
      }
    }
    try {
      await _storage.write(key: key, value: fallback);
      return true;
    } on Object {
      // Local memory/scope still fail closed. A subsequent explicit logout can
      // retry keystore cleanup if the platform service recovers.
    }
    return false;
  }

  Future<void> _deleteSecureBestEffort(String key) async {
    try {
      await _storage.delete(key: key);
    } on Object {
      // Invalid stored data is ignored even if keystore cleanup is unavailable.
    }
  }

  Future<bool> _hasActiveLogoutTombstone() async {
    final raw = await _storage.read(key: _logoutTombstoneKey);
    if (raw == null) return false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['version'] != 1) return true;
      return decoded['active'] != false;
    } on Object {
      // A damaged marker is treated as active so startup fails closed.
      return true;
    }
  }

  Future<void> _writeLogoutTombstone({required bool active}) => _storage.write(
    key: _logoutTombstoneKey,
    value: jsonEncode(<String, Object?>{
      'version': 1,
      'active': active,
      'generation': _uuid.v7(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }),
  );

  Future<void> _finalizeHandoffBestEffort(String source, String target) async {
    try {
      await accountScope.finalizeConfirmedDataTransfer(source, target);
    } on Object {
      // The canonical target session and copy-first target rows are already
      // committed. Keep the journal so a later launch can retry source-row
      // cleanup, but never reject or brick the now-authoritative target.
      return;
    }
    // The target session and transferred data are already authoritative.
    // Cleanup failure must not turn committed state into a startup loop; any
    // leftover valid handoff can be replayed idempotently.
    await _neutralizeSecureValue(_pendingHandoffKey, fallback: '{}');
    await _neutralizeSecureValue(_pendingVerificationKey, fallback: '{}');
  }

  _AuthTransitionStamp _stamp() =>
      _AuthTransitionStamp(session: _session, scopeEpoch: accountScope.epoch);

  bool _matches(_AuthTransitionStamp stamp) =>
      identical(_session, stamp.session) &&
      accountScope.epoch == stamp.scopeEpoch;

  static bool _sameStamp(
    _AuthTransitionStamp left,
    _AuthTransitionStamp right,
  ) =>
      identical(left.session, right.session) &&
      left.scopeEpoch == right.scopeEpoch;

  void _ensureMatches(_AuthTransitionStamp stamp) {
    if (!_matches(stamp)) throw const AccountScopeChanged();
  }

  void _publishSession() => _sessionChanges.add(_session);

  Future<T> _serializeTransition<T>(Future<T> Function() action) {
    final result = _transitionTail.then((_) => action());
    _transitionTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  static String _safeVersion(String raw) {
    final safe = raw.replaceAll(RegExp(r'[^A-Za-z0-9._+()\-]'), '-');
    return safe.isEmpty ? '1.0.0' : safe.substring(0, min(32, safe.length));
  }

  static String _newInstallationCredential() {
    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => random.nextInt(256)),
    );
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  static Map<String, Object?> _jsonMap(Object? value) {
    if (value is Map) return Map<String, Object?>.from(value);
    throw const ApiException(
      message: 'Invalid API response',
      code: 'invalid_response',
    );
  }

  static _PendingAccountHandoff _decodePendingHandoff(
    Map<String, Object?> pending,
  ) {
    final sourceOwnerId = pending['source_owner_id']?.toString().trim() ?? '';
    final rawSession = pending['target_session'];
    if (pending['version'] != 1 ||
        sourceOwnerId.isEmpty ||
        rawSession is! Map) {
      throw const FormatException('Pending account handoff is invalid');
    }
    late final AuthSession target;
    try {
      target = AuthSession.fromJson(Map<String, Object?>.from(rawSession));
    } on Object {
      throw const FormatException('Pending account handoff is invalid');
    }
    if (target.userId.trim().isEmpty ||
        target.userId == sourceOwnerId ||
        target.accessToken.isEmpty ||
        target.refreshToken.isEmpty ||
        target.deviceId.isEmpty) {
      throw const FormatException('Pending account handoff is invalid');
    }
    return _PendingAccountHandoff(sourceOwnerId: sourceOwnerId, target: target);
  }
}

class _PendingAccountHandoff {
  const _PendingAccountHandoff({
    required this.sourceOwnerId,
    required this.target,
  });

  final String sourceOwnerId;
  final AuthSession target;
}

class _AuthTransitionStamp {
  const _AuthTransitionStamp({required this.session, required this.scopeEpoch});

  final AuthSession? session;
  final int scopeEpoch;
}

class _PendingEmailVerification {
  const _PendingEmailVerification({
    required this.challengeId,
    required this.expiresAt,
    required this.code,
    required this.idempotencyKey,
    required this.installationCredential,
    required this.sourceOwnerId,
  });

  factory _PendingEmailVerification.fromJson(Map<String, Object?> json) {
    final challengeId = json['challenge_id']?.toString().trim() ?? '';
    final expiresAt = DateTime.tryParse(
      json['challenge_expires_at']?.toString() ?? '',
    );
    final code = json['code']?.toString() ?? '';
    final idempotencyKey = json['idempotency_key']?.toString().trim() ?? '';
    final installationCredential =
        json['installation_credential']?.toString() ?? '';
    final sourceOwnerId = json['source_owner_id']?.toString().trim() ?? '';
    if (json['version'] != 1 ||
        challengeId.isEmpty ||
        challengeId.length > 128 ||
        expiresAt == null ||
        code.isEmpty ||
        code.length > 32 ||
        idempotencyKey.isEmpty ||
        idempotencyKey.length > 128 ||
        installationCredential.isEmpty ||
        installationCredential.length > 512 ||
        sourceOwnerId.isEmpty ||
        sourceOwnerId.length > 128) {
      throw const FormatException('Pending email verification is invalid');
    }
    return _PendingEmailVerification(
      challengeId: challengeId,
      expiresAt: expiresAt.toUtc(),
      code: code,
      idempotencyKey: idempotencyKey,
      installationCredential: installationCredential,
      sourceOwnerId: sourceOwnerId,
    );
  }

  final String challengeId;
  final DateTime expiresAt;
  final String code;
  final String idempotencyKey;
  final String installationCredential;
  final String sourceOwnerId;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'challenge_id': challengeId,
    'challenge_expires_at': expiresAt.toUtc().toIso8601String(),
    'code': code,
    'idempotency_key': idempotencyKey,
    'installation_credential': installationCredential,
    'source_owner_id': sourceOwnerId,
  };
}
