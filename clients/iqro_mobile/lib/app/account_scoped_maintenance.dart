import '../core/auth/account_scope.dart';
import '../core/background/background_maintenance_service.dart';

typedef MaintenanceAccountKey = ({String userId, int epoch});

/// Throttles foreground maintenance per account generation and absorbs the
/// expected cancellation raised when an account changes during asynchronous
/// work. Unexpected failures are reported without escaping an unawaited
/// lifecycle callback into Flutter's root zone.
class AccountScopedMaintenanceCoordinator {
  AccountScopedMaintenanceCoordinator({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const throttleWindow = Duration(minutes: 5);

  final DateTime Function() _clock;
  MaintenanceAccountKey? _lastKey;
  DateTime? _lastStartedAt;

  Future<void> run({
    required MaintenanceAccountKey? key,
    required Future<BackgroundMaintenanceReport> Function() maintenance,
    required bool Function(MaintenanceAccountKey key) isCurrent,
    required Future<void> Function() restoreAudio,
    required void Function(Object error, StackTrace stackTrace)
    reportUnexpected,
  }) async {
    if (key == null) return;
    final now = _clock();
    if (_lastKey == key &&
        _lastStartedAt != null &&
        now.difference(_lastStartedAt!) < throttleWindow) {
      return;
    }
    _lastKey = key;
    _lastStartedAt = now;

    late final BackgroundMaintenanceReport report;
    try {
      report = await maintenance();
    } on AccountScopeChanged {
      _resetFailedAttempt(key);
      return;
    } on Object catch (error, stackTrace) {
      _resetFailedAttempt(key);
      reportUnexpected(error, stackTrace);
      return;
    }

    if (!isCurrent(key) || !report.audioDownloaded) return;
    try {
      await restoreAudio();
    } on AccountScopeChanged {
      _resetFailedAttempt(key);
    } on Object catch (error, stackTrace) {
      _resetFailedAttempt(key);
      reportUnexpected(error, stackTrace);
    }
  }

  void _resetFailedAttempt(MaintenanceAccountKey key) {
    // A late failure from account A must not erase account B's throttle.
    if (_lastKey != key) return;
    _lastKey = null;
    _lastStartedAt = null;
  }
}
