import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/config/app_config.dart';

void main() {
  test('debug configuration safely defaults to staging', () {
    final config = AppConfig.validate(
      apiBaseUrl: '',
      fallbackDownloadUrl: 'https://iqro.forum',
      environment: '',
      releaseMode: false,
    );

    expect(config.environment, 'staging');
    expect(config.apiBaseUrl, 'https://staging.iqro.forum');
    expect(config.apiV1, 'https://staging.iqro.forum/api/v1');
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

  test('production and staging hosts cannot be mixed', () {
    expect(
      () => AppConfig.validate(
        apiBaseUrl: 'https://staging.iqro.forum',
        fallbackDownloadUrl: 'https://iqro.forum',
        environment: 'production',
        releaseMode: true,
      ),
      throwsFormatException,
    );
    expect(
      () => AppConfig.validate(
        apiBaseUrl: 'https://iqro.forum',
        fallbackDownloadUrl: 'https://iqro.forum',
        environment: 'staging',
        releaseMode: true,
      ),
      throwsFormatException,
    );
  });

  test('API config rejects cleartext, credentials, ports and paths', () {
    for (final origin in <String>[
      'http://staging.iqro.forum',
      'https://user:secret@staging.iqro.forum',
      'https://staging.iqro.forum:8443',
      'https://staging.iqro.forum/api',
      'https://staging.iqro.forum?token=secret',
    ]) {
      expect(
        () => AppConfig.validate(
          apiBaseUrl: origin,
          fallbackDownloadUrl: 'https://iqro.forum',
          environment: 'staging',
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
