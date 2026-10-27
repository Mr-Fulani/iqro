import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../core/analytics/analytics.dart';
import '../core/audio/audio_controller.dart';
import '../core/audio/audio_playback_store.dart';
import '../core/audio/audio_playback_sync_service.dart';
import '../core/audio/listening_media_controls.dart';
import '../core/auth/account_scope.dart';
import '../core/auth/auth_repository.dart';
import '../core/auth/auth_session.dart';
import '../core/auth/google_sign_in_gateway.dart';
import '../core/background/background_maintenance_service.dart';
import '../core/config/app_config.dart';
import '../core/network/api_client.dart';
import '../core/notifications/notification_gateway.dart';
import '../core/storage/cache_maintenance.dart';
import '../core/storage/local_database.dart';
import '../core/storage/preferences_store.dart';
import '../core/sync/sync_service.dart';
import '../features/audio/audio_models.dart';
import '../features/audio/audio_offline_repository.dart';
import '../features/audio/audio_repository.dart';
import '../features/audio/listening_queue.dart';
import '../features/audio/player_backgrounds.dart';
import '../features/audio/reciter_catalog.dart';
import '../features/courses/course_feedback.dart';
import '../features/courses/course_models.dart';
import '../features/courses/course_progress_store.dart';
import '../features/courses/course_repository.dart';
import '../features/courses/lesson_media_cache.dart';
import '../features/dua/dua_repository.dart';
import '../features/dua/dua_topics.dart';
import '../features/feedback/feedback_models.dart';
import '../features/feedback/feedback_repository.dart';
import '../features/memorization/memorization_repository.dart';
import '../features/plan/plan_repository.dart';
import '../features/plan/plan_widget_service.dart';
import '../features/prayer/prayer_repository.dart';
import '../features/prayer/prayer_widget_service.dart';
import '../features/quran/quran_models.dart';
import '../features/quran/mushaf_edition.dart';
import '../features/quran/mushaf_offline_repository.dart';
import '../features/quran/mushaf_thumbnail_cache.dart';
import '../features/quran/quran_repository.dart';
import '../features/reminders/reminder_controller.dart';
import '../features/reminders/reminder_models.dart';
import '../features/reminders/reminder_repository.dart';
import '../features/salah/salah_3d.dart';
import '../features/salah/salah_display.dart';
import '../features/salah/salah_models.dart';
import '../features/salah/salah_offline_repository.dart';
import '../features/salah/salah_progress.dart';
import '../features/salah/salah_repository.dart';
import '../features/share/share_repository.dart';
import '../features/settings/offline_storage_repository.dart';
import '../features/tajweed/tajweed_models.dart';
import '../features/tajweed/tajweed_repository.dart';
import '../features/tajweed_course/tajweed_course_models.dart';
import '../features/tajweed_course/tajweed_course_progress.dart';
import '../features/tajweed_course/tajweed_course_repository.dart';
import '../features/tajweed_course/tajweed_practice.dart';
import '../features/tajweed_course/tajweed_practice_store.dart';
import '../l10n/generated/app_localizations.dart';

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

