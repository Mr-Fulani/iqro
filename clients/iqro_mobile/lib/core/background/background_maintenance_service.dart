import '../../features/prayer/prayer_repository.dart';
import '../../features/prayer/prayer_widget_service.dart';
import '../../features/reminders/reminder_repository.dart';
import '../audio/audio_playback_sync_service.dart';
import '../auth/account_scope.dart';
import '../notifications/notification_gateway.dart';
import '../storage/local_database.dart';
import '../sync/sync_service.dart';

class BackgroundMaintenanceReport {
  const BackgroundMaintenanceReport({
    required this.sync,
    required this.audio,
    required this.remindersScheduled,
    this.prayerWidgetUpdated = false,
    this.reminderError,
    this.prayerWidgetError,
  });

  final SyncReport sync;
  final AudioPlaybackSyncReport audio;
  final int remindersScheduled;
  final bool prayerWidgetUpdated;
  final String? reminderError;
  final String? prayerWidgetError;

  bool get audioDownloaded =>
      audio.status == AudioPlaybackSyncStatus.downloaded;

  bool get shouldRetry =>
      sync.shouldRetry ||
      audio.shouldRetry ||
      reminderError != null ||
      prayerWidgetError != null;
}

class BackgroundMaintenanceService {
  BackgroundMaintenanceService({
    required SyncService sync,
    required AudioPlaybackSyncService audio,
    required ReminderRepository reminders,
    required PrayerRepository prayer,
    required PrayerWidgetService prayerWidget,
    required NotificationGateway notifications,
    required LocalDatabase database,
    required String Function() locale,
  }) : _sync = sync,
       _audio = audio,
       _reminders = reminders,
       _prayer = prayer,
       _prayerWidget = prayerWidget,
       _notifications = notifications,
       _database = database,
       _locale = locale;

  static const diagnosticsStateKey = 'background_maintenance_v1';

  final SyncService _sync;
  final AudioPlaybackSyncService _audio;
  final ReminderRepository _reminders;
  final PrayerRepository _prayer;
  final PrayerWidgetService _prayerWidget;
  final NotificationGateway _notifications;
  final LocalDatabase _database;
  final String Function() _locale;
  Future<BackgroundMaintenanceReport>? _flight;
  AccountScopeSnapshot? _flightScope;

  Future<BackgroundMaintenanceReport> run({bool renewReminders = true}) async {
    final requestedScope = await _database.captureAccount();
    while (true) {
      final current = _flight;
      final activeScope = _flightScope;
      if (current != null) {
        if (activeScope != null &&
            activeScope.userId == requestedScope.userId &&
            activeScope.epoch == requestedScope.epoch) {
          return current;
        }
        try {
          await current;
        } on Object {
          // A previous account must not suppress maintenance for this one.
        }
        _database.ensureCurrent(requestedScope);
        continue;
      }
      return _startFlight(requestedScope, renewReminders: renewReminders);
    }
  }

  Future<BackgroundMaintenanceReport> _startFlight(
    AccountScopeSnapshot scope, {
    required bool renewReminders,
  }) {
    late final Future<BackgroundMaintenanceReport> flight;
    flight = _run(scope, renewReminders: renewReminders).whenComplete(() {
      if (identical(_flight, flight)) {
        _flight = null;
        _flightScope = null;
      }
    });
    _flight = flight;
    _flightScope = scope;
    return flight;
  }

  Future<BackgroundMaintenanceReport> _run(
    AccountScopeSnapshot scope, {
    required bool renewReminders,
  }) async {
    final syncReport = await _sync.synchronize();
    _database.ensureCurrent(scope);
    final audioReport = await _audio.synchronize();
    _database.ensureCurrent(scope);
    var remindersScheduled = 0;
    String? reminderError;
    var prayerWidgetUpdated = false;
    String? prayerWidgetError;
    if (renewReminders) {
      try {
        final rules = await _reminders.localRules(accountScope: scope);
        _database.ensureCurrent(scope);
        final result = await _notifications.reschedule(
          rules: rules,
          prayerRepository: _prayer,
          locale: _locale(),
          accountScope: scope,
        );
        _database.ensureCurrent(scope);
        remindersScheduled = result.scheduled;
      } on Object catch (error) {
        reminderError = error.toString();
      }
    }
    try {
      final widgetResult = await _prayerWidget.update(
        locale: _locale(),
        accountScope: scope,
      );
      _database.ensureCurrent(scope);
      prayerWidgetUpdated = widgetResult.hasSchedule;
    } on Object catch (error) {
      prayerWidgetError = error.toString();
    }
    final report = BackgroundMaintenanceReport(
      sync: syncReport,
      audio: audioReport,
      remindersScheduled: remindersScheduled,
      prayerWidgetUpdated: prayerWidgetUpdated,
      reminderError: reminderError,
      prayerWidgetError: prayerWidgetError,
    );
    await _database.writeState(diagnosticsStateKey, <String, Object?>{
      'completed_at': DateTime.now().toUtc().toIso8601String(),
      'sync_status': syncReport.status.name,
      'pushed': syncReport.pushed,
      'pulled': syncReport.pulled,
      'pending': syncReport.pending,
      'audio_status': audioReport.status.name,
      'reminders_scheduled': remindersScheduled,
      'reminders_renewed': renewReminders,
      'reminders_ok': reminderError == null,
      'prayer_widget_updated': prayerWidgetUpdated,
      'prayer_widget_ok': prayerWidgetError == null,
      'retry_recommended': report.shouldRetry,
    }, accountScope: scope);
    return report;
  }
}
