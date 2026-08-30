import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/audio_controller.dart';
import '../core/auth/auth_repository.dart';
import '../core/auth/auth_session.dart';
import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/storage/local_database.dart';
import '../core/storage/preferences_store.dart';
import '../core/sync/sync_service.dart';
import '../features/audio/audio_models.dart';
import '../features/audio/audio_repository.dart';
import '../features/dua/dua_repository.dart';
import '../features/memorization/memorization_repository.dart';
import '../features/plan/plan_repository.dart';
import '../features/prayer/prayer_repository.dart';
import '../features/quran/quran_models.dart';
import '../features/quran/quran_repository.dart';
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
final audioRepositoryProvider = Provider<AudioRepository>(
  (ref) => _missing('AudioRepository'),
);
final planRepositoryProvider = Provider<PlanRepository>(
  (ref) => _missing('PlanRepository'),
);
final prayerRepositoryProvider = Provider<PrayerRepository>(
  (ref) => _missing('PrayerRepository'),
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

class AppPreferencesController extends StateNotifier<AppPreferences> {
  AppPreferencesController(this._store) : super(_store.read());
  final PreferencesStore _store;

  Future<void> _set(AppPreferences value) async {
    state = value;
    await _store.write(value);
  }

  Future<void> completeOnboarding({
    required String locale,
    required String goal,
    required DailyUnit unit,
    required int target,
  }) => _set(
    state.copyWith(
      onboardingComplete: true,
      locale: locale,
      goal: goal,
      dailyUnit: unit,
      dailyTarget: target,
    ),
  );

  Future<void> setLocale(String locale) => _set(state.copyWith(locale: locale));
  Future<void> setTheme(ThemeMode mode) =>
      _set(state.copyWith(themeMode: mode));
  Future<void> setReaderMode(ReaderMode mode) =>
      _set(state.copyWith(readerMode: mode));
}

final appPreferencesProvider =
    StateNotifierProvider<AppPreferencesController, AppPreferences>((ref) {
      return AppPreferencesController(ref.watch(preferencesStoreProvider));
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
final mushafPageProvider = FutureProvider.family<MushafPageData, int>((
  ref,
  page,
) {
  return ref.watch(quranRepositoryProvider).mushafPage(page);
});
final recitersProvider = FutureProvider<List<Reciter>>((ref) {
  return ref.watch(audioRepositoryProvider).reciters();
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

class PlanController extends StateNotifier<AsyncValue<DailyPlan>> {
  PlanController(this._repository) : super(const AsyncValue.loading()) {
    unawaited(reload());
  }
  final PlanRepository _repository;
  Future<void> reload() async =>
      state = await AsyncValue.guard(_repository.load);
  Future<void> addPages(int pages) async =>
      state = await AsyncValue.guard(() => _repository.addPages(pages));
  Future<void> setPrayerPages(String prayer, int pages) async => state =
      await AsyncValue.guard(() => _repository.setPrayerPages(prayer, pages));
}

final planProvider =
    StateNotifierProvider<PlanController, AsyncValue<DailyPlan>>((ref) {
      return PlanController(ref.watch(planRepositoryProvider));
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
      final controller = AudioController();
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
