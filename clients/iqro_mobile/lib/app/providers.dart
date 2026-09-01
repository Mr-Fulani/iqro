import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/audio_controller.dart';
import '../core/audio/audio_playback_store.dart';
import '../core/audio/audio_playback_sync_service.dart';
import '../core/auth/auth_repository.dart';
import '../core/auth/auth_session.dart';
import '../core/background/background_maintenance_service.dart';
import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/notifications/notification_gateway.dart';
import '../core/storage/local_database.dart';
import '../core/storage/preferences_store.dart';
import '../core/sync/sync_service.dart';
import '../features/audio/audio_models.dart';
import '../features/audio/audio_offline_repository.dart';
import '../features/audio/audio_repository.dart';
import '../features/audio/reciter_catalog.dart';
import '../features/dua/dua_repository.dart';
import '../features/memorization/memorization_repository.dart';
import '../features/plan/plan_repository.dart';
import '../features/prayer/prayer_repository.dart';
import '../features/quran/quran_models.dart';
import '../features/quran/mushaf_offline_repository.dart';
import '../features/quran/quran_repository.dart';
import '../features/reminders/reminder_controller.dart';
import '../features/reminders/reminder_models.dart';
import '../features/reminders/reminder_repository.dart';
import '../features/share/share_repository.dart';

Never _missing(String name) => throw StateError('$name was not initialized');

final appConfigProvider = Provider<AppConfig>((ref) => _missing('AppConfig'));
final preferencesStoreProvider = Provider<PreferencesStore>(
  (ref) => _missing('PreferencesStore'),
);
final localDatabaseProvider = Provider<LocalDatabase>(
  (ref) => _missing('LocalDatabase'),
);
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => _missing('AuthRepository'),
);
final apiClientProvider = Provider<ApiClient>((ref) => _missing('ApiClient'));
final quranRepositoryProvider = Provider<QuranRepository>(
  (ref) => _missing('QuranRepository'),
);
final mushafOfflineRepositoryProvider = Provider<MushafOfflineRepository>(
  (ref) => _missing('MushafOfflineRepository'),
);
final audioRepositoryProvider = Provider<AudioRepository>(
  (ref) => _missing('AudioRepository'),
);
final audioOfflineRepositoryProvider = Provider<AudioOfflineRepository>(
  (ref) => _missing('AudioOfflineRepository'),
);
final audioPlaybackSyncProvider = Provider<AudioPlaybackSyncService>(
  (ref) => _missing('AudioPlaybackSyncService'),
);
final planRepositoryProvider = Provider<PlanRepository>(
  (ref) => _missing('PlanRepository'),
);
final prayerRepositoryProvider = Provider<PrayerRepository>(
  (ref) => _missing('PrayerRepository'),
);
final reminderRepositoryProvider = Provider<ReminderRepository>(
  (ref) => _missing('ReminderRepository'),
);
final notificationGatewayProvider = Provider<NotificationGateway>(
  (ref) => _missing('NotificationGateway'),
);
final memorizationRepositoryProvider = Provider<MemorizationRepository>(
  (ref) => _missing('MemorizationRepository'),
);
final duaRepositoryProvider = Provider<DuaRepository>(
  (ref) => _missing('DuaRepository'),
);
final shareRepositoryProvider = Provider<ShareRepository>(
  (ref) => _missing('ShareRepository'),
);
final syncServiceProvider = Provider<SyncService>(
  (ref) => _missing('SyncService'),
);
final backgroundMaintenanceProvider = Provider<BackgroundMaintenanceService>(
  (ref) => _missing('BackgroundMaintenanceService'),
);

class AppPreferencesController extends StateNotifier<AppPreferences> {
  AppPreferencesController(this._store, this._plan) : super(_store.read());
  final PreferencesStore _store;
  final PlanRepository _plan;

  Future<void> _set(AppPreferences value) async {
    state = value;
    await _store.write(value);
  }

