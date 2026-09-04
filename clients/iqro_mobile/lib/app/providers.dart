import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/audio/audio_controller.dart';
import '../core/audio/audio_playback_store.dart';
import '../core/audio/audio_playback_sync_service.dart';
import '../core/auth/account_scope.dart';
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

  Future<void> setReaderTypography({
    required double arabicFontSize,
    required double lineHeight,
    required double ayahSpacing,
  }) => _set(
    state.copyWith(
      readerArabicFontSize: arabicFontSize
          .clamp(minReaderArabicFontSize, maxReaderArabicFontSize)
          .toDouble(),
      readerLineHeight: lineHeight
          .clamp(minReaderLineHeight, maxReaderLineHeight)
          .toDouble(),
      readerAyahSpacing: ayahSpacing
          .clamp(minReaderAyahSpacing, maxReaderAyahSpacing)
          .toDouble(),
    ),
  );

  Future<void> setReaderFocusMode(bool enabled) =>
      _set(state.copyWith(readerFocusMode: enabled));

  Future<void> setMushafVariant(String variant) =>
      _set(state.copyWith(mushafVariant: variant));

  Future<void> setPreferredTranslationSource(int sourceId) =>
      _set(state.copyWith(preferredTranslationSourceId: sourceId));

  Future<void> setPreferredTafsirSource(int sourceId) =>
      _set(state.copyWith(preferredTafsirSourceId: sourceId));

  Future<void> setPreferredRecitation(String recitationId) =>
      _set(state.copyWith(preferredRecitationId: recitationId));

  Future<void> setPreferredAudioQuality(String quality) => _set(
    state.copyWith(
      preferredAudioQuality: supportedAudioQualityPreferences.contains(quality)
          ? quality
          : defaultPreferredAudioQuality,
    ),
  );
}

final appPreferencesProvider =
    StateNotifierProvider<AppPreferencesController, AppPreferences>((ref) {
      return AppPreferencesController(
        ref.watch(preferencesStoreProvider),
        ref.watch(planRepositoryProvider),
      );
    });

class SessionController extends StateNotifier<AsyncValue<AuthSession?>> {
  SessionController(this._auth, this._notifications, this._locale)
    : super(const AsyncValue.loading()) {
    _authSubscription = _auth.sessionChanges.listen(_onSessionChanged);
    unawaited(initialize());
  }

  final AuthRepository _auth;
  final NotificationGateway _notifications;
  final String Function() _locale;
  late final StreamSubscription<AuthSession?> _authSubscription;
  var _hasObservedSession = false;
  String? _observedOwnerId;

  void _onSessionChanged(AuthSession? session) {
    if (!mounted) return;
    final previousOwnerId = _observedOwnerId;
    final nextOwnerId = session?.userId;
    _observedOwnerId = nextOwnerId;
    if (!_hasObservedSession) {
      _hasObservedSession = true;
      state = AsyncValue.data(session);
      return;
    }
    if (previousOwnerId == nextOwnerId) {
      state = AsyncValue.data(session);
      return;
    }
    state = nextOwnerId == null
        ? const AsyncValue.data(null)
        : const AsyncValue.loading();
    unawaited(_adoptChangedSession(session));
  }

  Future<void> _adoptChangedSession(AuthSession? session) async {
    await _cancelManagedBestEffort();
    if (!mounted || !identical(_auth.current, session)) return;
    state = AsyncValue.data(session);
  }

  Future<void> initialize() async {
    final cached = await _auth.loadCachedSession();
    if (!mounted) return;
    if (cached != null) {
      _hasObservedSession = true;
      _observedOwnerId = cached.userId;
      state = AsyncValue.data(cached);
    }
    try {
      final session = await _auth.ensureSession(locale: _locale());
      if (!mounted) return;
      _hasObservedSession = true;
      _observedOwnerId = session.userId;
      state = AsyncValue.data(session);
    } on Object catch (error, stack) {
      if (!mounted) return;
      if (cached == null || _auth.current == null) {
        state = AsyncValue.error(error, stack);
      }
    }
  }

  Future<EmailChallenge> startEmail(String email) =>
      _auth.startEmailVerification(email, locale: _locale());

