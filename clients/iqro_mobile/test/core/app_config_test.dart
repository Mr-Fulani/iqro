import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/config/app_config.dart';

void main() {
  test('debug configuration safely defaults to local', () {
    final config = AppConfig.validate(
      apiBaseUrl: '',
      fallbackDownloadUrl: 'https://iqro.forum',
      environment: '',
      releaseMode: false,
    );

    expect(config.environment, 'local');
    expect(config.apiBaseUrl, 'http://127.0.0.1:8000');
    expect(config.apiV1, 'http://127.0.0.1:8000/api/v1');
  });

  group('local default follows the device type', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('Android emulator reaches the host through 10.0.2.2', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final config = await AppConfig.fromEnvironment(
        isPhysicalAndroidDevice: () async => false,
      );
      expect(config.apiBaseUrl, 'http://10.0.2.2:8000');
    });

    test('physical Android phone uses adb reverse on 127.0.0.1', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final config = await AppConfig.fromEnvironment(
        isPhysicalAndroidDevice: () async => true,
      );
      expect(config.apiBaseUrl, 'http://127.0.0.1:8000');
    });

    test('unknown Android device keeps the emulator default', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final config = await AppConfig.fromEnvironment(
        isPhysicalAndroidDevice: () async => throw StateError('no plugin'),
      );
      expect(config.apiBaseUrl, 'http://10.0.2.2:8000');
    });

    test('iOS does not query Android device info', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final config = await AppConfig.fromEnvironment(
        isPhysicalAndroidDevice: () async => fail('must not be called'),
      );
      expect(config.apiBaseUrl, 'http://127.0.0.1:8000');
    });
  });

  test(
    'release configuration requires explicit environment and API origin',
    () {
      expect(
        () => AppConfig.validate(
          apiBaseUrl: '',
          fallbackDownloadUrl: 'https://iqro.forum',
          environment: '',
          releaseMode: true,
        ),
        throwsStateError,
      );
      expect(
        () => AppConfig.validate(
          apiBaseUrl: '',
          fallbackDownloadUrl: 'https://iqro.forum',
          environment: 'production',
          releaseMode: true,
        ),
        throwsStateError,
      );
    },
  );

  test('production configuration rejects non-production hosts', () {
    expect(
      () => AppConfig.validate(
        apiBaseUrl: 'https://example.com',
        fallbackDownloadUrl: 'https://iqro.forum',
        environment: 'production',
        releaseMode: true,
      ),
      throwsFormatException,
    );
  });

  test('API config rejects cleartext, credentials, ports and paths', () {
    for (final origin in <String>[
      'http://iqro.forum',
      'https://user:secret@iqro.forum',
      'https://iqro.forum:8443',
      'https://iqro.forum/api',
      'https://iqro.forum?token=secret',
    ]) {
      expect(
        () => AppConfig.validate(
          apiBaseUrl: origin,
          fallbackDownloadUrl: 'https://iqro.forum',
          environment: 'production',
          releaseMode: false,
        ),
        throwsFormatException,
        reason: origin,
      );
    }
  });

  test('accepts exact production origin and approved store download URLs', () {
    final config = AppConfig.validate(
      apiBaseUrl: 'https://iqro.forum/',
      fallbackDownloadUrl:
          'https://play.google.com/store/apps/details?id=forum.iqro.app',
      environment: 'production',
      releaseMode: true,
    );

    expect(config.isProduction, isTrue);
    expect(config.apiBaseUrl, 'https://iqro.forum');
    expect(config.fallbackDownloadUrl, contains('play.google.com/store/apps'));
  });

  test('rejects an unapproved download host', () {
    expect(
      () => AppConfig.validate(
        apiBaseUrl: 'https://iqro.forum',
        fallbackDownloadUrl: 'https://example.com/download',
        environment: 'production',
        releaseMode: true,
      ),
      throwsFormatException,
    );
  });
}