/// Drawn edition miniatures. The app stores them on disk; without that
/// override they last for this run only.
final mushafThumbnailCacheProvider = Provider<MushafThumbnailCache>(
  (ref) => MushafThumbnailCache.memory(),
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
final planWidgetServiceProvider = Provider<PlanWidgetService>(
  (ref) => PlanWidgetService(database: ref.watch(localDatabaseProvider)),
);
final planUpdatesProvider = StreamProvider<int>(
  (ref) => ref.watch(planRepositoryProvider).updates,
);
final prayerRepositoryProvider = Provider<PrayerRepository>(
  (ref) => _missing('PrayerRepository'),
);
final prayerWidgetServiceProvider = Provider<PrayerWidgetService>(
  (ref) => _missing('PrayerWidgetService'),
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
final salahRepositoryProvider = Provider<SalahRepository>(
  (ref) => _missing('SalahRepository'),
);
final feedbackRepositoryProvider = Provider<FeedbackRepository>(
  (ref) => _missing('FeedbackRepository'),
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
final offlineStorageRepositoryProvider = Provider<OfflineStorageRepository>(
  (ref) => OfflineStorageRepository(database: ref.watch(localDatabaseProvider)),
);
final cacheMaintenanceProvider = Provider<CacheMaintenance>(
  (ref) => CacheMaintenance(database: ref.watch(localDatabaseProvider)),
);
final offlinePackagesProvider =
    FutureProvider.autoDispose<List<OfflinePackageSummary>>(
      (ref) => ref.watch(offlineStorageRepositoryProvider).packages(),
    );

class AppPreferencesController extends StateNotifier<AppPreferences> {
  AppPreferencesController(
    this._store,
    this._plan, {
    AccountScope? accountScope,
  }) : _accountScope = accountScope,
       _boundScope = accountScope?.current,
       super(
         accountScope == null
             ? _store.read()
             : _store.readForAccount(accountScope.current?.userId),
       );
  final PreferencesStore _store;
  final PlanRepository _plan;
  final AccountScope? _accountScope;
  final AccountScopeSnapshot? _boundScope;

  bool get _canWrite {
    final accountScope = _accountScope;
    if (accountScope == null) return true;
    final boundScope = _boundScope;
    return boundScope == null
        ? accountScope.current == null
        : accountScope.isCurrent(boundScope);
  }

  Future<void> _set(AppPreferences value) async {
    if (!_canWrite) return;
    state = value;
    await _store.write(value, includeLegacyRecitations: _accountScope == null);
  }

  Future<void> _setRecitation(
    RecitationPreferenceRole role,
    String recitationId,
  ) async {
    if (!_canWrite || (_accountScope != null && _boundScope == null)) return;
    state = switch (role) {
      RecitationPreferenceRole.listening => state.copyWith(
        listeningRecitationId: recitationId,
      ),
      RecitationPreferenceRole.mushaf => state.copyWith(
        mushafRecitationId: recitationId,
      ),
      RecitationPreferenceRole.memorization => state.copyWith(
        memorizationDefaultRecitationId: recitationId,
      ),
    };
    final ownerId = _boundScope?.userId;
    if (ownerId == null) {
      await _store.writeLegacyRecitation(role, recitationId);
    } else {
      await _store.writeAccountRecitation(ownerId, role, recitationId);
    }
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
    await _plan.initialize(
      target: target,
      metric: readingMetricForDailyUnit(unit),
    );
  }

  /// First launch: start in the phone's language when IQRO has it.
  Future<void> adoptDeviceLocale(List<Locale> deviceLocales) async {
    if (_store.hasStoredLocale) return;
    final locale = deviceLocales
        .map((item) => item.languageCode)
        .where(PreferencesStore.supportedLocales.contains)
        .firstOrNull;
    if (locale != null && locale != state.locale) await setLocale(locale);
  }

  /// Debug builds only: the next cold start opens the first-launch flow.
  Future<void> resetOnboarding() =>
      _set(state.copyWith(onboardingComplete: false));

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

  Future<void> setReaderHaptics(bool enabled) =>
      _set(state.copyWith(readerHaptics: enabled));

  Future<void> setHijriAdjustment(int days) =>
      _set(state.copyWith(hijriAdjustment: days.clamp(-2, 2)));

  Future<void> setMushafVariant(String variant) =>
      _set(state.copyWith(mushafVariant: variant));

  Future<void> setPreferredTranslationSource(int sourceId) =>
      _set(state.copyWith(preferredTranslationSourceId: sourceId));

  Future<void> setPreferredTafsirSource(int sourceId) =>
      _set(state.copyWith(preferredTafsirSourceId: sourceId));

  Future<void> setListeningRecitation(String recitationId) =>
      _setRecitation(RecitationPreferenceRole.listening, recitationId);

  Future<void> setMushafRecitation(String recitationId) =>
      _setRecitation(RecitationPreferenceRole.mushaf, recitationId);

  Future<void> setMemorizationDefaultRecitation(String recitationId) =>
      _setRecitation(RecitationPreferenceRole.memorization, recitationId);

  /// Compatibility entry point for code that still represents the old
  /// single-reciter preference. It now changes only the Listening role.
  Future<void> setPreferredRecitation(String recitationId) =>
      setListeningRecitation(recitationId);

  Future<void> setPreferredAudioQuality(String quality) => _set(
    state.copyWith(
      preferredAudioQuality: supportedAudioQualityPreferences.contains(quality)
          ? quality
          : defaultPreferredAudioQuality,
    ),
  );

  Future<void> setPlayerBackground(String id) =>
      _set(state.copyWith(playerBackgroundId: id));

  Future<void> setDailyReadingGoal({
    required DailyUnit unit,
    required int target,
  }) => _set(state.copyWith(dailyUnit: unit, dailyTarget: target));
}

final appPreferencesProvider =
    StateNotifierProvider<AppPreferencesController, AppPreferences>((ref) {
      ref.watch(_accountScopeEpochProvider);
      return AppPreferencesController(
        ref.watch(preferencesStoreProvider),
        ref.watch(planRepositoryProvider),
        accountScope: ref.watch(localDatabaseProvider).accountScope,
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

  /// Signs in with a Google ID token. Like [verify], the current account stays
  /// visible until the server answers.
  Future<void> signInWithGoogle(String idToken) async {
    try {
      final session = await _auth.signInWithGoogle(
        idToken: idToken,
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

  /// Signs out, then opens Google's account sheet for the next account.
  /// Closing the sheet leaves the app signed out; returns whether a Google
  /// account signed in.
  Future<bool> switchAccount(GoogleSignInGateway google) async {
    await google.signOut();
    await signOut();
    final idToken = await google.chooseAccount();
    if (idToken == null) return false;
    await signInWithGoogle(idToken);
    return true;
  }

  /// Confirms ownership of the current account's email before a lifecycle
  /// action. The account stays the same, so managed notifications are kept.
  Future<void> reauthenticate(EmailChallenge challenge, String code) async {
    await _auth.verifyEmail(
      challenge: challenge,
      code: code,
      locale: _locale(),
    );
  }

  Future<void> requestAccountDeletion(String challengeId) async {
    await _auth.requestAccountDeletion(challengeId, locale: _locale());
  }

  Future<void> cancelAccountDeletion(String challengeId) async {
    await _auth.cancelAccountDeletion(challengeId, locale: _locale());
  }

  /// Best-effort refresh of the account status, e.g. a deletion scheduled or
  /// cancelled on the website.
  Future<void> refreshAccountStatus() async {
    try {
      await _auth.refreshAccountSummary(locale: _locale());
    } on Object {
      // Offline or a changed account: the cached status stays authoritative.
    }
  }

  Future<void> signOut() => _signOutLocally(_auth.clearSession);

  /// Revokes all sessions on the server first; a failure leaves this device
  /// signed in. Only then the local logout runs, without a redundant remote
  /// logout of the already revoked session.
  Future<void> signOutEverywhere() async {
    await _auth.revokeAllSessions(locale: _locale());
    await _signOutLocally(() => _auth.clearSession(revokeRemote: false));
  }

  Future<void> _signOutLocally(Future<void> Function() clearSession) async {
    // Drop every account-owned provider before secure storage or network work
    // so account A cannot remain visible while logout is in progress.
    state = const AsyncValue.loading();
    await _cancelManagedBestEffort();
    try {
      await clearSession();
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

final googleSignInGatewayProvider = Provider<GoogleSignInGateway>(
  (ref) => PluginGoogleSignInGateway(
    ref.watch(authRepositoryProvider).googleServerClientId,
  ),
);

final googleSignInAvailableProvider = FutureProvider<bool>(
  (ref) => ref.watch(googleSignInGatewayProvider).isAvailable(),
);

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

final feedbackTicketsProvider =
    FutureProvider.autoDispose<List<FeedbackTicket>>((ref) async {
      ref.watch(activeAccountScopeKeyProvider);
      final session = ref.watch(sessionProvider).valueOrNull;
      final database = ref.watch(localDatabaseProvider);
      final scope = database.accountScope.current;
      if (session == null ||
          !session.isVerified ||
          scope == null ||
          scope.userId != session.userId) {
        return const <FeedbackTicket>[];
      }
      return ref.watch(feedbackRepositoryProvider).list(accountScope: scope);
    });

final feedbackTicketProvider = FutureProvider.autoDispose
    .family<FeedbackTicket, String>((ref, publicId) async {
      ref.watch(activeAccountScopeKeyProvider);
      final session = ref.watch(sessionProvider).valueOrNull;
      final database = ref.watch(localDatabaseProvider);
      final scope = database.accountScope.current;
      if (session == null ||
          !session.isVerified ||
          scope == null ||
          scope.userId != session.userId) {
        throw StateError('A verified account is required');
      }
      return ref
          .watch(feedbackRepositoryProvider)
          .get(publicId, accountScope: scope);
    });

final quranCatalogProvider = FutureProvider<QuranCatalog>((ref) {
  return ref.watch(quranRepositoryProvider).surahs();
});
typedef AyahBookmarkKey = ({AccountScopeKey account, int surah, int ayah});

final ayahBookmarkProvider = FutureProvider.autoDispose
    .family<bool, AyahBookmarkKey>((ref, key) async {
      final database = ref.watch(localDatabaseProvider);
      final scope = database.accountScope.current;
      if (scope == null || accountScopeKey(scope) != key.account) {
        throw const AccountScopeChanged();
      }
      final bookmarked = await ref
          .watch(quranRepositoryProvider)
          .isBookmarked(key.surah, key.ayah, accountScope: scope);
      if (!database.accountScope.isCurrent(scope)) {
        throw const AccountScopeChanged();
      }
      return bookmarked;
    });

final ayahAnnotationsProvider = FutureProvider.autoDispose
    .family<List<Map<String, Object?>>, AccountScopeKey>((ref, key) async {
      if (ref.watch(activeAccountScopeKeyProvider) != key) {
        throw const AccountScopeChanged();
      }
      final database = ref.watch(localDatabaseProvider);
      final scope = database.accountScope.current;
      if (scope == null || accountScopeKey(scope) != key) {
        throw const AccountScopeChanged();
      }
      final annotations = await ref
          .watch(quranRepositoryProvider)
          .ayahAnnotations(accountScope: scope);
      if (!database.accountScope.isCurrent(scope)) {
        throw const AccountScopeChanged();
      }
      return annotations;
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

/// Published catalog of Mushaf editions. A fresh local copy (under an hour
/// old) answers without the network; only a missing or expired copy triggers
/// a request, during which [cachedMushafRenditionsProvider] keeps the screen
/// drawn, so opening the Quran tab never shows the catalog loading.
final mushafRenditionsProvider = FutureProvider<List<NativeMushafEdition>>((
  ref,
) {
  return ref.watch(quranRepositoryProvider).mushafRenditions();
});

/// The app overrides this with the copy AppDependencies reads before the
/// first frame, so the Quran tab never waits on the database for it.
final cachedMushafRenditionsProvider =
    FutureProvider<List<NativeMushafEdition>>((ref) {
      return ref.watch(quranRepositoryProvider).cachedMushafRenditions();
    });
final availableMushafRenditionsProvider = Provider<List<NativeMushafEdition>>((
  ref,
) {
  final currentCatalog = ref.watch(mushafRenditionsProvider);
  final catalog = currentCatalog.hasValue
      ? currentCatalog.valueOrNull!
      : ref.watch(cachedMushafRenditionsProvider).valueOrNull ??
            const <NativeMushafEdition>[];
  final isProduction = ref.watch(appConfigProvider).isProduction;
  return catalog
      .where((edition) => edition.availableIn(isProduction: isProduction))
      .toList();
});
final selectedMushafIdentityProvider = Provider<MushafIdentity>((ref) {
  final preference = ref.watch(
    appPreferencesProvider.select((p) => p.mushafVariant),
  );
  // Readers who never chose an edition get the colour-coded Tajweed Mushaf.
  final identity = preference == defaultMushafVariant
      ? MushafIdentity.defaultEdition
      : MushafIdentity.fromPreference(preference);
  final catalog = ref.watch(availableMushafRenditionsProvider);
  return availableMushafIdentity(
    identity,
    catalog,
    isProduction: ref.watch(appConfigProvider).isProduction,
  );
});
final mushafRepositoryProvider =
    Provider.family<QuranRepository, MushafIdentity>((ref, identity) {
      final repository = ref.watch(quranRepositoryProvider);
      // Only a changed source version rebuilds the repository: a refreshed
      // catalog with the same checksum must not reload every open page.
      final version = ref.watch(
        availableMushafRenditionsProvider.select(
          (catalog) =>
              catalog
                  .where((edition) => edition.identity == identity)
                  .firstOrNull
                  ?.sourceChecksum ??
              '',
        ),
      );
      final selected = repository.forMushaf(identity);
      return identity.isFoundation
          ? selected.withFoundationVersion(version)
          : selected;
    });
final selectedMushafRepositoryProvider = Provider<QuranRepository>((ref) {
  return ref.watch(
    mushafRepositoryProvider(ref.watch(selectedMushafIdentityProvider)),
  );
});
final selectedMushafPageCountProvider = Provider<int>((ref) {
  final identity = ref.watch(selectedMushafIdentityProvider);
  return ref
          .watch(availableMushafRenditionsProvider)
          .where((edition) => edition.identity == identity)
          .firstOrNull
          ?.pagesCount ??
      604;
});
final selectedMushafOfflineRepositoryProvider =
    Provider<MushafOfflineRepository>((ref) {
      final identity = ref.watch(selectedMushafIdentityProvider);
      final repository = ref.watch(mushafOfflineRepositoryProvider);
      return repository.forMushaf(identity);
    });
final mushafPageProvider = FutureProvider.autoDispose
    .family<MushafPageData, int>((ref, page) {
      return ref.watch(selectedMushafRepositoryProvider).mushafPage(page);
    });
final tajweedRepositoryProvider = Provider<TajweedRepository>(
  (ref) => TajweedRepository(
    api: ref.watch(apiClientProvider),
    database: ref.watch(localDatabaseProvider),
  ),
);
final tajweedRulesProvider = FutureProvider.autoDispose<TajweedReference?>(
  (ref) => ref.watch(tajweedRepositoryProvider).rules(),
);

/// Tajweed of a QF Mushaf 19 page, whose numbering it shares.
final tajweedPageProvider = FutureProvider.autoDispose
    .family<TajweedPage?, int>(
      (ref, page) => ref.watch(tajweedRepositoryProvider).page(page),
    );

class MushafDownloadController extends StateNotifier<MushafDownloadSnapshot> {
  MushafDownloadController(this._repository)
    : super(const MushafDownloadSnapshot.empty()) {
    unawaited(initialize());
  }

  final MushafOfflineRepository _repository;

  Future<void> initialize() async {
    final snapshot = await _repository.snapshot();
    if (mounted && state.status != MushafDownloadStatus.downloading) {
      state = snapshot;
    }
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
      final installed = await _repository.install(
        width: width,
        onProgress: (progress) {
          if (mounted) state = progress;
        },
      );
      if (!mounted) return;
      state = installed;
      for (var page = 1; page <= state.totalPages; page += 1) {
        refInvalidateMushafPage?.call(page);
      }
    } on Object catch (error) {
      final persisted = await _repository.snapshot();
      if (!mounted) return;
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

// Keep one download controller per edition, even when the reader switches away.
// Otherwise returning to an edition can start two writers for the same package.
final mushafDownloadsByEditionProvider =
    StateNotifierProvider.family<
      MushafDownloadController,
      MushafDownloadSnapshot,
      MushafIdentity
    >((ref, identity) {
      final repository = ref.watch(mushafOfflineRepositoryProvider);
      final controller = MushafDownloadController(
        repository.forMushaf(identity),
      );
      controller.refInvalidateMushafPage = (page) {
        if (ref.read(selectedMushafIdentityProvider) == identity) {
          ref.invalidate(mushafPageProvider(page));
        }
      };
      return controller;
    });
final selectedMushafDownloadControllerProvider =
    Provider<MushafDownloadController>((ref) {
      final identity = ref.watch(selectedMushafIdentityProvider);
      final controller = ref.watch(
        mushafDownloadsByEditionProvider(identity).notifier,
      );
      unawaited(controller.initialize());
      return controller;
    });
final mushafDownloadProvider = Provider<MushafDownloadSnapshot>((ref) {
  ref.watch(selectedMushafDownloadControllerProvider);
  return ref.watch(
    mushafDownloadsByEditionProvider(ref.watch(selectedMushafIdentityProvider)),
  );
});
final recitersProvider = FutureProvider<List<Reciter>>((ref) {
  return ref.watch(audioRepositoryProvider).reciters();
});
final playerBackgroundRepositoryProvider = Provider<PlayerBackgroundRepository>(
  (ref) => PlayerBackgroundRepository(
    api: ref.watch(apiClientProvider),
    database: ref.watch(localDatabaseProvider),
    apiBaseUrl: ref.watch(appConfigProvider).apiBaseUrl,
  ),
);

/// Bundled backgrounds always come first, so the picker works offline and
/// before the admin has published anything.
final playerBackgroundsProvider = FutureProvider<List<PlayerBackground>>((
  ref,
) async {
  try {
    final remote = await ref.watch(playerBackgroundRepositoryProvider).remote();
    return <PlayerBackground>[...bundledPlayerBackgrounds, ...remote];
  } on Object {
    return bundledPlayerBackgrounds;
  }
});
final audioRecitationsProvider = FutureProvider<List<Recitation>>((ref) {
  return ref.watch(audioRepositoryProvider).recitations();
});
final memorizationRecitationsProvider = FutureProvider<List<Recitation>>(
  (ref) async => ref
      .watch(audioRepositoryProvider)
      .recitationsForRole(AudioRecitationRole.memorization),
);

class AudioDownloadController extends StateNotifier<AudioDownloadSnapshot> {
  AudioDownloadController(this._repository, this._recitationId)
    : super(AudioDownloadSnapshot.empty(_recitationId)) {
    unawaited(initialize());
  }

  final AudioOfflineRepository _repository;
  final String _recitationId;

  /// The stored state first, then whether the recitation gained surahs.
  Future<void> initialize() async {
    state = await _repository.snapshot(_recitationId);
    if (state.status != AudioDownloadStatus.ready) return;
    try {
      final latest = await _repository.check(_recitationId);
      if (mounted && state.status == AudioDownloadStatus.ready) state = latest;
    } on Object {
      // Offline the stored package stays as it is.
    }
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

final duaEntriesByTopicProvider = FutureProvider.family<List<DuaEntry>, String>(
  (ref, id) async {
    final topic = duaTopics.singleWhere((item) => item.id == id);
    final categories = await ref.watch(duaCategoriesProvider.future);
    final members =
        categories.where(topic.includesCategory).toList(growable: false)..sort(
          (left, right) => left.sourceNumber.compareTo(right.sourceNumber),
        );
    final pages = await Future.wait([
      for (final category in members)
        ref.watch(duaEntriesByCategoryProvider(category.identity).future),
    ]);
    return pages
        .expand((entries) => entries)
        .where(topic.includesEntry)
        .toList(growable: false);
  },
);

/// The account's favourite du'a, newest first. Pulls the server copy when
/// online and falls back to the local list offline.
final duaFavoritesProvider = FutureProvider.autoDispose
    .family<List<DuaEntry>, AccountScopeKey>((ref, key) async {
      if (ref.watch(activeAccountScopeKeyProvider) != key) {
        throw const AccountScopeChanged();
      }
      final database = ref.watch(localDatabaseProvider);
      final scope = database.accountScope.current;
      if (scope == null || accountScopeKey(scope) != key) {
        throw const AccountScopeChanged();
      }
      final locale = ref.watch(
        appPreferencesProvider.select((value) => value.locale),
      );
      final favorites = await ref
          .watch(duaRepositoryProvider)
          .favorites(locale: locale, accountScope: scope);
      if (!database.accountScope.isCurrent(scope)) {
        throw const AccountScopeChanged();
      }
      return favorites;
    });

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
final salahCourseProvider = FutureProvider.family<SalahCourseDocument, String>((
  ref,
  slug,
) {
  final locale = ref.watch(
    appPreferencesProvider.select((value) => value.locale),
  );
  return ref.watch(salahRepositoryProvider).course(slug, locale);
});
final salahProgressStoreProvider = Provider<SalahProgressStore>(
  (ref) => SalahProgressStore(ref.watch(localDatabaseProvider)),
);
final salahProgressProvider = FutureProvider.autoDispose
    .family<SalahCourseProgress, String>((ref, course) {
      // Progress belongs to the account; switching it reads the new owner's.
      ref.watch(activeAccountScopeKeyProvider);
      return ref.watch(salahProgressStoreProvider).read(course);
    });
final tajweedCourseGatewayProvider = Provider<TajweedCourseRemoteGateway>(
  (ref) => ApiTajweedCourseGateway(ref.watch(apiClientProvider)),
);
final tajweedCourseRepositoryProvider = Provider<TajweedCourseRepository>(
  (ref) => TajweedCourseRepository(
    remote: ref.watch(tajweedCourseGatewayProvider),
    database: ref.watch(localDatabaseProvider),
    keepMedia: LessonMediaPrefetcher(
      cache: ref.watch(lessonMediaCacheManagerProvider),
      apiBase: Uri.parse(ref.watch(appConfigProvider).apiBaseUrl),
    ).keep,
  ),
);
final tajweedCourseProvider =
    FutureProvider.family<TajweedCourseDocument, String>((ref, slug) {
      final locale = ref.watch(
        appPreferencesProvider.select((value) => value.locale),
      );
      return ref.watch(tajweedCourseRepositoryProvider).course(slug, locale);
    });
final tajweedCourseProgressStoreProvider = Provider<TajweedCourseProgressStore>(
  (ref) => TajweedCourseProgressStore(ref.watch(localDatabaseProvider)),
);
final tajweedCourseProgressProvider = FutureProvider.autoDispose
    .family<TajweedCourseProgress, String>((ref, course) {
      // Progress belongs to the account; switching it reads the new owner's.
      ref.watch(activeAccountScopeKeyProvider);
      return ref.watch(tajweedCourseProgressStoreProvider).read(course);
    });
final tajweedProgressSyncProvider = Provider<TajweedProgressSync>(
  (ref) => TajweedProgressSync(
    remote: ref.watch(tajweedCourseGatewayProvider),
    store: ref.watch(tajweedCourseProgressStoreProvider),
    database: ref.watch(localDatabaseProvider),
    session: () => ref.read(sessionProvider).valueOrNull,
    onMerged: (course) => ref.invalidate(tajweedCourseProgressProvider(course)),
  ),
);
final courseGatewayProvider = Provider<CourseRemoteGateway>(
  (ref) => ApiCourseGateway(ref.watch(apiClientProvider)),
);
final courseRepositoryProvider = Provider<CourseRepository>(
  (ref) => CourseRepository(
    remote: ref.watch(courseGatewayProvider),
    database: ref.watch(localDatabaseProvider),
    keepMedia: LessonMediaPrefetcher(
      cache: ref.watch(lessonMediaCacheManagerProvider),
      apiBase: Uri.parse(ref.watch(appConfigProvider).apiBaseUrl),
    ).keep,
  ),
);

/// The list is asked for each time the section is opened: a new version
/// means a new document, a course gone from it is hidden.
final courseCatalogProvider = FutureProvider.autoDispose<CourseCatalog>((ref) {
  final locale = ref.watch(
    appPreferencesProvider.select((value) => value.locale),
  );
  return ref.watch(courseRepositoryProvider).catalog(locale);
});
final courseDocumentProvider = FutureProvider.autoDispose
    .family<CourseDocument, String>((ref, slug) async {
      final locale = ref.watch(
        appPreferencesProvider.select((value) => value.locale),
      );
      final catalog = await ref.watch(courseCatalogProvider.future);
      final course = catalog.course(slug);
      if (course == null) throw CourseUnavailable(slug);
      return ref.watch(courseRepositoryProvider).document(course, locale);
    });
final courseProgressStoreProvider = Provider<CourseProgressStore>(
  (ref) => CourseProgressStore(ref.watch(localDatabaseProvider)),
);
final courseProgressProvider = FutureProvider.autoDispose
    .family<CourseProgress, String>((ref, course) {
      // Progress belongs to the account; switching it reads the new owner's.
      ref.watch(activeAccountScopeKeyProvider);
      return ref.watch(courseProgressStoreProvider).read(course);
    });
final coursePositionsProvider = FutureProvider.autoDispose
    .family<CourseVideoPositions, String>((ref, course) {
      ref.watch(activeAccountScopeKeyProvider);
      return ref.watch(courseProgressStoreProvider).readPositions(course);
    });

final courseFeedbackGatewayProvider = Provider<CourseFeedbackGateway>(
  (ref) => ApiCourseFeedbackGateway(ref.watch(apiClientProvider)),
);

/// One queue for the app: it sends lesson counters once a minute and when
/// the app goes to the background.
final courseEventQueueProvider = Provider<CourseEventQueue>((ref) {
  final queue = CourseEventQueue(
    send: (platform, events) =>
        ref.read(courseFeedbackGatewayProvider).sendEvents(platform, events),
  );
  WidgetsBinding.instance.addObserver(queue);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(queue));
  return queue;
});
final courseFeedbackStoreProvider = Provider<CourseFeedbackStore>(
  (ref) => CourseFeedbackStore(ref.watch(localDatabaseProvider)),
);
final courseVotesProvider = FutureProvider.autoDispose
    .family<Map<String, LessonVote>, String>((ref, course) {
      ref.watch(activeAccountScopeKeyProvider);
      return ref.watch(courseFeedbackStoreProvider).votes(course);
    });
final courseRatingProvider = FutureProvider.autoDispose
    .family<CourseRating?, String>((ref, course) {
      ref.watch(activeAccountScopeKeyProvider);
      return ref.watch(courseFeedbackStoreProvider).rating(course);
    });

/// Firebase for this platform when the build carries its IDs; tests put a
/// fake in.
final analyticsBackendProvider = Provider<AnalyticsBackend?>((ref) {
  final options = firebaseOptionsFor(defaultTargetPlatform);
  return options == null ? null : FirebaseAnalyticsBackend(options);
});
final analyticsProvider =
    StateNotifierProvider<AnalyticsController, AnalyticsConsent?>((ref) {
      final backend = ref.watch(analyticsBackendProvider);
      return backend == null
          ? AnalyticsController.disabled()
          : AnalyticsController(ref.watch(preferencesStoreProvider), backend);
    });

/// «audio_play» as the site sends it, the reciter named in the reader's
/// language.
Map<String, Object> audioPlayParameters(
  IqroAudioState state, {
  required String locale,
}) {
  final start = state.rangeStartAyah;
  final end = state.rangeEndAyah;
  return <String, Object>{
    'kind': start == null
        ? 'surah'
        : start == end
        ? 'ayah'
        : 'range',
    'surah': state.track?.surah ?? 0,
    'reciter': state.reciter?.nameFor(locale) ?? '',
  };
}

/// The system share sheet; tests put a fake in.
final courseShareProvider =
    Provider<Future<ShareResult> Function(ShareParams params)>(
      (ref) =>
          (params) => SharePlus.instance.share(params),
    );

/// Course covers, kept in the image disk cache after the first view.
final courseImageProvider = Provider<ImageProvider Function(String url)>(
  (ref) =>
      (url) => CachedNetworkImageProvider(url),
);
final tajweedPracticeStoreProvider = Provider<TajweedPracticeStore>(
  (ref) => TajweedPracticeStore(ref.watch(localDatabaseProvider)),
);
final tajweedPracticeProvider = FutureProvider.autoDispose
    .family<TajweedPracticeLocal, String>((ref, course) {
      // The practice belongs to the account; switching it reads the new
      // owner's.
      ref.watch(activeAccountScopeKeyProvider);
      return ref.watch(tajweedPracticeStoreProvider).read(course);
    });
final tajweedPracticeSyncProvider = Provider<TajweedPracticeSync>(
  (ref) => TajweedPracticeSync(
    remote: ref.watch(tajweedCourseGatewayProvider),
    store: ref.watch(tajweedPracticeStoreProvider),
    database: ref.watch(localDatabaseProvider),
    session: () => ref.read(sessionProvider).valueOrNull,
    onChanged: (course) => ref.invalidate(tajweedPracticeProvider(course)),
  ),
);

/// The time of practice answers and sessions; tests fix it.
final tajweedPracticeClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Resolves the reciter whose timings play the course examples: always
/// al-Husary's Muallim, see [tajweedCourseRecitation].
final tajweedCourseRecitationProvider = Provider<Future<String?> Function()>(
  (ref) => () async {
    final recitations = await ref
        .read(audioRepositoryProvider)
        .recitationsForRole(AudioRecitationRole.ayahPlayback);
    return tajweedCourseRecitation(recitations)?.id;
  },
);
final salahDisplayProvider = StateProvider<SalahDisplay>(
  (ref) => const SalahDisplay(),
);

/// Draws a step's schematic 3D scene; tests swap the WebView for a stand-in.
final salah3DViewBuilderProvider = Provider<Salah3DViewBuilder>(
  (ref) => buildSalah3DWebView,
);

/// Step illustrations, kept in the image disk cache after the first view.
final salahImageProvider = Provider<ImageProvider Function(String url)>(
  (ref) =>
      (url) => CachedNetworkImageProvider(url),
);
final salahOfflineRepositoryProvider = Provider<SalahOfflineRepository>(
  (ref) => SalahOfflineRepository(
    gateway: ApiSalahOfflineGateway(ref.watch(apiClientProvider)),
    database: ref.watch(localDatabaseProvider),
  ),
);

/// Downloaded course pictures by SHA-256, for the language being read.
final salahOfflineImagesProvider =
    FutureProvider.family<Map<String, String>, String>((ref, slug) {
      final locale = ref.watch(
        appPreferencesProvider.select((value) => value.locale),
      );
      return ref
          .watch(salahOfflineRepositoryProvider)
          .localImages(slug, locale);
    });

/// A step picture from the offline package when it is downloaded, otherwise
/// from the network as before.
final salahCourseImageProvider =
    Provider.family<ImageProvider Function(SalahMedia media), String>((
      ref,
      slug,
    ) {
      final local =
          ref.watch(salahOfflineImagesProvider(slug)).valueOrNull ??
          const <String, String>{};
      final network = ref.watch(salahImageProvider);
      return (media) {
        final path = media.sha256.isEmpty ? null : local[media.sha256];
        return path == null ? network(media.url) : FileImage(File(path));
      };
    });

class SalahOfflineController extends StateNotifier<SalahOfflineSnapshot> {
  SalahOfflineController(
    this._repository,
    this._slug,
    this._language, {
    this.onChanged,
  }) : super(const SalahOfflineSnapshot.empty()) {
    unawaited(initialize());
  }

  final SalahOfflineRepository _repository;
  final String _slug;
  final String _language;

  /// Called when the stored pictures changed.
  final void Function()? onChanged;

  /// The stored state first, then the published size and version.
  Future<void> initialize() async {
    try {
      final stored = await _repository.snapshot(_slug, _language);
      if (mounted && state.status != SalahOfflineStatus.downloading) {
        state = stored;
      }
      final latest = await _repository.check(_slug, _language);
      if (mounted && state.status != SalahOfflineStatus.downloading) {
        state = latest;
      }
    } on Object {
      // Offline the stored state stays; without a manifest there is nothing
      // to offer for download.
    }
  }

  Future<void> download() async {
    if (state.status == SalahOfflineStatus.downloading) return;
    final previous = state;
    state = SalahOfflineSnapshot(
      status: SalahOfflineStatus.downloading,
      packageId: previous.packageId,
      totalItems: previous.totalItems,
      totalBytes: previous.totalBytes,
    );
    try {
      final installed = await _repository.install(
        _slug,
        _language,
        onProgress: (progress) {
          if (mounted) state = progress;
        },
      );
      onChanged?.call();
      if (mounted) state = installed;
    } on Object catch (error) {
      onChanged?.call();
      if (!mounted) return;
      state = SalahOfflineSnapshot(
        status: SalahOfflineStatus.failed,
        packageId: previous.packageId,
        version: previous.version,
        checksum: previous.checksum,
        totalItems: previous.totalItems,
        totalBytes: previous.totalBytes,
        error: error.toString(),
      );
    }
  }

  Future<void> delete() async {
    await _repository.delete(_slug, _language);
    onChanged?.call();
    if (!mounted) return;
    state = SalahOfflineSnapshot(
      status: SalahOfflineStatus.notDownloaded,
      packageId: state.packageId,
      totalItems: state.totalItems,
      totalBytes: state.totalBytes,
    );
  }
}

// Not disposed with the course screen: a download keeps running and one
// controller per course avoids two writers for the same package.
final salahOfflineProvider =
    StateNotifierProvider.family<
      SalahOfflineController,
      SalahOfflineSnapshot,
      String
    >((ref, slug) {
      final locale = ref.watch(
        appPreferencesProvider.select((value) => value.locale),
      );
      return SalahOfflineController(
        ref.watch(salahOfflineRepositoryProvider),
        slug,
        locale,
        onChanged: () => ref.invalidate(salahOfflineImagesProvider(slug)),
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
    required ReadingGoalMetric? preferredMetric,
  }) : _database = database,
       _accountScope = accountScope,
       _preferredTarget = preferredTarget,
       _preferredMetric = preferredMetric,
       super(const AsyncValue.loading()) {
    unawaited(reload());
    unawaited(_showCached());
  }
  final PlanRepository _repository;
  final LocalDatabase _database;
  final AccountScopeSnapshot? _accountScope;
  final int? _preferredTarget;
  final ReadingGoalMetric? _preferredMetric;
  // Only the newest load may land, so a slow older one never undoes it.
  var _generation = 0;

  /// The saved plan shows while the first load waits for the server.
  Future<void> _showCached() async {
    final scope = _accountScope;
    if (scope == null) return;
    try {
      final cached = await _repository.cached(accountScope: scope);
      _database.ensureCurrent(scope);
      if (cached != null && mounted && !state.hasValue) {
        state = AsyncValue.data(cached);
      }
    } on Object {
      // The server load decides what the screen shows.
    }
  }

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
      preferredMetric: _preferredMetric,
      accountScope: scope,
    ),
  );

  Future<void> setGoal(ReadingGoalMetric metric, int target, int revision) =>
      _mutate(
        (scope) => _repository.setGoal(
          metric,
          target,
          baseRevision: revision,
          accountScope: scope,
        ),
      );

  Future<void> addReading(int amount, ReadingGoalMetric metric) => _mutate(
    (scope) =>
        _repository.addReading(amount, metric: metric, accountScope: scope),
  );

  Future<void> addPages(int pages) =>
      _mutate((scope) => _repository.addPages(pages, accountScope: scope));

  Future<void> updateManualReading(
    ReadingSession session, {
    required ReadingGoalMetric metric,
    required double amount,
    required String localDate,
  }) => _mutate(
    (scope) => _repository.updateManualReading(
      session,
      metric: metric,
      amount: amount,
      localDate: localDate,
      accountScope: scope,
    ),
  );

  Future<void> deleteManualReading(ReadingSession session) => _mutate(
    (scope) => _repository.deleteManualReading(session, accountScope: scope),
  );

  Future<void> setPrayerPages(String prayer, int pages) => _mutate(
    (scope) => _repository.setPrayerPages(prayer, pages, accountScope: scope),
  );

  Future<void> _mutate(
    Future<DailyPlan> Function(AccountScopeSnapshot scope) load,
  ) async {
    final scope = _accountScope;
    if (scope == null) return;
    final generation = ++_generation;
    try {
      final next = await load(scope);
      _database.ensureCurrent(scope);
      if (mounted && generation == _generation) state = AsyncValue.data(next);
    } on AccountScopeChanged {
      // A disposed controller must never retry an A action under account B.
    } on Object {
      rethrow;
    }
  }

  Future<void> _replace(
    Future<DailyPlan> Function(AccountScopeSnapshot scope) load,
  ) async {
    final scope = _accountScope;
    if (scope == null) return;
    final generation = ++_generation;
    try {
      final next = await load(scope);
      _database.ensureCurrent(scope);
      if (mounted && generation == _generation) state = AsyncValue.data(next);
    } on AccountScopeChanged {
      // A disposed controller must never retry an A action under account B.
    } on Object catch (error, stack) {
      if (mounted &&
          generation == _generation &&
          _database.accountScope.isCurrent(scope)) {
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
      // Only the daily goal matters here: a theme or reciter change must not
      // send the plan back to a spinner.
      final (preferredTarget, dailyUnit) = ref.watch(
        appPreferencesProvider.select(
          (value) => (value.dailyTarget, value.dailyUnit),
        ),
      );
      final controller = PlanController(
        ref.watch(planRepositoryProvider),
        database: database,
        accountScope: boundScope,
        preferredTarget: preferredTarget,
        preferredMetric: readingMetricForDailyUnit(dailyUnit),
      );
      // New reading refreshes the plan in place; the old numbers stay on
      // screen until the new ones arrive.
      ref.listen(planUpdatesProvider, (_, _) => unawaited(controller.reload()));
      return controller;
    });

ReadingGoalMetric readingMetricForDailyUnit(DailyUnit unit) => switch (unit) {
  DailyUnit.minutes => ReadingGoalMetric.minutes,
  DailyUnit.pages => ReadingGoalMetric.pages,
  DailyUnit.ayahs => ReadingGoalMetric.ayahs,
};

DailyUnit dailyUnitForReadingMetric(ReadingGoalMetric metric) =>
    switch (metric) {
      ReadingGoalMetric.minutes => DailyUnit.minutes,
      ReadingGoalMetric.pages => DailyUnit.pages,
      ReadingGoalMetric.ayahs => DailyUnit.ayahs,
    };

class MemorizationController
    extends StateNotifier<AsyncValue<MemorizationDashboard>> {
  MemorizationController(
    this._repository, {
    required LocalDatabase database,
    required AccountScopeSnapshot? accountScope,
  }) : _database = database,
       _accountScope = accountScope,
       super(const AsyncValue.loading()) {
    if (accountScope != null) unawaited(_start(accountScope));
  }
  final MemorizationRepository _repository;
  final LocalDatabase _database;
  final AccountScopeSnapshot? _accountScope;

  Future<void> reload() => _replace(
    (scope) => _repository.load(accountScope: scope),
    propagateError: false,
  );

  // Today's saved dashboard shows while the server is asked; on a phone the
  // Home card otherwise said "Loading" for a round trip on every start.
  Future<void> _start(AccountScopeSnapshot scope) async {
    final load = reload();
    try {
      final cached = await _repository.cachedToday(accountScope: scope);
      if (cached != null && mounted && !state.hasValue && !state.hasError) {
        state = AsyncValue.data(cached);
      }
    } on Object {
      // The server's answer, or its own cache fallback, decides.
    }
    await load;
  }

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

  /// Adds a Mushaf selection to the list and returns the server's result.
  Future<String> addSelection(
    MemorizationSelection selection, {
    required MemorizationAddMode mode,
    required int baseRevision,
    String? recitationId,
  }) async {
    var result = '';
    await _mutateList((scope) async {
      final added = await _repository.addSelection(
        selection,
        mode: mode,
        baseRevision: baseRevision,
        recitationId: recitationId,
        accountScope: scope,
      );
      result = added.result;
      return added.dashboard;
    });
    return result;
  }

  Future<void> updateItem(
    MemorizationItem item,
    MemorizationItemStatus status, {
    required int baseRevision,
  }) => _mutateList(
    (scope) => _repository.updateItem(
      item.id,
      status,
      baseRevision: baseRevision,
      accountScope: scope,
    ),
  );

  Future<void> removeItem(MemorizationItem item, {required int baseRevision}) =>
      _mutateList(
        (scope) => _repository.removeItem(
          item.id,
          baseRevision: baseRevision,
          accountScope: scope,
        ),
      );

  /// A failed list change keeps the dashboard on screen; the caller reports it.
  Future<void> _mutateList(
    Future<MemorizationDashboard> Function(AccountScopeSnapshot scope) change,
  ) async {
    final scope = _accountScope;
    if (scope == null) throw const AccountScopeChanged();
    final next = await change(scope);
    _database.ensureCurrent(scope);
    if (mounted) state = AsyncValue.data(next);
  }

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
        mediaLabels: () =>
            _listeningMediaLabels(ref.read(appPreferencesProvider).locale),
        playbackStore: boundScope == null
            ? null
            : AudioPlaybackStore(database, accountScope: boundScope),
        queueSource: ListeningQueueSource(
          heldSurahs: (recitationId) async {
            final recitations = await ref
                .read(audioRepositoryProvider)
                .recitations();
            return recitationHeldSurahs(
              recitations.where((item) => item.id == recitationId).firstOrNull,
            );
          },
          entry: (recitationId, surah) async {
            final playback = await ref
                .read(audioRepositoryProvider)
                .playback(recitationId: recitationId, surah: surah);
            return (
              playback: playback,
              surahName: await _listeningSurahName(ref, surah),
            );
          },
        ),
        onPlaybackStarted: (state) => ref
            .read(analyticsProvider.notifier)
            .track(
              AnalyticsEvent.audioPlay,
              audioPlayParameters(
                state,
                locale: ref.read(appPreferencesProvider).locale,
              ),
            ),
      );
      if (boundScope != null) unawaited(controller.restore());
      return controller;
    });

/// The media card's button labels, in the app's language.
ListeningMediaLabels _listeningMediaLabels(String locale) {
  final l10n = lookupAppLocalizations(Locale(locale));
  final speedFormat = NumberFormat('0.##', locale);
  return (
    previous: l10n.previousSurah,
    next: l10n.nextSurah,
    play: l10n.play,
    pause: l10n.pause,
    back10: l10n.mediaBack10,
    forward10: l10n.mediaForward10,
    speed: (speed) => l10n.mediaSpeed(speedFormat.format(speed)),
  );
}

/// The name the queue gives a surah it plays without a screen, in the app's
/// language, as the player screens name it.
Future<String> _listeningSurahName(Ref ref, int surah) async {
  final locale = ref.read(appPreferencesProvider).locale;
  try {
    final catalog = await ref.read(quranCatalogProvider.future);
    for (final item in catalog.surahs) {
      if (item.number == surah) return item.nameFor(locale);
    }
  } on Object {
    // The number alone still names it.
  }
  return '${lookupAppLocalizations(Locale(locale)).surah} $surah';
}

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
