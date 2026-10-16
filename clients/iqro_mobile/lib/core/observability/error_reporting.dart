import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry/sentry.dart';

/// Sentry project DSN (EU region), passed with `--dart-define=SENTRY_DSN=...`.
/// Empty disables error reporting entirely.
const sentryDsn = String.fromEnvironment('SENTRY_DSN');

/// Options for the app's Sentry client. Reports carry no personal data: no IP
/// address, user id or request bodies, and no performance tracing.
void configureErrorReporting(
  SentryOptions options, {
  required String dsn,
  required String environment,
  String? release,
}) {
  options
    ..dsn = dsn
    ..environment = environment.isEmpty ? 'production' : environment
    ..release = release
    ..sendDefaultPii = false
    ..tracesSampleRate = 0;
}

/// Reports Flutter framework errors and uncaught async errors to Sentry.
/// Call once from `main` before `runApp`; does nothing without a DSN.
void startErrorReporting() {
  if (sentryDsn.isEmpty) return;
  final previousFlutterError = FlutterError.onError;
  FlutterError.onError = (details) {
    previousFlutterError?.call(details);
    unawaited(
      Sentry.captureException(details.exception, stackTrace: details.stack),
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(Sentry.captureException(error, stackTrace: stack));
    return false;
  };
  unawaited(() async {
    String? release;
    try {
      final info = await PackageInfo.fromPlatform();
      release = 'iqro-mobile@${info.version}+${info.buildNumber}';
    } on Object {
      release = null;
    }
    await Sentry.init(
      (options) => configureErrorReporting(
        options,
        dsn: sentryDsn,
        environment: const String.fromEnvironment('APP_ENV'),
        release: release,
      ),
    );
  }());
}