  Future<void> verify(EmailChallenge challenge, String code) async {
    // Keep the source account visible while verification is in flight. A
    // transient/invalid-code response must not look like logout and dispose
    // every account-bound provider. AuthRepository publishes the target
    // session atomically on success; failures are returned to the screen.
    try {
      final session = await _auth.verifyEmail(
        challenge: challenge,
        code: code,
        locale: _locale(),
      );
      await _cancelManagedBestEffort();
      if (mounted) state = AsyncValue.data(session);
    } on Object catch (error, stack) {
      final current = _auth.current;
      if (mounted && current != null) state = AsyncValue.data(current);
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> signOut() async {
    // Drop every account-owned provider before secure storage or network work
    // so account A cannot remain visible while logout is in progress.
    state = const AsyncValue.loading();
    await _cancelManagedBestEffort();
    try {
      await _auth.clearSession();
    } on Object catch (error, stack) {
      // AuthRepository has already deactivated the in-memory scope. Never
      // strand the UI in loading or bootstrap a replacement session when the
      // durable logout fence itself could not be recorded.
      if (mounted) state = const AsyncValue.data(null);
      Error.throwWithStackTrace(error, stack);
    }
    if (!mounted) return;
    state = const AsyncValue.data(null);
    await initialize();
  }

  Future<void> _cancelManagedBestEffort() async {
    try {
      await _notifications.cancelAllManaged();
    } on Object {
      // The durable notification plan remains marked for cold-start cleanup.
      // A plugin/platform failure must never block auth isolation or logout.
    }
  }

  @override
  void dispose() {
    unawaited(_authSubscription.cancel());
    super.dispose();
  }
}

final sessionProvider =
    StateNotifierProvider<SessionController, AsyncValue<AuthSession?>>((ref) {
      return SessionController(
        ref.watch(authRepositoryProvider),
        ref.watch(notificationGatewayProvider),
        () => ref.read(appPreferencesProvider).locale,
      );
    });

typedef AccountScopeKey = ({String userId, int epoch});

AccountScopeKey accountScopeKey(AccountScopeSnapshot scope) =>
    (userId: scope.userId, epoch: scope.epoch);

final _accountScopeEpochProvider = Provider<int>((ref) {
  final scope = ref.watch(localDatabaseProvider).accountScope;
  final subscription = scope.changes.listen((_) => ref.invalidateSelf());
  ref.onDispose(() => unawaited(subscription.cancel()));
  return scope.epoch;
});

final activeAccountScopeKeyProvider = Provider<AccountScopeKey?>((ref) {
  ref.watch(_accountScopeEpochProvider);
  final session = ref.watch(sessionProvider);
  // Hide account-owned values for the whole transition window, including the
  // best-effort notification cancellation that precedes logout deactivation.
  if (session.isLoading || session.hasError) return null;
  final ownerId = session.valueOrNull?.userId;
  final scope = ref.watch(localDatabaseProvider).accountScope.current;
  return scope == null || scope.userId != ownerId
      ? null
      : accountScopeKey(scope);
});

final quranCatalogProvider = FutureProvider<QuranCatalog>((ref) {
  return ref.watch(quranRepositoryProvider).surahs();
});
final readingPositionProvider = FutureProvider.autoDispose
    .family<ReadingPosition, AccountScopeKey>((ref, key) {
      final database = ref.watch(localDatabaseProvider);
      final scope = database.accountScope.current;
      if (scope == null || accountScopeKey(scope) != key) {
        throw const AccountScopeChanged();
      }
      return ref.watch(quranRepositoryProvider).position(accountScope: scope);
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
final audioRecitationsProvider = FutureProvider<List<Recitation>>((ref) {
  return ref.watch(audioRepositoryProvider).recitations();
});
final memorizationRecitationsProvider = FutureProvider<List<Recitation>>((
  ref,
) async {
  final recitations = await ref.watch(audioRepositoryProvider).recitations();
  return recitations
      .where((item) => item.streamAllowed && item.timingsAvailable)
      .toList(growable: false);
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
  return ref.watch(duaRepositoryProvider).featuredEntries(locale);
});
final duaEntriesByCategoryProvider =
    FutureProvider.family<List<DuaEntry>, DuaCategoryIdentity>((ref, identity) {
      final locale = ref.watch(
        appPreferencesProvider.select((value) => value.locale),
      );
      return ref
          .watch(duaRepositoryProvider)
          .entries(
            locale,
            collection: identity.collection.isEmpty
                ? null
                : identity.collection,
            category: identity.slug,
          );
    });

typedef DuaSearchQuery = ({String query, String? collection, String? category});

final duaSearchProvider = FutureProvider.autoDispose
    .family<List<DuaEntry>, DuaSearchQuery>((ref, request) {
      final locale = ref.watch(
        appPreferencesProvider.select((value) => value.locale),
      );
      return ref
          .watch(duaRepositoryProvider)
          .search(
            locale,
            request.query,
            collection: request.collection,
            category: request.category,
          );
    });

final duaEntryProvider = FutureProvider.autoDispose.family<DuaEntry, String>((
  ref,
  id,
) {
  final locale = ref.watch(
    appPreferencesProvider.select((value) => value.locale),
  );
  return ref.watch(duaRepositoryProvider).entry(locale, id);
});
final duaEntryByReferenceProvider = FutureProvider.autoDispose
    .family<DuaEntry, DuaEntryIdentity>((ref, identity) {
      final locale = ref.watch(
        appPreferencesProvider.select((value) => value.locale),
      );
      return ref
          .watch(duaRepositoryProvider)
          .entryByReference(
            locale,
            collection: identity.collection,
            sourceNumber: identity.sourceNumber,
          );
    });
final prayerScheduleProvider = FutureProvider.autoDispose
    .family<PrayerSchedule?, AccountScopeKey>((ref, key) {
      final database = ref.watch(localDatabaseProvider);
      final scope = database.accountScope.current;
      if (scope == null || accountScopeKey(scope) != key) {
        throw const AccountScopeChanged();
      }
      return ref
          .watch(prayerRepositoryProvider)
          .cachedToday(accountScope: scope);
    });
final prayerMethodsProvider = FutureProvider<List<PrayerMethod>>((ref) {
  return ref.watch(prayerRepositoryProvider).methods();
});

final reminderProvider =
    StateNotifierProvider<ReminderController, ReminderState>((ref) {
      final accountKey = ref.watch(activeAccountScopeKeyProvider);
      final database = ref.watch(localDatabaseProvider);
      final currentScope = database.accountScope.current;
      final boundScope =
          currentScope != null &&
              accountKey != null &&
              accountScopeKey(currentScope) == accountKey
          ? currentScope
          : null;
      return ReminderController(
        repository: ref.watch(reminderRepositoryProvider),
        notifications: ref.watch(notificationGatewayProvider),
        prayerRepository: ref.watch(prayerRepositoryProvider),
        database: database,
        accountScope: boundScope,
        locale: () => ref.read(appPreferencesProvider).locale,
      );
    });

class PlanController extends StateNotifier<AsyncValue<DailyPlan>> {
  PlanController(
    this._repository, {
    required LocalDatabase database,
    required AccountScopeSnapshot? accountScope,
    required int? preferredTarget,
  }) : _database = database,
       _accountScope = accountScope,
       _preferredTarget = preferredTarget,
       super(const AsyncValue.loading()) {
    unawaited(reload());
  }
  final PlanRepository _repository;
  final LocalDatabase _database;
  final AccountScopeSnapshot? _accountScope;
  final int? _preferredTarget;

  bool isBoundTo(AccountScopeSnapshot scope) {
    final bound = _accountScope;
    return bound != null &&
        bound.userId == scope.userId &&
        bound.epoch == scope.epoch &&
        _database.accountScope.isCurrent(bound);
  }

  Future<void> reload() => _replace(
    (scope) => _repository.load(
      preferredTarget: _preferredTarget,
      accountScope: scope,
    ),
  );

  Future<void> addPages(int pages) =>
      _replace((scope) => _repository.addPages(pages, accountScope: scope));

  Future<void> setPrayerPages(String prayer, int pages) => _replace(
    (scope) => _repository.setPrayerPages(prayer, pages, accountScope: scope),
  );

  Future<void> _replace(
    Future<DailyPlan> Function(AccountScopeSnapshot scope) load,
  ) async {
    final scope = _accountScope;
    if (scope == null) return;
    try {
      final next = await load(scope);
      _database.ensureCurrent(scope);
      if (mounted) state = AsyncValue.data(next);
    } on AccountScopeChanged {
      // A disposed controller must never retry an A action under account B.
    } on Object catch (error, stack) {
      if (mounted && _database.accountScope.isCurrent(scope)) {
        state = AsyncValue.error(error, stack);
      }
    }
  }
}

final planProvider =
    StateNotifierProvider<PlanController, AsyncValue<DailyPlan>>((ref) {
      final accountKey = ref.watch(activeAccountScopeKeyProvider);
      final database = ref.watch(localDatabaseProvider);
      final currentScope = database.accountScope.current;
      final boundScope =
          currentScope != null &&
              accountKey != null &&
              accountScopeKey(currentScope) == accountKey
          ? currentScope
          : null;
      final preferences = ref.watch(appPreferencesProvider);
      final preferredTarget = preferences.dailyUnit == DailyUnit.pages
          ? preferences.dailyTarget
          : null;
      return PlanController(
        ref.watch(planRepositoryProvider),
        database: database,
        accountScope: boundScope,
        preferredTarget: preferredTarget,
      );
    });

class MemorizationController
    extends StateNotifier<AsyncValue<MemorizationDashboard>> {
  MemorizationController(
    this._repository, {
    required LocalDatabase database,
    required AccountScopeSnapshot? accountScope,
  }) : _database = database,
       _accountScope = accountScope,
       super(const AsyncValue.loading()) {
    if (accountScope != null) unawaited(reload());
  }
  final MemorizationRepository _repository;
  final LocalDatabase _database;
  final AccountScopeSnapshot? _accountScope;

  Future<void> reload() => _replace(
    (scope) => _repository.load(accountScope: scope),
    propagateError: false,
  );

  Future<void> savePlan(
    MemorizationPlanDraft draft, {
    required int baseRevision,
  }) => _replace(
    (scope) => _repository.savePlan(
      draft,
      baseRevision: baseRevision,
      accountScope: scope,
    ),
  );

  Future<void> assess(MemorizationAssessment value) =>
      _replace((scope) => _repository.assess(value, accountScope: scope));

  Future<void> reset() =>
      _replace((scope) => _repository.reset(accountScope: scope));

  Future<void> _replace(
    Future<MemorizationDashboard> Function(AccountScopeSnapshot scope) load, {
    bool propagateError = true,
  }) async {
    final scope = _accountScope;
    if (scope == null) return;
    try {
      final next = await load(scope);
      _database.ensureCurrent(scope);
      if (mounted) state = AsyncValue.data(next);
    } on AccountScopeChanged {
      // A provider from a previous account epoch is expected to stop here.
    } on Object catch (error, stack) {
      if (mounted && _database.accountScope.isCurrent(scope)) {
        state = AsyncValue.error(error, stack);
      }
      if (propagateError) rethrow;
    }
  }
}

final memorizationProvider =
    StateNotifierProvider<
      MemorizationController,
      AsyncValue<MemorizationDashboard>
    >((ref) {
      final accountKey = ref.watch(activeAccountScopeKeyProvider);
      final database = ref.watch(localDatabaseProvider);
      final currentScope = database.accountScope.current;
      final boundScope =
          currentScope != null &&
              accountKey != null &&
              accountScopeKey(currentScope) == accountKey
          ? currentScope
          : null;
      return MemorizationController(
        ref.watch(memorizationRepositoryProvider),
        database: database,
        accountScope: boundScope,
      );
    });

final audioControllerProvider =
    StateNotifierProvider<AudioController, IqroAudioState>((ref) {
      final accountKey = ref.watch(activeAccountScopeKeyProvider);
      final database = ref.watch(localDatabaseProvider);
      final currentScope = database.accountScope.current;
      final boundScope =
          currentScope != null &&
              accountKey != null &&
              accountScopeKey(currentScope) == accountKey
          ? currentScope
          : null;
      final controller = AudioController(
        playbackStore: boundScope == null
            ? null
            : AudioPlaybackStore(database, accountScope: boundScope),
      );
      if (boundScope != null) unawaited(controller.restore());
      return controller;
    });

class SyncController extends StateNotifier<SyncReport> {
  SyncController(
    this._service, {
    required LocalDatabase database,
    required AccountScopeSnapshot? accountScope,
  }) : _database = database,
       _accountScope = accountScope,
       super(const SyncReport(status: SyncStatus.idle));
  final SyncService _service;
  final LocalDatabase _database;
  final AccountScopeSnapshot? _accountScope;
  Future<SyncReport> run() async {
    final scope = _accountScope;
    if (scope == null) throw const AccountScopeChanged();
    _database.ensureCurrent(scope);
    state = const SyncReport(status: SyncStatus.syncing);
    try {
      final result = await _service.synchronize(accountScope: scope);
      _database.ensureCurrent(scope);
      if (mounted) state = result;
      return result;
    } on AccountScopeChanged {
      rethrow;
    } on Object catch (error) {
      if (mounted && _database.accountScope.isCurrent(scope)) {
        state = SyncReport(
          status: SyncStatus.failed,
          message: error.toString(),
        );
      }
      rethrow;
    }
  }
}

final syncProvider = StateNotifierProvider<SyncController, SyncReport>((ref) {
  final accountKey = ref.watch(activeAccountScopeKeyProvider);
  final database = ref.watch(localDatabaseProvider);
  final currentScope = database.accountScope.current;
  final boundScope =
      currentScope != null &&
          accountKey != null &&
          accountScopeKey(currentScope) == accountKey
      ? currentScope
      : null;
  return SyncController(
    ref.watch(syncServiceProvider),
    database: database,
    accountScope: boundScope,
  );
});