  Future<void> completeOnboarding({
    required String locale,
    required String goal,
    required DailyUnit unit,
    required int target,
  }) async {
    await _set(
      state.copyWith(
        onboardingComplete: true,
        locale: locale,
        goal: goal,
        dailyUnit: unit,
        dailyTarget: target,
      ),
    );
    await _plan.initialize(target: unit == DailyUnit.pages ? target : 6);
  }

  Future<void> setLocale(String locale) => _set(state.copyWith(locale: locale));
  Future<void> setTheme(ThemeMode mode) =>
      _set(state.copyWith(themeMode: mode));
  Future<void> setReaderMode(ReaderMode mode) =>
      _set(state.copyWith(readerMode: mode));

  Future<void> setMushafVariant(String variant) =>
      _set(state.copyWith(mushafVariant: variant));

  Future<void> setPreferredTranslationSource(int sourceId) =>
      _set(state.copyWith(preferredTranslationSourceId: sourceId));

  Future<void> setPreferredTafsirSource(int sourceId) =>
      _set(state.copyWith(preferredTafsirSourceId: sourceId));

  Future<void> setPreferredRecitation(String recitationId) =>
      _set(state.copyWith(preferredRecitationId: recitationId));
}

final appPreferencesProvider =
    StateNotifierProvider<AppPreferencesController, AppPreferences>((ref) {
      return AppPreferencesController(
        ref.watch(preferencesStoreProvider),
        ref.watch(planRepositoryProvider),
      );
    });

class SessionController extends StateNotifier<AsyncValue<AuthSession?>> {
  SessionController(this._auth, this._locale)
    : super(const AsyncValue.loading()) {
    unawaited(initialize());
  }

  final AuthRepository _auth;
  final String Function() _locale;

  Future<void> initialize() async {
    final cached = await _auth.loadCachedSession();
    if (cached != null) state = AsyncValue.data(cached);
    try {
      state = AsyncValue.data(await _auth.ensureSession(locale: _locale()));
    } on Object catch (error, stack) {
      if (cached == null) state = AsyncValue.error(error, stack);
    }
  }

  Future<EmailChallenge> startEmail(String email) =>
      _auth.startEmailVerification(email, locale: _locale());

  Future<void> verify(EmailChallenge challenge, String code) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => _auth.verifyEmail(
        challenge: challenge,
        code: code,
        locale: _locale(),
      ),
    );
  }

  Future<void> signOut() async {
    await _auth.clearSession();
    state = const AsyncValue.data(null);
    await initialize();
  }
}

final sessionProvider =
    StateNotifierProvider<SessionController, AsyncValue<AuthSession?>>((ref) {
      return SessionController(
        ref.watch(authRepositoryProvider),
        () => ref.read(appPreferencesProvider).locale,
      );
    });

final quranCatalogProvider = FutureProvider<QuranCatalog>((ref) {
  return ref.watch(quranRepositoryProvider).surahs();
});
final readingPositionProvider = FutureProvider<ReadingPosition>((ref) {
  return ref.watch(quranRepositoryProvider).position();
});
final ayahsProvider = FutureProvider.family<List<QuranAyah>, int>((ref, surah) {
  return ref.watch(quranRepositoryProvider).ayahs(surah);
});
final quranJuzProvider = FutureProvider<List<QuranDivision>>((ref) {
  return ref.watch(quranRepositoryProvider).juz();
});
final mushafPageProvider = FutureProvider.autoDispose
    .family<MushafPageData, int>((ref, page) {
      return ref.watch(quranRepositoryProvider).mushafPage(page);
    });

class MushafDownloadController extends StateNotifier<MushafDownloadSnapshot> {
  MushafDownloadController(this._repository)
    : super(const MushafDownloadSnapshot.empty()) {
    unawaited(initialize());
  }

  final MushafOfflineRepository _repository;

  Future<void> initialize() async {
    state = await _repository.snapshot();
  }

