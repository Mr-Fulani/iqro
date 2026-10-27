import 'package:flutter/services.dart';

/// Google Play's progress for an update the user accepted
/// (`com.google.android.play.core.install.model.InstallStatus`).
enum PlayInstallStatus {
  unknown,
  pending,
  downloading,
  downloaded,
  installing,
  installed,
  failed,
  canceled;

  static PlayInstallStatus parse(Object? value) => PlayInstallStatus.values
      .firstWhere((status) => status.name == value, orElse: () => unknown);
}

/// What Play knows about a newer version of this app.
class PlayUpdateInfo {
  const PlayUpdateInfo({
    required this.available,
    required this.installStatus,
    required this.versionCode,
    required this.priority,
    required this.flexibleAllowed,
  });

  factory PlayUpdateInfo.fromMap(Map<String, Object?> map) => PlayUpdateInfo(
    available: map['available'] == true,
    installStatus: PlayInstallStatus.parse(map['installStatus']),
    versionCode: (map['versionCode'] as num?)?.toInt() ?? 0,
    priority: (map['priority'] as num?)?.toInt() ?? 0,
    flexibleAllowed: map['flexibleAllowed'] == true,
  );

  final bool available;
  final PlayInstallStatus installStatus;
  final int versionCode;

  /// 0–5, set per release through the Play Developer API (0 when not set).
  final int priority;
  final bool flexibleAllowed;
}

abstract interface class AppUpdateGateway {
  /// Null when Play cannot answer: debug and adb installs, no Play Store.
  Future<PlayUpdateInfo?> check();

  /// Opens Play's update dialog; true once the user accepted the download.
  Future<bool> startFlexibleUpdate();

  /// Installs a downloaded update; Play restarts the app.
  Future<void> completeUpdate();

  Stream<PlayInstallStatus> get installStatus;
}

/// The native side is `AppUpdateHandler.kt` (FLEXIBLE updates only).
class PlayAppUpdateGateway implements AppUpdateGateway {
  static const _methods = MethodChannel('forum.iqro.app/app_update');
  static const _events = EventChannel('forum.iqro.app/app_update_state');

  @override
  Future<PlayUpdateInfo?> check() async {
    try {
      final map = await _methods.invokeMapMethod<String, Object?>('check');
      return map == null ? null : PlayUpdateInfo.fromMap(map);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<bool> startFlexibleUpdate() async {
    try {
      return await _methods.invokeMethod<bool>('startFlexible') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> completeUpdate() async {
    try {
      await _methods.invokeMethod<void>('complete');
    } on PlatformException {
      // Play keeps the downloaded update; the next start offers it again.
    } on MissingPluginException {
      // Older native shells have no update channel.
    }
  }

  @override
  Stream<PlayInstallStatus> get installStatus =>
      _events.receiveBroadcastStream().map(PlayInstallStatus.parse);
}
