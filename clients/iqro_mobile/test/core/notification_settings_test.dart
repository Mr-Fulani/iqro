import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/platform/notification_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const plugin = MethodChannel('dexterous.com/flutter/local_notifications');

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(plugin, null);
    messenger.setMockMethodCallHandler(NotificationSettings.channel, null);
  });

  Future<bool> onIos({required bool sound}) {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    IOSFlutterLocalNotificationsPlugin.registerWith();
    messenger.setMockMethodCallHandler(
      plugin,
      (call) async => <String, Object>{
        'isEnabled': true,
        'isSoundEnabled': sound,
        'isAlertEnabled': true,
        'isBadgeEnabled': true,
        'isProvisionalEnabled': false,
        'isCriticalEnabled': false,
      },
    );
    return NotificationSettings.soundAllowed();
  }

  test('iOS answers from its notification settings', () async {
    expect(await onIos(sound: true), isTrue);
    expect(await onIos(sound: false), isFalse);
  });

  test('every Android phone runs the native check', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(NotificationSettings.channel, (
      call,
    ) async {
      calls.add(call.method);
      return false;
    });

    expect(await NotificationSettings.soundAllowed(), isFalse);
    expect(calls, <String>['soundAllowed']);
  });

  test('a failed Android check does not warn', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(
      NotificationSettings.channel,
      (call) async => throw PlatformException(code: 'failed'),
    );

    expect(await NotificationSettings.soundAllowed(), isTrue);
  });
}
