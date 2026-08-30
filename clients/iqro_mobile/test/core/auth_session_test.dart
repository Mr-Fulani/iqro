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
}
