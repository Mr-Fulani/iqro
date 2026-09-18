class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.accessExpiresAt,
    required this.refreshExpiresAt,
    required this.bootstrapGeneration,
    required this.userId,
    required this.userStatus,
    required this.deviceId,
    this.email,
  });

  factory AuthSession.fromJson(Map<String, Object?> json) {
    return AuthSession(
      accessToken: json['access_token']! as String,
      refreshToken: json['refresh_token']! as String,
      accessExpiresAt: DateTime.parse(json['access_expires_at']! as String),
      refreshExpiresAt: DateTime.parse(json['refresh_expires_at']! as String),
      bootstrapGeneration: (json['bootstrap_generation'] as num?)?.toInt() ?? 0,
      userId: json['user_id']?.toString() ?? '',
      userStatus: json['user_status']?.toString() ?? 'guest',
      deviceId: json['device_id']?.toString() ?? '',
      email: json['email']?.toString(),
    );
  }

  factory AuthSession.fromApi(
    Map<String, Object?> json, {
    AuthSession? previous,
  }) {
    final user = json['user'] is Map
        ? Map<String, Object?>.from(json['user']! as Map)
        : const <String, Object?>{};
    final device = json['device'] is Map
        ? Map<String, Object?>.from(json['device']! as Map)
        : const <String, Object?>{};
    return AuthSession(
      accessToken: json['access_token']! as String,
      refreshToken: json['refresh_token']! as String,
      accessExpiresAt: DateTime.parse(json['access_expires_at']! as String),
      refreshExpiresAt: DateTime.parse(json['refresh_expires_at']! as String),
      bootstrapGeneration:
          (device['bootstrap_generation'] as num?)?.toInt() ??
          previous?.bootstrapGeneration ??
          0,
      userId: user['id']?.toString() ?? previous?.userId ?? '',
      userStatus: user['status']?.toString() ?? previous?.userStatus ?? 'guest',
      deviceId: device['id']?.toString() ?? previous?.deviceId ?? '',
      email: user.containsKey('email')
          ? user['email']?.toString()
          : previous?.email,
    );
  }

  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;
  final DateTime refreshExpiresAt;
  final int bootstrapGeneration;
  final String userId;
  final String userStatus;
  final String deviceId;
  final String? email;

  bool get isGuest => userStatus == 'guest';
  bool get isVerified => userStatus == 'active' && email != null;
  bool get accessIsFresh => accessExpiresAt.isAfter(
    DateTime.now().toUtc().add(const Duration(seconds: 60)),
  );
  bool get canRefresh => refreshExpiresAt.isAfter(DateTime.now().toUtc());

  Map<String, Object?> toJson() => <String, Object?>{
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'access_expires_at': accessExpiresAt.toUtc().toIso8601String(),
    'refresh_expires_at': refreshExpiresAt.toUtc().toIso8601String(),
    'bootstrap_generation': bootstrapGeneration,
    'user_id': userId,
    'user_status': userStatus,
    'device_id': deviceId,
    'email': email,
  };
}

class EmailChallenge {
  const EmailChallenge({required this.id, required this.expiresAt});

  final String id;
  final DateTime expiresAt;
}
