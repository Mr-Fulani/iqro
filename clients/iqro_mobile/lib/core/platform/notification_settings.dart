import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';

/// Whether a reminder can sound, on any phone. iOS reports it. Android reports
/// only part of it, so the native side also tries a silent notification.
class NotificationSettings {
  static const channel = MethodChannel('forum.iqro.app/notification_settings');

  static Future<bool> soundAllowed() async {
    if (kIsWeb) return true;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => _androidSoundAllowed(),
      TargetPlatform.iOS => _iosSoundAllowed(),
      _ => true,
    };
  }

  static Future<bool> _androidSoundAllowed() async {
    try {
      return await channel.invokeMethod<bool>('soundAllowed') ?? true;
    } on PlatformException {
      return true;
    }
  }

  static Future<bool> _iosSoundAllowed() async {
    final options = await FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.checkPermissions();
    return options?.isSoundEnabled ?? true;
  }

  /// Opens this app's notification screen, or its settings on iOS.
  static Future<void> open() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      await Geolocator.openAppSettings();
      return;
    }
    try {
      await channel.invokeMethod<void>('open');
    } on PlatformException {
      // Some firmwares lack the screen; reminders still vibrate.
    }
  }
}
