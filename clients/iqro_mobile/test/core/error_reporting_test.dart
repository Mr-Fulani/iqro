import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/observability/error_reporting.dart';
import 'package:sentry/sentry.dart';

void main() {
  test('error reports carry no personal data and no tracing', () {
    final options = SentryOptions();
    configureErrorReporting(
      options,
      dsn: 'https://key@o1.ingest.de.sentry.io/2',
      environment: 'production',
      release: 'iqro-mobile@1.0.0+1',
    );

    expect(options.dsn, 'https://key@o1.ingest.de.sentry.io/2');
    expect(options.environment, 'production');
    expect(options.release, 'iqro-mobile@1.0.0+1');
    expect(options.sendDefaultPii, isFalse);
    expect(options.tracesSampleRate, 0);
  });

  test('an unset environment reports as production', () {
    final options = SentryOptions();
    configureErrorReporting(
      options,
      dsn: 'https://key@o1.ingest.de.sentry.io/2',
      environment: '',
    );
    expect(options.environment, 'production');
  });

  test('reporting is off unless a DSN is compiled in', () {
    expect(sentryDsn, isEmpty);
  });
}