  Future<void> download({int? width}) async {
    if (state.status == MushafDownloadStatus.downloading) return;
    state = MushafDownloadSnapshot(
      status: MushafDownloadStatus.downloading,
      packageId: state.packageId,
      completedPages: state.completedPages,
      totalPages: state.totalPages,
      downloadedBytes: state.downloadedBytes,
      totalBytes: state.totalBytes,
    );
    try {
      state = await _repository.install(
        width: width,
        onProgress: (progress) => state = progress,
      );
      for (var page = 1; page <= state.totalPages; page += 1) {
        refInvalidateMushafPage?.call(page);
      }
    } on Object catch (error) {
      final persisted = await _repository.snapshot();
      state = MushafDownloadSnapshot(
        status: MushafDownloadStatus.failed,
        packageId: persisted.packageId,
        completedPages: persisted.completedPages,
        totalPages: persisted.totalPages,
        downloadedBytes: persisted.downloadedBytes,
        totalBytes: persisted.totalBytes,
        error: error.toString(),
      );
    }
  }

  void Function(int page)? refInvalidateMushafPage;
}

final mushafDownloadProvider =
    StateNotifierProvider<MushafDownloadController, MushafDownloadSnapshot>((
      ref,
    ) {
      final controller = MushafDownloadController(
        ref.watch(mushafOfflineRepositoryProvider),
      );
      controller.refInvalidateMushafPage = (page) =>
          ref.invalidate(mushafPageProvider(page));
      return controller;
    });
final recitersProvider = FutureProvider<List<Reciter>>((ref) {
  return ref.watch(audioRepositoryProvider).reciters();
});
final recitationVariantsProvider =
    FutureProvider.family<List<Recitation>, String>((ref, personKey) async {
      final reciters = await ref.watch(recitersProvider.future);
      final people = groupRecitersByPerson(reciters);
      final person = people.where((item) => item.key == personKey).firstOrNull;
      if (person == null) return const <Recitation>[];
      return ref
          .watch(audioRepositoryProvider)
          .recitationsForReciters(person.sources.map((item) => item.id));
    });

class AudioDownloadController extends StateNotifier<AudioDownloadSnapshot> {
  AudioDownloadController(this._repository, this._recitationId)
    : super(AudioDownloadSnapshot.empty(_recitationId)) {
    unawaited(initialize());
  }

  final AudioOfflineRepository _repository;
  final String _recitationId;

  Future<void> initialize() async {
    state = await _repository.snapshot(_recitationId);
  }

  Future<void> download({String? quality}) async {
    if (state.status == AudioDownloadStatus.downloading) return;
    final requestedQuality =
        quality ?? (state.quality == 'default' ? null : state.quality);
    state = AudioDownloadSnapshot(
      status: AudioDownloadStatus.downloading,
      recitationId: _recitationId,
      packageId: state.packageId,
      quality: requestedQuality ?? state.quality,
      completedTracks: state.completedTracks,
      totalTracks: state.totalTracks,
      downloadedBytes: state.downloadedBytes,
      totalBytes: state.totalBytes,
    );
    try {
      state = await _repository.install(
        recitationId: _recitationId,
        quality: requestedQuality,
        onProgress: (progress) => state = progress,
      );
    } on Object catch (error) {
      final persisted = await _repository.snapshot(_recitationId);
      state = AudioDownloadSnapshot(
        status: AudioDownloadStatus.failed,
        recitationId: _recitationId,
        packageId: persisted.packageId,
        quality: persisted.quality,
        completedTracks: persisted.completedTracks,
        totalTracks: persisted.totalTracks,
        downloadedBytes: persisted.downloadedBytes,
        totalBytes: persisted.totalBytes,
        error: error.toString(),
      );
    }
  }
}

final audioDownloadProvider = StateNotifierProvider.autoDispose
    .family<AudioDownloadController, AudioDownloadSnapshot, String>((
      ref,
      recitationId,
    ) {
      return AudioDownloadController(
        ref.watch(audioOfflineRepositoryProvider),
        recitationId,
      );
    });
