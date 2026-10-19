import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/auth/auth_session.dart';

void main() {
  test('AuthSession preserves generation and account mode', () {
    final session = AuthSession.fromApi(<String, Object?>{
      'access_token': 'access',
      'refresh_token': 'refresh',
      'access_expires_at': '2030-01-01T00:00:00Z',
      'refresh_expires_at': '2030-02-01T00:00:00Z',
      'user': <String, Object?>{
        'id': 'user',
        'status': 'active',
        'email': 'reader@example.com',
      },
      'device': <String, Object?>{'id': 'device', 'bootstrap_generation': 3},
    });

    expect(session.bootstrapGeneration, 3);
    expect(session.isVerified, isTrue);
    expect(AuthSession.fromJson(session.toJson()).email, 'reader@example.com');
  });

  test('an explicit null email clears stale verified account data', () {
    final previous = AuthSession.fromApi(<String, Object?>{
      'access_token': 'old-access',
      'refresh_token': 'old-refresh',
      'access_expires_at': '2030-01-01T00:00:00Z',
      'refresh_expires_at': '2030-02-01T00:00:00Z',
      'user': <String, Object?>{
        'id': 'user',
        'status': 'active',
        'email': 'reader@example.com',
      },
      'device': <String, Object?>{'id': 'device'},
    });

    final current = AuthSession.fromApi(<String, Object?>{
      'access_token': 'new-access',
      'refresh_token': 'new-refresh',
      'access_expires_at': '2030-01-02T00:00:00Z',
      'refresh_expires_at': '2030-02-02T00:00:00Z',
      'user': <String, Object?>{'id': 'user', 'status': 'guest', 'email': null},
      'device': <String, Object?>{'id': 'device'},
    }, previous: previous);

    expect(current.email, isNull);
    expect(current.isVerified, isFalse);
  });

  test('a guest response without email clears stale account data', () {
    final previous = AuthSession.fromApi(<String, Object?>{
      'access_token': 'old-access',
      'refresh_token': 'old-refresh',
      'access_expires_at': '2030-01-01T00:00:00Z',
      'refresh_expires_at': '2030-02-01T00:00:00Z',
      'user': <String, Object?>{
        'id': 'user',
        'status': 'active',
        'email': 'reader@example.com',
      },
      'device': <String, Object?>{'id': 'device'},
    });

    final current = AuthSession.fromApi(<String, Object?>{
      'access_token': 'new-access',
      'refresh_token': 'new-refresh',
      'access_expires_at': '2030-01-02T00:00:00Z',
      'refresh_expires_at': '2030-02-02T00:00:00Z',
      'user': <String, Object?>{'id': 'guest', 'status': 'guest'},
      'device': <String, Object?>{'id': 'device'},
    }, previous: previous);

    expect(current.email, isNull);
    expect(current.isGuest, isTrue);
  });

  test('deletion schedule survives storage and token refreshes', () {
    final pending = AuthSession.fromApi(<String, Object?>{
      'access_token': 'access',
      'refresh_token': 'refresh',
      'access_expires_at': '2030-01-01T00:00:00Z',
      'refresh_expires_at': '2030-02-01T00:00:00Z',
      'user': <String, Object?>{
        'id': 'user',
        'status': 'pending_deletion',
        'email': 'reader@example.com',
        'deletion_requested_at': '2026-10-19T09:00:00Z',
        'deletion_scheduled_for': '2026-10-26T09:00:00Z',
      },
      'device': <String, Object?>{'id': 'device'},
    });

    expect(pending.isPendingDeletion, isTrue);
    expect(pending.isVerified, isFalse);
    final restored = AuthSession.fromJson(pending.toJson());
    expect(restored.isPendingDeletion, isTrue);
    expect(restored.deletionScheduledFor, DateTime.utc(2026, 10, 26, 9));

    final refreshed = AuthSession.fromApi(<String, Object?>{
      'access_token': 'new-access',
      'refresh_token': 'new-refresh',
      'access_expires_at': '2030-01-02T00:00:00Z',
      'refresh_expires_at': '2030-02-02T00:00:00Z',
    }, previous: pending);
    expect(refreshed.deletionScheduledFor, DateTime.utc(2026, 10, 26, 9));

    final cancelled = refreshed.withAccountSummary(<String, Object?>{
      'user': <String, Object?>{
        'id': 'user',
        'status': 'active',
        'email': 'reader@example.com',
        'deletion_requested_at': null,
        'deletion_scheduled_for': null,
      },
    });
    expect(cancelled.isVerified, isTrue);
    expect(cancelled.deletionScheduledFor, isNull);
    expect(cancelled.accessToken, 'new-access');
  });
}
