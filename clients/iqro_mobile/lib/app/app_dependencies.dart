import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/auth/auth_repository.dart';
import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/notifications/notification_gateway.dart';
import '../core/storage/local_database.dart';
import '../core/storage/preferences_store.dart';
import '../core/sync/sync_service.dart';
import '../features/audio/audio_repository.dart';
import '../features/dua/dua_repository.dart';
import '../features/memorization/memorization_repository.dart';
import '../features/plan/plan_repository.dart';
import '../features/prayer/prayer_repository.dart';
import '../features/quran/quran_repository.dart';
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
    required this.audio,
    required this.plan,
    required this.prayer,
    required this.reminders,
    required this.notifications,
    required this.memorization,
    required this.dua,
    required this.share,
    required this.sync,
  });

  final AppConfig config;
  final PreferencesStore preferences;
  final LocalDatabase database;
  final AuthRepository auth;
  final ApiClient api;
  final QuranRepository quran;
  final AudioRepository audio;
  final PlanRepository plan;
  final PrayerRepository prayer;
  final ReminderRepository reminders;
  final NotificationGateway notifications;
  final MemorizationRepository memorization;
  final DuaRepository dua;
  final ShareRepository share;
  final SyncService sync;

  static Future<AppDependencies> initialize() async {
    final config = AppConfig.fromEnvironment();
    final sharedPreferences = await SharedPreferences.getInstance();
    final preferences = PreferencesStore(sharedPreferences);
    final database = await LocalDatabase.open();
    final auth = AuthRepository(config: config);
    final api = ApiClient(
      config: config,
      authRepository: auth,
      locale: () => preferences.read().locale,
    );
    final prayer = PrayerRepository(api: api, database: database);
    final reminders = ReminderRepository(api: api, database: database);
    final notifications = NotificationGateway(database: database);
    await notifications.initialize();
    return AppDependencies._(
      config: config,
      preferences: preferences,
      database: database,
      auth: auth,
      api: api,
      quran: QuranRepository(api: api, database: database),
      audio: AudioRepository(api: api, database: database),
      plan: PlanRepository(database),
      prayer: prayer,
      reminders: reminders,
      notifications: notifications,
      memorization: MemorizationRepository(database),
      dua: DuaRepository(api: api, database: database),
      share: ShareRepository(
        api: api,
        config: config,
        database: database,
        auth: auth,
      ),
      sync: SyncService(api: api, database: database),
    );
  }

  List<Override> get overrides => <Override>[
    appConfigProvider.overrideWithValue(config),
    preferencesStoreProvider.overrideWithValue(preferences),
    localDatabaseProvider.overrideWithValue(database),
    authRepositoryProvider.overrideWithValue(auth),
    apiClientProvider.overrideWithValue(api),
    quranRepositoryProvider.overrideWithValue(quran),
    audioRepositoryProvider.overrideWithValue(audio),
    planRepositoryProvider.overrideWithValue(plan),
    prayerRepositoryProvider.overrideWithValue(prayer),
    reminderRepositoryProvider.overrideWithValue(reminders),
    notificationGatewayProvider.overrideWithValue(notifications),
    memorizationRepositoryProvider.overrideWithValue(memorization),
    duaRepositoryProvider.overrideWithValue(dua),
    shareRepositoryProvider.overrideWithValue(share),
    syncServiceProvider.overrideWithValue(sync),
  ];
}