final duaCategoriesProvider = FutureProvider<List<DuaCategory>>((ref) {
  final locale = ref.watch(
    appPreferencesProvider.select((value) => value.locale),
  );
  return ref.watch(duaRepositoryProvider).categories(locale);
});
final duaEntriesProvider = FutureProvider<List<DuaEntry>>((ref) {
  final locale = ref.watch(
    appPreferencesProvider.select((value) => value.locale),
  );
  return ref.watch(duaRepositoryProvider).entries(locale);
});
final duaEntriesByCategoryProvider =
    FutureProvider.family<List<DuaEntry>, String?>((ref, category) {
      final locale = ref.watch(
        appPreferencesProvider.select((value) => value.locale),
      );
      return ref
          .watch(duaRepositoryProvider)
          .entries(locale, category: category);
    });
final prayerScheduleProvider = FutureProvider<PrayerSchedule?>((ref) {
  return ref.watch(prayerRepositoryProvider).cachedToday();
});
final prayerMethodsProvider = FutureProvider<List<PrayerMethod>>((ref) {
  return ref.watch(prayerRepositoryProvider).methods();
});

final reminderProvider =
    StateNotifierProvider<ReminderController, ReminderState>((ref) {
      return ReminderController(
        repository: ref.watch(reminderRepositoryProvider),
        notifications: ref.watch(notificationGatewayProvider),
        prayerRepository: ref.watch(prayerRepositoryProvider),
        locale: () => ref.read(appPreferencesProvider).locale,
      );
    });

class PlanController extends StateNotifier<AsyncValue<DailyPlan>> {
  PlanController(this._repository, {required int? preferredTarget})
    : _preferredTarget = preferredTarget,
      super(const AsyncValue.loading()) {
    unawaited(reload());
  }
  final PlanRepository _repository;
  final int? _preferredTarget;
  Future<void> reload() async => state = await AsyncValue.guard(
    () => _repository.load(preferredTarget: _preferredTarget),
  );
  Future<void> addPages(int pages) async =>
      state = await AsyncValue.guard(() => _repository.addPages(pages));
  Future<void> setPrayerPages(String prayer, int pages) async => state =
      await AsyncValue.guard(() => _repository.setPrayerPages(prayer, pages));
}

final planProvider =
    StateNotifierProvider<PlanController, AsyncValue<DailyPlan>>((ref) {
      final preferences = ref.watch(appPreferencesProvider);
      final preferredTarget = preferences.dailyUnit == DailyUnit.pages
          ? preferences.dailyTarget
          : null;
      return PlanController(
        ref.watch(planRepositoryProvider),
        preferredTarget: preferredTarget,
      );
    });

class MemorizationController
    extends StateNotifier<AsyncValue<MemorizationState>> {
  MemorizationController(this._repository) : super(const AsyncValue.loading()) {
    unawaited(reload());
  }
  final MemorizationRepository _repository;
  Future<void> reload() async =>
      state = await AsyncValue.guard(_repository.load);
  Future<void> assess(String value) async =>
      state = await AsyncValue.guard(() => _repository.assess(value));
  Future<void> reset() async =>
      state = await AsyncValue.guard(_repository.reset);
}

final memorizationProvider =
    StateNotifierProvider<
      MemorizationController,
      AsyncValue<MemorizationState>
    >((ref) {
      return MemorizationController(ref.watch(memorizationRepositoryProvider));
    });

final audioControllerProvider =
    StateNotifierProvider<AudioController, IqroAudioState>((ref) {
      final controller = AudioController(
        playbackStore: AudioPlaybackStore(ref.watch(localDatabaseProvider)),
      );
      unawaited(controller.restore());
      ref.onDispose(controller.dispose);
      return controller;
    });

class SyncController extends StateNotifier<SyncReport> {
  SyncController(this._service)
    : super(const SyncReport(status: SyncStatus.idle));
  final SyncService _service;
  Future<SyncReport> run() async {
    state = const SyncReport(status: SyncStatus.syncing);
    state = await _service.synchronize();
    return state;
  }
}

final syncProvider = StateNotifierProvider<SyncController, SyncReport>((ref) {
  return SyncController(ref.watch(syncServiceProvider));
});
