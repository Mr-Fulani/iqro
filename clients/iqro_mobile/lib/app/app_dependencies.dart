import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/audio/audio_playback_store.dart';
import '../core/audio/audio_playback_sync_service.dart';
import '../core/auth/account_scope.dart';
import '../core/auth/auth_repository.dart';
import '../core/background/background_maintenance_service.dart';
import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/notifications/notification_gateway.dart';
import '../core/storage/local_database.dart';
import '../core/storage/preferences_store.dart';
import '../core/sync/sync_service.dart';
import '../features/audio/audio_repository.dart';
import '../features/audio/audio_offline_repository.dart';
import '../features/dua/dua_repository.dart';
import '../features/memorization/memorization_repository.dart';
import '../features/plan/plan_repository.dart';
import '../features/prayer/prayer_repository.dart';
import '../features/prayer/prayer_widget_service.dart';
import '../features/quran/quran_repository.dart';
import '../features/quran/mushaf_offline_repository.dart';
import '../features/reminders/reminder_repository.dart';
import '../features/share/share_repository.dart';
import 'providers.dart';

class AppDependencies {
  AppDependencies._({
    required this.config,
    required this.preferences,
    required this.database,
    required this.auth,
    required this.api,
    required this.quran,
    required this.offlineMushaf,
    required this.audio,
    required this.offlineAudio,
    required this.playbackSync,
    required this.plan,
    required this.prayer,
    required this.prayerWidget,
    required this.reminders,
    required this.notifications,
    required this.memorization,
    required this.dua,
    required this.share,
    required this.sync,
    required this.maintenance,
  });

  final AppConfig config;
  final PreferencesStore preferences;
  final LocalDatabase database;
  final AuthRepository auth;
  final ApiClient api;
  final QuranRepository quran;
  final MushafOfflineRepository offlineMushaf;
  final AudioRepository audio;
  final AudioOfflineRepository offlineAudio;
  final AudioPlaybackSyncService playbackSync;
  final PlanRepository plan;
  final PrayerRepository prayer;
  final PrayerWidgetService prayerWidget;
  final ReminderRepository reminders;
  final NotificationGateway notifications;
  final MemorizationRepository memorization;
  final DuaRepository dua;
  final ShareRepository share;
  final SyncService sync;
  final BackgroundMaintenanceService maintenance;

  static Future<AppDependencies> initialize() async {
    final config = AppConfig.fromEnvironment();
    final sharedPreferences = await SharedPreferences.getInstance();
    final preferences = PreferencesStore(sharedPreferences);
    final accountScope = AccountScope();
    final auth = AuthRepository(config: config, accountScope: accountScope);
    final legacyOwnerId = await auth.legacyOwnerIdForMigration();
    final database = await LocalDatabase.open(
      accountScope: accountScope,
      legacyOwnerId: legacyOwnerId,
    );
    accountScope.configure(
      loader: () async {
        await auth.ensureSession(locale: preferences.read().locale);
      },
      transfer: database.transferAccountData,
      finalizeTransfer: database.finalizeAccountTransfer,
    );
    await auth.loadCachedSession();
    final api = ApiClient(
      config: config,
      authRepository: auth,
      locale: () => preferences.read().locale,
    );
    final prayer = PrayerRepository(api: api, database: database);
    final prayerWidget = PrayerWidgetService(
      prayer: prayer,
      database: database,
    );
    final reminders = ReminderRepository(api: api, database: database);
    final notifications = NotificationGateway(database: database);
    await notifications.initialize();
    final offlineMushaf = MushafOfflineRepository(api: api, database: database);
    final offlineAudio = AudioOfflineRepository(api: api, database: database);
    final audio = AudioRepository(
      api: api,
      database: database,
      offline: offlineAudio,
      preferredQuality: () => preferences.read().preferredAudioQuality,
    );
    final playbackSync = AudioPlaybackSyncService(
      api: api,
      database: database,
      audio: audio,
      store: AudioPlaybackStore(database),
      locale: () => preferences.read().locale,
    );
    final sync = SyncService(api: api, database: database);
    final maintenance = BackgroundMaintenanceService(
      sync: sync,
      audio: playbackSync,
      reminders: reminders,
      prayer: prayer,
      prayerWidget: prayerWidget,
      notifications: notifications,
      database: database,
      locale: () => preferences.read().locale,
    );
    return AppDependencies._(
      config: config,
      preferences: preferences,
      database: database,
      auth: auth,
      api: api,
      quran: QuranRepository(api: api, database: database),
      offlineMushaf: offlineMushaf,
      audio: audio,
      offlineAudio: offlineAudio,
      playbackSync: playbackSync,
      plan: PlanRepository(database, api: api),
      prayer: prayer,
      prayerWidget: prayerWidget,
      reminders: reminders,
      notifications: notifications,
      memorization: MemorizationRepository(api: api, database: database),
      dua: DuaRepository(api: api, database: database),
      share: ShareRepository(
        api: api,
        config: config,
        database: database,
        auth: auth,
      ),
      sync: sync,
      maintenance: maintenance,
    );
  }

  List<Override> get overrides => <Override>[
    appConfigProvider.overrideWithValue(config),
    preferencesStoreProvider.overrideWithValue(preferences),
    localDatabaseProvider.overrideWithValue(database),
    authRepositoryProvider.overrideWithValue(auth),
    apiClientProvider.overrideWithValue(api),
    quranRepositoryProvider.overrideWithValue(quran),
    mushafOfflineRepositoryProvider.overrideWithValue(offlineMushaf),
    audioRepositoryProvider.overrideWithValue(audio),
    audioOfflineRepositoryProvider.overrideWithValue(offlineAudio),
    audioPlaybackSyncProvider.overrideWithValue(playbackSync),
    planRepositoryProvider.overrideWithValue(plan),
    prayerRepositoryProvider.overrideWithValue(prayer),
    prayerWidgetServiceProvider.overrideWithValue(prayerWidget),
    reminderRepositoryProvider.overrideWithValue(reminders),
    notificationGatewayProvider.overrideWithValue(notifications),
    memorizationRepositoryProvider.overrideWithValue(memorization),
    duaRepositoryProvider.overrideWithValue(dua),
    shareRepositoryProvider.overrideWithValue(share),
    syncServiceProvider.overrideWithValue(sync),
    backgroundMaintenanceProvider.overrideWithValue(maintenance),
  ];
}
