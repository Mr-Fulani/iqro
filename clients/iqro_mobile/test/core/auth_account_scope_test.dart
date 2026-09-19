import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/auth/auth_repository.dart';
import 'package:iqro_mobile/core/auth/auth_session.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/network/api_exception.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'IQRO',
      packageName: 'forum.iqro.mobile',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  test('a delayed refresh cannot replace a new guest session', () async {
    final storage = _MemorySecureStorage(<String, String>{
      'session.v1': jsonEncode(_storedSession('account-a').toJson()),
      'installation_id.v1': 'installation-a',
      'installation_credential.v1': 'credential-a',
    });
    final refreshStarted = Completer<void>();
    final delayedRefresh = Completer<ResponseBody>();
    late Map<String, Object?> guestRequest;
    final adapter = _ScriptedAdapter((request) {
      switch (request.path) {
        case '/auth/token/refresh':
          refreshStarted.complete();
          return delayedRefresh.future;
        case '/auth/logout':
          return _jsonResponse(const <String, Object?>{});
        case '/auth/guest':
          guestRequest = Map<String, Object?>.from(request.data! as Map);
          return _jsonResponse(_apiSession('account-b', status: 'guest'));
        default:
          throw StateError('Unexpected request ${request.path}');
      }
    });
    final repository = _repository(storage, adapter);
    final events = <String?>[];
    final subscription = repository.sessionChanges.listen(
      (session) => events.add(session?.userId),
    );

    expect((await repository.loadCachedSession())?.userId, 'account-a');
    final staleRefresh = repository.refresh();
    final staleRefreshError = staleRefresh.then<Object?>(
      (_) => null,
      onError: (Object error, StackTrace _) => error,
    );
    await refreshStarted.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => throw StateError('refresh request did not start'),
    );

    await repository.clearSession().timeout(
      const Duration(seconds: 2),
      onTimeout: () => throw StateError('clearSession deadlocked'),
    );
    final guest = await repository
        .bootstrapGuest(locale: 'ru')
        .timeout(
          const Duration(seconds: 2),
          onTimeout: () => throw StateError('bootstrapGuest deadlocked'),
        );
    delayedRefresh.complete(
      _jsonResponse(_apiSession('account-a', status: 'active')),
    );

    expect(await staleRefreshError, isA<AccountScopeChanged>());
    expect(guest.userId, 'account-b');
    expect(repository.current?.userId, 'account-b');
    expect(repository.accountScope.current?.userId, 'account-b');
    expect(guestRequest['installation_id'], isNot('installation-a'));
    expect(guestRequest['installation_credential'], isNot('credential-a'));
    expect(
      events,
      containsAllInOrder(<String?>['account-a', null, 'account-b']),
    );
    expect(
      AuthSession.fromJson(
        Map<String, Object?>.from(
          jsonDecode(storage.values['session.v1']!) as Map,
        ),
      ).userId,
      'account-b',
    );
    expect(
      (jsonDecode(storage.values['logout_tombstone.v1']!) as Map)['active'],
      isFalse,
    );
    final restarted = _repository(storage, adapter);
    expect((await restarted.loadCachedSession())?.userId, 'account-b');
    await subscription.cancel();
  });

  test(
    'a delayed verification cannot transfer after logout and rebootstrap',
    () async {
      final storage = _MemorySecureStorage(<String, String>{
        'session.v1': jsonEncode(_storedSession('account-a').toJson()),
        'installation_id.v1': 'installation-a',
        'installation_credential.v1': 'credential-a',
      });
      final verifyStarted = Completer<void>();
      final delayedVerify = Completer<ResponseBody>();
      final adapter = _ScriptedAdapter((request) {
        switch (request.path) {
          case '/auth/email/verify':
            verifyStarted.complete();
            return delayedVerify.future;
          case '/auth/logout':
            return _jsonResponse(const <String, Object?>{});
          case '/auth/guest':
            return _jsonResponse(_apiSession('account-b', status: 'guest'));
          default:
            throw StateError('Unexpected request ${request.path}');
        }
      });
      var transfers = 0;
      final repository = _repository(storage, adapter);
      repository.accountScope.configure(
        transfer: (source, target) async => transfers++,
        finalizeTransfer: (source, target) async {},
      );
      await repository.loadCachedSession();

      final staleVerification = repository.verifyEmail(
        challenge: EmailChallenge(
          id: 'challenge-a',
          expiresAt: DateTime.utc(2035),
        ),
        code: '123456',
        locale: 'ru',
      );
      final staleVerificationError = staleVerification.then<Object?>(
        (_) => null,
        onError: (Object error, StackTrace _) => error,
      );
      await verifyStarted.future;
      await repository.clearSession();
      await repository.bootstrapGuest(locale: 'ru');
      delayedVerify.complete(
        _jsonResponse(<String, Object?>{
          ..._apiSession('verified-a', status: 'active'),
          'merged_guest': true,
        }),
      );

      expect(await staleVerificationError, isA<AccountScopeChanged>());
      expect(transfers, 0);
      expect(repository.current?.userId, 'account-b');
      expect(storage.values['pending_account_handoff.v1'], isNull);
    },
  );

  test(
    'logout queued behind a handoff revokes the committed target session',
    () async {
      final storage = _MemorySecureStorage(<String, String>{
        'session.v1': jsonEncode(_storedSession('guest-a').toJson()),
        'installation_id.v1': 'installation-a',
        'installation_credential.v1': 'credential-a',
      });
      final transferStarted = Completer<void>();
      final releaseTransfer = Completer<void>();
      String? logoutAuthorization;
      final adapter = _ScriptedAdapter((request) {
        if (request.path == '/auth/email/verify') {
          return _jsonResponse(<String, Object?>{
            ..._apiSession('verified-b', status: 'active'),
            'merged_guest': true,
          });
        }
        if (request.path == '/auth/logout') {
          logoutAuthorization = request.headers['Authorization']?.toString();
          return _jsonResponse(const <String, Object?>{});
        }
        throw StateError('Unexpected request ${request.path}');
      });
      final repository = _repository(storage, adapter);
      repository.accountScope.configure(
        transfer: (source, target) async {
          transferStarted.complete();
          await releaseTransfer.future;
        },
        finalizeTransfer: (source, target) async {},
      );
      await repository.loadCachedSession();

      final verification = repository.verifyEmail(
        challenge: EmailChallenge(
          id: 'challenge-logout-race',
          expiresAt: DateTime.utc(2035),
        ),
        code: '123456',
        locale: 'ru',
      );
      await transferStarted.future;
      final logout = repository.clearSession();
      await Future<void>.delayed(Duration.zero);
      releaseTransfer.complete();

      expect((await verification).userId, 'verified-b');
      await logout;
      expect(logoutAuthorization, 'Bearer access-verified-b');
      expect(repository.current, isNull);
      expect(repository.accountScope.current, isNull);
    },
  );

  test(
    'handoff recovers after copied data but before session persistence',
    () async {
      final storage = _MemorySecureStorage(<String, String>{
        'session.v1': jsonEncode(
          _storedSession(
            'guest-a',
            accessExpiresAt: DateTime.utc(2020),
            refreshExpiresAt: DateTime.utc(2020),
          ).toJson(),
        ),
        'installation_id.v1': 'installation-a',
        'installation_credential.v1': 'credential-a',
      });
      final adapter = _ScriptedAdapter(
        (request) => request.path == '/auth/email/verify'
            ? _jsonResponse(<String, Object?>{
                ..._apiSession('verified-b', status: 'active'),
                'merged_guest': true,
              })
            : throw StateError('Unexpected request ${request.path}'),
      );
      var copied = false;
      var failTransfer = true;
      final first = _repository(storage, adapter);
      first.accountScope.configure(
        transfer: (source, target) async {
          copied = true;
          if (failTransfer) throw StateError('crash after copy');
        },
        finalizeTransfer: (source, target) async {},
      );
      await first.loadCachedSession();

      await expectLater(
        first.verifyEmail(
          challenge: EmailChallenge(
            id: 'challenge-a',
            expiresAt: DateTime.utc(2035),
          ),
          code: '123456',
          locale: 'ru',
        ),
        throwsStateError,
      );
      expect(copied, isTrue);
      expect(first.current?.userId, 'guest-a');
      expect(first.accountScope.current?.userId, 'guest-a');
      expect(storage.values['pending_account_handoff.v1'], isNotNull);

      failTransfer = false;
      var finalized = false;
      final recovered = _repository(storage, adapter);
      recovered.accountScope.configure(
        transfer: (source, target) async => copied = true,
        finalizeTransfer: (source, target) async => finalized = true,
      );
      expect(await recovered.legacyOwnerIdForMigration(), 'guest-a');
      expect((await recovered.loadCachedSession())?.userId, 'verified-b');
      expect(recovered.accountScope.current?.userId, 'verified-b');
      expect(finalized, isTrue);
      expect(storage.values['pending_account_handoff.v1'], isNull);
    },
  );

  test('handoff recovers when canonical session write fails', () async {
    final storage = _MemorySecureStorage(<String, String>{
      'session.v1': jsonEncode(_storedSession('guest-a').toJson()),
      'installation_id.v1': 'installation-a',
      'installation_credential.v1': 'credential-a',
    });
    final adapter = _ScriptedAdapter(
      (request) => _jsonResponse(<String, Object?>{
        ..._apiSession('verified-b', status: 'active'),
        'merged_guest': true,
      }),
    );
    var copies = 0;
    final first = _repository(storage, adapter);
    first.accountScope.configure(
      transfer: (source, target) async => copies++,
      finalizeTransfer: (source, target) async {},
    );
    await first.loadCachedSession();
    storage.failNextWriteKey = 'session.v1';

    await expectLater(
      first.verifyEmail(
        challenge: EmailChallenge(
          id: 'challenge-a',
          expiresAt: DateTime.utc(2035),
        ),
        code: '123456',
        locale: 'ru',
      ),
      throwsStateError,
    );
    expect(copies, 1);
    expect(first.accountScope.current?.userId, 'guest-a');
    expect(storage.values['pending_account_handoff.v1'], isNotNull);
    expect(
      AuthSession.fromJson(
        Map<String, Object?>.from(
          jsonDecode(storage.values['session.v1']!) as Map,
        ),
      ).userId,
      'guest-a',
    );

    var finalized = false;
    final recovered = _repository(storage, adapter);
    recovered.accountScope.configure(
      transfer: (source, target) async => copies++,
      finalizeTransfer: (source, target) async => finalized = true,
    );
    expect((await recovered.loadCachedSession())?.userId, 'verified-b');
    expect(copies, 2);
    expect(finalized, isTrue);
    expect(storage.values['pending_account_handoff.v1'], isNull);
  });

  test(
    'committed handoff remains usable when journal cleanup is unavailable',
    () async {
      final storage = _MemorySecureStorage(<String, String>{
        'session.v1': jsonEncode(_storedSession('guest-a').toJson()),
        'installation_id.v1': 'installation-a',
        'installation_credential.v1': 'credential-a',
      });
      storage.alwaysFailDeleteKeys.addAll(<String>{
        'pending_account_handoff.v1',
        'pending_email_verification.v1',
      });
      storage.alwaysFailFallbackWriteKeys.addAll(<String>{
        'pending_account_handoff.v1',
        'pending_email_verification.v1',
      });
      final adapter = _ScriptedAdapter(
        (request) => _jsonResponse(<String, Object?>{
          ..._apiSession('verified-b', status: 'active'),
          'merged_guest': true,
        }),
      );
      var transfers = 0;
      var finalizations = 0;
      final repository = _repository(storage, adapter);
      repository.accountScope.configure(
        transfer: (source, target) async => transfers++,
        finalizeTransfer: (source, target) async => finalizations++,
      );
      await repository.loadCachedSession();

      final verified = await repository.verifyEmail(
        challenge: EmailChallenge(
          id: 'challenge-cleanup',
          expiresAt: DateTime.utc(2035),
        ),
        code: '123456',
        locale: 'ru',
      );

      expect(verified.userId, 'verified-b');
      expect(repository.current?.userId, 'verified-b');
      expect(transfers, 1);
      expect(finalizations, 1);
      expect(storage.values['pending_account_handoff.v1'], isNotNull);

      final restarted = _repository(storage, adapter);
      restarted.accountScope.configure(
        transfer: (source, target) async => transfers++,
        finalizeTransfer: (source, target) async => finalizations++,
      );
      expect((await restarted.loadCachedSession())?.userId, 'verified-b');
      expect(restarted.accountScope.current?.userId, 'verified-b');
      expect(transfers, 1);
      expect(finalizations, 2);
    },
  );

  test(
    'handoff stays usable and retries after source finalization fails',
    () async {
      final storage = _MemorySecureStorage(<String, String>{
        'session.v1': jsonEncode(_storedSession('guest-a').toJson()),
        'installation_id.v1': 'installation-a',
        'installation_credential.v1': 'credential-a',
      });
      final adapter = _ScriptedAdapter((request) {
        if (request.path == '/auth/logout') {
          return _jsonResponse(const <String, Object?>{});
        }
        return _jsonResponse(<String, Object?>{
          ..._apiSession('verified-b', status: 'active'),
          'merged_guest': true,
        });
      });
      final first = _repository(storage, adapter);
      first.accountScope.configure(
        transfer: (source, target) async {},
        finalizeTransfer: (source, target) async {
          throw StateError('crash before finalize');
        },
      );
      await first.loadCachedSession();

      final verified = await first.verifyEmail(
        challenge: EmailChallenge(
          id: 'challenge-a',
          expiresAt: DateTime.utc(2035),
        ),
        code: '123456',
        locale: 'ru',
      );
      expect(verified.userId, 'verified-b');
      expect(first.current?.userId, 'verified-b');
      expect(first.accountScope.current?.userId, 'verified-b');
      expect(storage.values['pending_account_handoff.v1'], isNotNull);

      var finalized = false;
      final recovered = _repository(storage, adapter);
      recovered.accountScope.configure(
        transfer: (source, target) async {},
        finalizeTransfer: (source, target) async => finalized = true,
      );
      expect((await recovered.loadCachedSession())?.userId, 'verified-b');
      expect(finalized, isTrue);
      expect(storage.values['pending_account_handoff.v1'], isNull);
    },
  );

  test(
    'persistent source finalizer failure never bricks committed target startup',
    () async {
      final storage = _MemorySecureStorage(<String, String>{
        'session.v1': jsonEncode(_storedSession('guest-a').toJson()),
        'installation_id.v1': 'installation-a',
        'installation_credential.v1': 'credential-a',
      });
      final adapter = _ScriptedAdapter(
        (request) => _jsonResponse(<String, Object?>{
          ..._apiSession('verified-b', status: 'active'),
          'merged_guest': true,
        }),
      );
      var finalizations = 0;
      Future<void> brokenFinalizer(String source, String target) async {
        finalizations++;
        throw StateError('persistent finalizer failure');
      }

      final first = _repository(storage, adapter);
      first.accountScope.configure(
        transfer: (source, target) async {},
        finalizeTransfer: brokenFinalizer,
      );
      await first.loadCachedSession();
      final verified = await first.verifyEmail(
        challenge: EmailChallenge(
          id: 'challenge-persistent-finalizer',
          expiresAt: DateTime.utc(2035),
        ),
        code: '123456',
        locale: 'ru',
      );
      expect(verified.userId, 'verified-b');
      expect(storage.values['pending_account_handoff.v1'], isNotNull);

      for (var restart = 0; restart < 2; restart++) {
        final recovered = _repository(storage, adapter);
        recovered.accountScope.configure(
          transfer: (source, target) async {},
          finalizeTransfer: brokenFinalizer,
        );
        expect((await recovered.loadCachedSession())?.userId, 'verified-b');
        expect(recovered.accountScope.current?.userId, 'verified-b');
        expect(storage.values['pending_account_handoff.v1'], isNotNull);
      }
      expect(finalizations, 3);
    },
  );

  test(
    'lost verification response reuses its durable idempotency intent',
    () async {
      final storage = _MemorySecureStorage(<String, String>{
        'session.v1': jsonEncode(_storedSession('guest-a').toJson()),
        'installation_id.v1': 'installation-a',
        'installation_credential.v1': 'credential-a',
      });
      Map<String, Object?>? firstRequest;
      final lostResponseAdapter = _ScriptedAdapter((request) {
        firstRequest = Map<String, Object?>.from(request.data! as Map);
        throw DioException(
          requestOptions: request,
          type: DioExceptionType.connectionError,
          message: 'response lost',
        );
      });
      final first = _repository(storage, lostResponseAdapter);
      first.accountScope.configure(
        transfer: (source, target) async {},
        finalizeTransfer: (source, target) async {},
      );
      await first.loadCachedSession();

      await expectLater(
        first.verifyEmail(
          challenge: EmailChallenge(
            id: 'challenge-lost-response',
            // A server may have committed the request before this deadline;
            // its idempotent stored response must remain replayable after it.
            expiresAt: DateTime.utc(2020),
          ),
          code: '654321',
          locale: 'ru',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(storage.values['pending_email_verification.v1'], isNotNull);

      Map<String, Object?>? retriedRequest;
      final replayPaths = <String>[];
      final replayStarted = Completer<void>();
      final replayResponse = Completer<ResponseBody>();
      final replayAdapter = _ScriptedAdapter((request) {
        replayPaths.add(request.path);
        if (request.path == '/auth/email/verify') {
          retriedRequest = Map<String, Object?>.from(request.data! as Map);
          replayStarted.complete();
          return replayResponse.future;
        }
        if (request.path == '/auth/token/refresh') {
          expect(
            Map<String, Object?>.from(request.data! as Map)['refresh_token'],
            'refresh-verified-b',
          );
          return _jsonResponse(_apiSession('verified-b', status: 'active'));
        }
        throw StateError(
          'Verification recovery must run before auth bootstrap: '
          '${request.path}',
        );
      });
      var transfers = 0;
      final recovered = _repository(storage, replayAdapter);
      recovered.accountScope.configure(
        transfer: (source, target) async => transfers++,
        finalizeTransfer: (source, target) async {},
      );
      final startup = recovered.loadCachedSession();
      await replayStarted.future;
      final concurrentRefresh = recovered.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(replayPaths, <String>['/auth/email/verify']);
      replayResponse.complete(
        _jsonResponse(<String, Object?>{
          ..._apiSession('verified-b', status: 'active'),
          'merged_guest': true,
        }),
      );
      final result = await startup;
      expect((await concurrentRefresh).userId, 'verified-b');

      expect(result?.userId, 'verified-b');
      expect(replayPaths, <String>[
        '/auth/email/verify',
        '/auth/token/refresh',
      ]);
      expect(transfers, 1);
      expect(
        retriedRequest?['idempotency_key'],
        firstRequest?['idempotency_key'],
      );
      expect(retriedRequest?['code'], firstRequest?['code']);
      expect(retriedRequest?['challenge_id'], firstRequest?['challenge_id']);
      expect(storage.values['pending_email_verification.v1'], isNull);
      expect(storage.values['pending_account_handoff.v1'], isNull);
    },
  );

  test(
    'logout clears a failed handoff journal and cannot resurrect target',
    () async {
      final storage = _MemorySecureStorage(<String, String>{
        'session.v1': jsonEncode(_storedSession('guest-a').toJson()),
        'installation_id.v1': 'installation-a',
        'installation_credential.v1': 'credential-a',
      });
      final adapter = _ScriptedAdapter((request) {
        if (request.path == '/auth/logout') {
          return _jsonResponse(const <String, Object?>{});
        }
        return _jsonResponse(<String, Object?>{
          ..._apiSession('verified-b', status: 'active'),
          'merged_guest': true,
        });
      });
      final first = _repository(storage, adapter);
      first.accountScope.configure(
        transfer: (source, target) async {},
        finalizeTransfer: (source, target) async {
          throw StateError('finalizer unavailable');
        },
      );
      await first.loadCachedSession();
      final verified = await first.verifyEmail(
        challenge: EmailChallenge(
          id: 'challenge-a',
          expiresAt: DateTime.utc(2035),
        ),
        code: '123456',
        locale: 'ru',
      );
      expect(verified.userId, 'verified-b');
      expect(storage.values['pending_account_handoff.v1'], isNotNull);

      final restartedWithBrokenFinalizer = _repository(storage, adapter);
      restartedWithBrokenFinalizer.accountScope.configure(
        transfer: (source, target) async {},
        finalizeTransfer: (source, target) async {
          throw StateError('finalizer remains unavailable');
        },
      );
      await restartedWithBrokenFinalizer.clearSession();

      expect(storage.values['session.v1'], isNull);
      expect(storage.values['pending_account_handoff.v1'], isNull);
      expect(storage.values['pending_email_verification.v1'], isNull);
      final restarted = _repository(storage, adapter);
      restarted.accountScope.configure(
        transfer: (source, target) async {},
        finalizeTransfer: (source, target) async {},
      );
      expect(await restarted.loadCachedSession(), isNull);
      expect(restarted.accountScope.current, isNull);
    },
  );

  test('logout fails closed when secure-storage deletes fail', () async {
    final original = _storedSession('account-a');
    final storage = _MemorySecureStorage(<String, String>{
      'session.v1': jsonEncode(original.toJson()),
      'installation_id.v1': 'installation-a',
      'installation_credential.v1': 'credential-a',
      'pending_account_handoff.v1': jsonEncode(<String, Object?>{
        'version': 1,
        'source_owner_id': 'account-a',
        'target_session': _storedSession('account-b').toJson(),
      }),
      'pending_email_verification.v1': jsonEncode(<String, Object?>{
        'version': 1,
        'challenge_id': 'challenge-a',
        'challenge_expires_at': DateTime.utc(2035).toIso8601String(),
        'code': '123456',
        'idempotency_key': 'verification-operation',
        'installation_credential': 'credential-a',
        'source_owner_id': 'account-a',
      }),
    });
    for (final key in storage.values.keys.toList(growable: false)) {
      storage.deleteFailuresRemaining[key] = 2;
    }
    final repository = _repository(
      storage,
      _ScriptedAdapter(
        (request) => request.path == '/auth/logout'
            ? _jsonResponse(const <String, Object?>{})
            : throw StateError('Unexpected request ${request.path}'),
      ),
    );
    final events = <String?>[];
    final subscription = repository.sessionChanges.listen(
      (session) => events.add(session?.userId),
    );

    await repository.clearSession();

    expect(repository.current, isNull);
    expect(repository.accountScope.current, isNull);
    expect(events, <String?>[null]);
    expect(storage.values['session.v1'], '{}');
    expect(storage.values['pending_account_handoff.v1'], '{}');
    expect(storage.values['pending_email_verification.v1'], '{}');
    expect(storage.values['installation_id.v1'], isNot('installation-a'));
    expect(storage.values['installation_credential.v1'], isNot('credential-a'));

    final restarted = _repository(
      storage,
      _ScriptedAdapter(
        (request) => throw StateError('Unexpected request ${request.path}'),
      ),
    );
    restarted.accountScope.configure(
      transfer: (source, target) async {
        throw StateError('Malformed handoff must not transfer');
      },
      finalizeTransfer: (source, target) async {},
    );
    expect(await restarted.loadCachedSession(), isNull);
    expect(restarted.accountScope.current, isNull);
    await subscription.cancel();
  });

  test(
    'logout tombstone blocks resurrection when session delete and overwrite fail',
    () async {
      final original = jsonEncode(_storedSession('account-a').toJson());
      final storage = _MemorySecureStorage(<String, String>{
        'session.v1': original,
        'installation_id.v1': 'installation-a',
        'installation_credential.v1': 'credential-a',
      });
      storage.alwaysFailDeleteKeys.add('session.v1');
      storage.alwaysFailWriteKeys.add('session.v1');
      final adapter = _ScriptedAdapter(
        (request) => request.path == '/auth/logout'
            ? _jsonResponse(const <String, Object?>{})
            : throw StateError('Unexpected request ${request.path}'),
      );
      final repository = _repository(storage, adapter);
      await repository.loadCachedSession();

      await repository.clearSession();

      expect(repository.current, isNull);
      expect(storage.values['session.v1'], original);
      final tombstone =
          jsonDecode(storage.values['logout_tombstone.v1']!) as Map;
      expect(tombstone['active'], isTrue);

      final restarted = _repository(
        storage,
        _ScriptedAdapter(
          (request) => throw StateError('Unexpected request ${request.path}'),
        ),
      );
      expect(await restarted.legacyOwnerIdForMigration(), isNull);
      expect(await restarted.loadCachedSession(), isNull);
      expect(restarted.current, isNull);
      expect(restarted.accountScope.current, isNull);
      expect(storage.values['session.v1'], original);
    },
  );

  test(
    'legacy migration owner lookup propagates transient tombstone read failure',
    () async {
      final storage = _MemorySecureStorage(<String, String>{
        'session.v1': jsonEncode(_storedSession('account-a').toJson()),
      });
      storage.readFailuresRemaining['logout_tombstone.v1'] = 1;
      final repository = _repository(
        storage,
        _ScriptedAdapter(
          (request) => throw StateError('Unexpected request ${request.path}'),
        ),
      );

      await expectLater(
        repository.legacyOwnerIdForMigration(),
        throwsStateError,
      );
      expect(await repository.legacyOwnerIdForMigration(), 'account-a');
    },
  );

  test('legacy migration ignores a partial handoff owner hint', () async {
    final storage = _MemorySecureStorage(<String, String>{
      'session.v1': jsonEncode(_storedSession('account-a').toJson()),
      'pending_account_handoff.v1': jsonEncode(<String, Object?>{
        'version': 1,
        'source_owner_id': 'unrelated-b',
        'target_session': <String, Object?>{'access_token': 'incomplete'},
      }),
    });
    final repository = _repository(
      storage,
      _ScriptedAdapter(
        (request) => throw StateError('Unexpected request ${request.path}'),
      ),
    );

    expect(await repository.legacyOwnerIdForMigration(), 'account-a');
  });

  test(
    'a valid but unrelated handoff cannot replace a newer canonical owner',
    () async {
      final storage = _MemorySecureStorage(<String, String>{
        'session.v1': jsonEncode(_storedSession('account-c').toJson()),
        'pending_account_handoff.v1': jsonEncode(<String, Object?>{
          'version': 1,
          'source_owner_id': 'account-a',
          'target_session': _storedSession('account-b').toJson(),
        }),
      });
      final repository = _repository(
        storage,
        _ScriptedAdapter(
          (request) => throw StateError('Unexpected request ${request.path}'),
        ),
      );
      var transfers = 0;
      repository.accountScope.configure(
        transfer: (source, target) async => transfers++,
        finalizeTransfer: (source, target) async {},
      );

      expect(await repository.legacyOwnerIdForMigration(), 'account-c');
      expect((await repository.loadCachedSession())?.userId, 'account-c');
      expect(repository.accountScope.current?.userId, 'account-c');
      expect(transfers, 0);
      expect(storage.values['pending_account_handoff.v1'], isNull);
    },
  );

  test('logout reports failure when no tombstone and a resurrection artifact '
      'cannot be neutralized', () async {
    final storage = _MemorySecureStorage(<String, String>{
      'session.v1': jsonEncode(_storedSession('account-a').toJson()),
      'installation_id.v1': 'installation-a',
      'installation_credential.v1': 'credential-a',
      'pending_account_handoff.v1': jsonEncode(<String, Object?>{
        'version': 1,
        'source_owner_id': 'account-a',
        'target_session': _storedSession('account-b').toJson(),
      }),
    });
    storage.alwaysFailWriteKeys.add('logout_tombstone.v1');
    storage.alwaysFailDeleteKeys.addAll(<String>{
      'pending_account_handoff.v1',
      'installation_credential.v1',
    });
    storage.alwaysFailWriteKeys.addAll(<String>{
      'pending_account_handoff.v1',
      'installation_credential.v1',
    });
    final repository = _repository(
      storage,
      _ScriptedAdapter(
        (request) => request.path == '/auth/logout'
            ? _jsonResponse(const <String, Object?>{})
            : throw StateError('Unexpected request ${request.path}'),
      ),
    );
    await expectLater(repository.clearSession(), throwsStateError);

    expect(repository.current, isNull);
    expect(repository.accountScope.current, isNull);
    expect(storage.values['logout_tombstone.v1'], isNull);
    expect(storage.values['session.v1'], isNull);
    expect(storage.values['pending_account_handoff.v1'], isNotNull);
    expect(storage.values['installation_credential.v1'], 'credential-a');
  });

  test('logout without a tombstone succeeds only after every resurrection '
      'artifact is neutralized and restart remains logged out', () async {
    final storage = _MemorySecureStorage(<String, String>{
      'session.v1': jsonEncode(_storedSession('account-a').toJson()),
      'installation_id.v1': 'installation-a',
      'installation_credential.v1': 'credential-a',
      'pending_account_handoff.v1': jsonEncode(<String, Object?>{
        'version': 1,
        'source_owner_id': 'account-a',
        'target_session': _storedSession('account-b').toJson(),
      }),
    });
    storage.alwaysFailWriteKeys.add('logout_tombstone.v1');
    final adapter = _ScriptedAdapter(
      (request) => request.path == '/auth/logout'
          ? _jsonResponse(const <String, Object?>{})
          : throw StateError('Unexpected request ${request.path}'),
    );
    final repository = _repository(storage, adapter);
    await repository.clearSession();

    expect(storage.values['session.v1'], isNull);
    expect(storage.values['pending_account_handoff.v1'], isNull);
    expect(storage.values['installation_id.v1'], isNull);
    expect(storage.values['installation_credential.v1'], isNull);
    final restarted = _repository(storage, adapter);
    expect(await restarted.loadCachedSession(), isNull);
    expect(restarted.accountScope.current, isNull);
  });

  test(
    'fresh bootstrap cannot lower logout fence while a handoff journal survives',
    () async {
      final storage = _MemorySecureStorage(<String, String>{
        'session.v1': jsonEncode(_storedSession('account-a').toJson()),
        'installation_id.v1': 'installation-a',
        'installation_credential.v1': 'credential-a',
        'pending_account_handoff.v1': jsonEncode(<String, Object?>{
          'version': 1,
          'source_owner_id': 'account-a',
          'target_session': _storedSession('account-b').toJson(),
        }),
      });
      storage.alwaysFailDeleteKeys.add('pending_account_handoff.v1');
      storage.alwaysFailWriteKeys.add('pending_account_handoff.v1');
      final adapter = _ScriptedAdapter((request) {
        if (request.path == '/auth/logout') {
          return _jsonResponse(const <String, Object?>{});
        }
        if (request.path == '/auth/guest') {
          return _jsonResponse(_apiSession('account-c', status: 'guest'));
        }
        throw StateError('Unexpected request ${request.path}');
      });
      final repository = _repository(storage, adapter);

      await repository.clearSession();
      await expectLater(
        repository.bootstrapGuest(locale: 'ru'),
        throwsStateError,
      );

      expect(repository.current, isNull);
      expect(
        (jsonDecode(storage.values['logout_tombstone.v1']!) as Map)['active'],
        isTrue,
      );
      expect(storage.values['session.v1'], isNull);
      expect(storage.values['pending_account_handoff.v1'], isNotNull);

      var transfers = 0;
      final restarted = _repository(storage, adapter);
      restarted.accountScope.configure(
        transfer: (source, target) async => transfers++,
        finalizeTransfer: (source, target) async {},
      );
      expect(await restarted.loadCachedSession(), isNull);
      expect(restarted.accountScope.current, isNull);
      expect(transfers, 0);
    },
  );

  test('refresh 401 preserves the local owner and device proof', () async {
    final original = jsonEncode(_storedSession('account-a').toJson());
    final storage = _MemorySecureStorage(<String, String>{
      'session.v1': original,
      'installation_id.v1': 'installation-a',
      'installation_credential.v1': 'credential-a',
    });
    storage.alwaysFailDeleteKeys.add('session.v1');
    storage.alwaysFailWriteKeys.add('session.v1');
    final adapter = _ScriptedAdapter((request) {
      if (request.path == '/auth/token/refresh') {
        return _jsonResponse(const <String, Object?>{
          'code': 'refresh_rejected',
        }, status: 401);
      }
      throw StateError('Unexpected request ${request.path}');
    });
    final repository = _repository(storage, adapter);
    await repository.loadCachedSession();

    await expectLater(
      repository.refresh(),
      throwsA(
        isA<ApiException>().having(
          (error) => error.statusCode,
          'statusCode',
          401,
        ),
      ),
    );

    expect(repository.current?.userId, 'account-a');
    expect(repository.accountScope.current?.userId, 'account-a');
    expect(storage.values['session.v1'], original);
    expect(storage.values['logout_tombstone.v1'], isNull);
    expect(storage.values['installation_id.v1'], 'installation-a');
    expect(storage.values['installation_credential.v1'], 'credential-a');
    final restarted = _repository(storage, adapter);
    expect((await restarted.loadCachedSession())?.userId, 'account-a');
    expect(restarted.accountScope.current?.userId, 'account-a');
  });

  test(
    'ensureSession recovers the same device after refresh rejection',
    () async {
      final storage = _MemorySecureStorage(<String, String>{
        'session.v1': jsonEncode(
          _storedSession(
            'account-a',
            accessExpiresAt: DateTime.utc(2020),
            refreshExpiresAt: DateTime.utc(2036),
          ).toJson(),
        ),
        'installation_id.v1': 'installation-a',
        'installation_credential.v1': 'credential-a',
      });
      final paths = <String>[];
      late Map<String, Object?> recoveryRequest;
      final adapter = _ScriptedAdapter((request) {
        paths.add(request.path);
        if (request.path == '/auth/token/refresh') {
          return _jsonResponse(const <String, Object?>{
            'code': 'refresh_token_invalid',
          }, status: 401);
        }
        if (request.path == '/auth/device/recover') {
          recoveryRequest = Map<String, Object?>.from(request.data! as Map);
          return _jsonResponse(_apiSession('account-a', status: 'active'));
        }
        throw StateError('Unexpected request ${request.path}');
      });
      final repository = _repository(storage, adapter);

      final session = await repository.ensureSession(locale: 'ru');

      expect(session.userId, 'account-a');
      expect(session.userStatus, 'active');
      expect(paths, <String>['/auth/token/refresh', '/auth/device/recover']);
      expect(recoveryRequest['installation_id'], 'installation-a');
      expect(recoveryRequest['installation_credential'], 'credential-a');
      expect(repository.accountScope.current?.userId, 'account-a');
      expect(storage.values['logout_tombstone.v1'], isNull);
    },
  );

  test('malformed handoff falls back to the canonical session', () async {
    final storage = _MemorySecureStorage(<String, String>{
      'session.v1': jsonEncode(_storedSession('account-a').toJson()),
      'pending_account_handoff.v1': jsonEncode(<String, Object?>{
        'version': 1,
        'source_owner_id': 'account-a',
        'target_session': <String, Object?>{
          'access_token': 'incomplete-target',
        },
      }),
    });
    final repository = _repository(
      storage,
      _ScriptedAdapter(
        (request) => throw StateError('Unexpected request ${request.path}'),
      ),
    );
    var transfers = 0;
    repository.accountScope.configure(
      transfer: (source, target) async => transfers++,
      finalizeTransfer: (source, target) async {},
    );

    final session = await repository.loadCachedSession();

    expect(session?.userId, 'account-a');
    expect(repository.accountScope.current?.userId, 'account-a');
    expect(transfers, 0);
    expect(storage.values['pending_account_handoff.v1'], isNull);
  });

  test(
    'offline startup keeps local owner but gates refresh and bootstrap behind '
    'verification replay',
    () async {
      final storage = _MemorySecureStorage(<String, String>{
        'session.v1': jsonEncode(
          _storedSession(
            'guest-a',
            accessExpiresAt: DateTime.utc(2020),
            refreshExpiresAt: DateTime.utc(2036),
          ).toJson(),
        ),
        'installation_id.v1': 'installation-a',
        'installation_credential.v1': 'credential-a',
        'pending_email_verification.v1': jsonEncode(<String, Object?>{
          'version': 1,
          'challenge_id': 'challenge-offline',
          'challenge_expires_at': DateTime.utc(2020).toIso8601String(),
          'code': '123456',
          'idempotency_key': 'stable-idempotency-key',
          'installation_credential': 'credential-a',
          'source_owner_id': 'guest-a',
        }),
      });
      final paths = <String>[];
      final adapter = _ScriptedAdapter((request) {
        paths.add(request.path);
        if (request.path != '/auth/email/verify') {
          throw StateError('Auth gate was bypassed by ${request.path}');
        }
        throw DioException(
          requestOptions: request,
          type: DioExceptionType.connectionError,
          message: 'offline',
        );
      });
      final repository = _repository(storage, adapter);
      repository.accountScope.configure(
        transfer: (source, target) async {},
        finalizeTransfer: (source, target) async {},
      );
      final events = <String?>[];
      final subscription = repository.sessionChanges.listen(
        (session) => events.add(session?.userId),
      );

      final cached = await repository.loadCachedSession();

      expect(cached?.userId, 'guest-a');
      expect(repository.current?.userId, 'guest-a');
      expect(events, <String?>['guest-a']);
      expect(storage.values['pending_email_verification.v1'], isNotNull);
      await expectLater(
        repository.ensureSession(locale: 'ru'),
        throwsA(
          isA<ApiException>().having(
            (error) => error.isOffline,
            'isOffline',
            isTrue,
          ),
        ),
      );
      expect(paths, <String>['/auth/email/verify', '/auth/email/verify']);
      expect(storage.values['session.v1'], isNotNull);
      expect(storage.values['pending_email_verification.v1'], isNotNull);
      await subscription.cancel();
    },
  );
}

const _config = AppConfig(
  apiBaseUrl: 'https://iqro.forum',
  fallbackDownloadUrl: 'https://iqro.forum',
  environment: 'production',
);

AuthRepository _repository(
  FlutterSecureStorage storage,
  HttpClientAdapter adapter,
) {
  final dio = Dio(BaseOptions(baseUrl: _config.apiV1));
  dio.httpClientAdapter = adapter;
  return AuthRepository(config: _config, secureStorage: storage, dio: dio);
}

AuthSession _storedSession(
  String userId, {
  DateTime? accessExpiresAt,
  DateTime? refreshExpiresAt,
}) => AuthSession(
  accessToken: 'access-$userId',
  refreshToken: 'refresh-$userId',
  accessExpiresAt: accessExpiresAt ?? DateTime.utc(2035),
  refreshExpiresAt: refreshExpiresAt ?? DateTime.utc(2036),
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
  String? failNextWriteKey;
  final Map<String, int> deleteFailuresRemaining = <String, int>{};
  final Map<String, int> readFailuresRemaining = <String, int>{};
  final Set<String> alwaysFailDeleteKeys = <String>{};
  final Set<String> alwaysFailWriteKeys = <String>{};
  final Set<String> alwaysFailFallbackWriteKeys = <String>{};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    final remaining = readFailuresRemaining[key] ?? 0;
    if (remaining > 0) {
      readFailuresRemaining[key] = remaining - 1;
      throw StateError('Injected secure-storage read failure for $key');
    }
    return values[key];
  }

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
    if (alwaysFailWriteKeys.contains(key)) {
      throw StateError('Injected persistent secure-storage write failure');
    }
    if (value == '{}' && alwaysFailFallbackWriteKeys.contains(key)) {
      throw StateError('Injected secure-storage fallback write failure');
    }
    if (failNextWriteKey == key) {
      failNextWriteKey = null;
      throw StateError('Injected secure-storage write failure for $key');
    }
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
    if (alwaysFailDeleteKeys.contains(key)) {
      throw StateError('Injected persistent secure-storage delete failure');
    }
    final remaining = deleteFailuresRemaining[key] ?? 0;
    if (remaining > 0) {
      deleteFailuresRemaining[key] = remaining - 1;
      throw StateError('Injected secure-storage delete failure for $key');
    }
    values.remove(key);
  }
}
