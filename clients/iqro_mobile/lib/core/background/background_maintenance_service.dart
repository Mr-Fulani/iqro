import '../../features/prayer/prayer_repository.dart';
import '../../features/reminders/reminder_repository.dart';
import '../audio/audio_playback_sync_service.dart';
import '../notifications/notification_gateway.dart';
import '../storage/local_database.dart';
import '../sync/sync_service.dart';

class BackgroundMaintenanceReport {
  const BackgroundMaintenanceReport({
    required this.sync,
    required this.audio,
    required this.remindersScheduled,
    this.reminderError,
  });

  final SyncReport sync;
  final AudioPlaybackSyncReport audio;
  final int remindersScheduled;
  final String? reminderError;

  bool get audioDownloaded =>
      audio.status == AudioPlaybackSyncStatus.downloaded;

  bool get shouldRetry =>
      sync.shouldRetry || audio.shouldRetry || reminderError != null;
}

class BackgroundMaintenanceService {
  BackgroundMaintenanceService({
    required SyncService sync,
    required AudioPlaybackSyncService audio,
    required ReminderRepository reminders,
    required PrayerRepository prayer,
    required NotificationGateway notifications,
    required LocalDatabase database,
    required String Function() locale,
  }) : _sync = sync,
       _audio = audio,
       _reminders = reminders,
       _prayer = prayer,
       _notifications = notifications,
       _database = database,
       _locale = locale;

  static const diagnosticsStateKey = 'background_maintenance_v1';

  final SyncService _sync;
  final AudioPlaybackSyncService _audio;
  final ReminderRepository _reminders;
  final PrayerRepository _prayer;
  final NotificationGateway _notifications;
  final LocalDatabase _database;
  final String Function() _locale;
  Future<BackgroundMaintenanceReport>? _flight;

  Future<BackgroundMaintenanceReport> run({bool renewReminders = true}) {
    final current = _flight;
    if (current != null) return current;
    late final Future<BackgroundMaintenanceReport> flight;
    flight = _run(renewReminders: renewReminders).whenComplete(() {
      if (identical(_flight, flight)) _flight = null;
    });
    _flight = flight;
    return flight;
  }

  Future<BackgroundMaintenanceReport> _run({
    required bool renewReminders,
  }) async {
    final syncReport = await _sync.synchronize();
    final audioReport = await _audio.synchronize();
    var remindersScheduled = 0;
    String? reminderError;
    if (renewReminders) {
      try {
        final rules = await _reminders.localRules();
        final result = await _notifications.reschedule(
          rules: rules,
          prayerRepository: _prayer,
          locale: _locale(),
        );
        remindersScheduled = result.scheduled;
      } on Object catch (error) {
        reminderError = error.toString();
      }
    }
    final report = BackgroundMaintenanceReport(
      sync: syncReport,
      audio: audioReport,
      remindersScheduled: remindersScheduled,
      reminderError: reminderError,
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
      'retry_recommended': report.shouldRetry,
    });
    return report;
  }
}
