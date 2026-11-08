import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/platform/play_app_update.dart';
import '../../core/storage/preferences_store.dart';
import 'app_release_source.dart';

// Google Play in-app updates (docs/release/google-play.md): the card above the
// tab bar offers a new version, Play downloads it in the background (FLEXIBLE
// only, never IMMEDIATE), and «Перезапустить» installs it. When Play has not
// noticed the update yet, the build named in the admin is offered instead, and
// «Обновить» opens the app's page in Google Play.

/// Updates whose Play priority reaches this value hide «Позже». 0 keeps it off;
/// a build turns it on with --dart-define=APP_UPDATE_MANDATORY_PRIORITY=4.
const appUpdateMandatoryPriority = int.fromEnvironment(
  'APP_UPDATE_MANDATORY_PRIORITY',
);

enum AppUpdateStage { none, offer, downloading, readyToInstall }

class AppUpdateState {
  const AppUpdateState(
    this.stage, {
    this.versionCode = 0,
    this.mandatory = false,
    this.viaStore = false,
    this.hidden = false,
  });

  const AppUpdateState.none() : this(AppUpdateStage.none);

  final AppUpdateStage stage;
  final int versionCode;
  final bool mandatory;

  /// Known from the server, not from Play: «Обновить» opens Google Play.
  final bool viaStore;

  /// «Позже» hid the card above the tab bar; the update is still there, and
  /// More's account list keeps offering it.
  final bool hidden;

  AppUpdateState hide() => AppUpdateState(
    stage,
    versionCode: versionCode,
    mandatory: mandatory,
    viaStore: viaStore,
    hidden: true,
  );
}

/// What this device remembers between launches.
class AppUpdateRecord {
  const AppUpdateRecord({
    this.lastCheck,
    this.snoozedVersion,
    this.snoozedUntil,
    this.acceptedVersion,
    this.offerVersion,
    this.offerViaStore = false,
    this.offerMandatory = false,
  });

  factory AppUpdateRecord.parse(String? raw) {
    if (raw == null) return const AppUpdateRecord();
    try {
      final map = jsonDecode(raw) as Map<String, Object?>;
      DateTime? time(String key) => switch (map[key]) {
        final int ms => DateTime.fromMillisecondsSinceEpoch(ms),
        _ => null,
      };
      return AppUpdateRecord(
        lastCheck: time('lastCheck'),
        snoozedVersion: map['snoozedVersion'] as int?,
        snoozedUntil: time('snoozedUntil'),
        acceptedVersion: map['acceptedVersion'] as int?,
        offerVersion: map['offerVersion'] as int?,
        offerViaStore: map['offerViaStore'] == true,
        offerMandatory: map['offerMandatory'] == true,
      );
    } on Object {
      return const AppUpdateRecord();
    }
  }

  final DateTime? lastCheck;

  /// «Позже» hides this version, and only this one, until [snoozedUntil].
  final int? snoozedVersion;
  final DateTime? snoozedUntil;

  /// Set while an update the user accepted downloads or waits for a restart.
  final int? acceptedVersion;

  /// The update the last check found. The app is often started anew within
  /// [AppUpdateController.checkInterval] (MIUI drops it from memory); Play is
  /// not asked again then, so the offer is restored from here.
  final int? offerVersion;
  final bool offerViaStore;
  final bool offerMandatory;

  bool snoozes(int versionCode, DateTime now) {
    final version = snoozedVersion;
    final until = snoozedUntil;
    return version != null &&
        until != null &&
        versionCode <= version &&
        now.isBefore(until);
  }

  AppUpdateRecord copyWith({
    DateTime? lastCheck,
    int? snoozedVersion,
    DateTime? snoozedUntil,
    int? acceptedVersion,
    bool clearAccepted = false,
    int? offerVersion,
    bool? offerViaStore,
    bool? offerMandatory,
    bool clearOffer = false,
  }) => AppUpdateRecord(
    lastCheck: lastCheck ?? this.lastCheck,
    snoozedVersion: snoozedVersion ?? this.snoozedVersion,
    snoozedUntil: snoozedUntil ?? this.snoozedUntil,
    acceptedVersion: clearAccepted
        ? null
        : acceptedVersion ?? this.acceptedVersion,
    offerVersion: clearOffer ? null : offerVersion ?? this.offerVersion,
    offerViaStore: clearOffer ? false : offerViaStore ?? this.offerViaStore,
    offerMandatory: clearOffer ? false : offerMandatory ?? this.offerMandatory,
  );

  String encode() => jsonEncode(<String, Object?>{
    'lastCheck': lastCheck?.millisecondsSinceEpoch,
    'snoozedVersion': snoozedVersion,
    'snoozedUntil': snoozedUntil?.millisecondsSinceEpoch,
    'acceptedVersion': acceptedVersion,
    'offerVersion': offerVersion,
    'offerViaStore': offerViaStore,
    'offerMandatory': offerMandatory,
  });
}

class AppUpdateController extends StateNotifier<AppUpdateState> {
  AppUpdateController(
    AppUpdateGateway this._gateway,
    PreferencesStore this._store, {
    AppReleaseSource? release,
    DateTime Function()? now,
    this.mandatoryPriority = appUpdateMandatoryPriority,
  }) : _release = release,
       _now = now ?? DateTime.now,
       super(const AppUpdateState.none());

  /// iOS and other platforms: nothing is checked or shown.
  AppUpdateController.disabled()
    : _gateway = null,
      _store = null,
      _release = null,
      _now = DateTime.now,
      mandatoryPriority = 0,
      super(const AppUpdateState.none());

  static const checkInterval = Duration(minutes: 30);
  static const snoozeDuration = Duration(days: 3);

  final AppUpdateGateway? _gateway;
  final PreferencesStore? _store;
  final AppReleaseSource? _release;
  final DateTime Function() _now;
  final int mandatoryPriority;
  StreamSubscription<PlayInstallStatus>? _progress;
  // Busy with Play: a check, or its update dialog (closing it resumes the app).
  var _checking = false;
  var _restartPostponed = false;

  AppUpdateRecord get _record => AppUpdateRecord.parse(_store?.appUpdateRecord);

  Future<void> _save(AppUpdateRecord record) =>
      _store?.writeAppUpdateRecord(record.encode()) ?? Future<void>.value();

  /// On launch and on every return to the app. Play is asked at most once
  /// every [checkInterval], except while an accepted update downloads, so «Перезапустить»
  /// appears as soon as it is ready.
  Future<void> checkIfDue() async {
    final gateway = _gateway;
    if (gateway == null || _checking) return;
    final record = _record;
    final now = _now();
    final last = record.lastCheck;
    final recent =
        last != null &&
        !now.isBefore(last) &&
        now.difference(last) < checkInterval;
    if (recent && record.acceptedVersion == null) {
      final remembered = await _rememberedOffer(record, now);
      if (remembered != null && mounted) state = remembered;
      return;
    }
    _checking = true;
    final PlayUpdateInfo? info;
    // Asked only when Play itself has nothing to offer.
    int? storeVersion;
    try {
      info = await gateway.check();
      if (info != null &&
          !(info.available && info.flexibleAllowed) &&
          !_busy(info.installStatus)) {
        storeVersion = await _newerInStore();
      }
    } finally {
      _checking = false;
    }
    // Re-read: «Позже» may have been saved while Play answered.
    var saved = _record.copyWith(lastCheck: now);
    final AppUpdateState next;
    if (info == null) {
      // Not installed from Play: debug and adb builds stay silent.
      next = const AppUpdateState.none();
    } else {
      switch (info.installStatus) {
        case PlayInstallStatus.downloaded:
          next = AppUpdateState(
            AppUpdateStage.readyToInstall,
            versionCode: info.versionCode,
            hidden: _restartPostponed,
          );
        case PlayInstallStatus.pending ||
            PlayInstallStatus.downloading ||
            PlayInstallStatus.installing:
          next = AppUpdateState(
            AppUpdateStage.downloading,
            versionCode: info.versionCode,
          );
          _follow();
        case _ when state.stage == AppUpdateStage.downloading:
          // Accepted moments ago; Play has not reported the download yet.
          next = state;
        case _:
          saved = saved.copyWith(clearAccepted: true);
          final mandatory =
              mandatoryPriority > 0 && info.priority >= mandatoryPriority;
          if (info.available && info.flexibleAllowed) {
            next = AppUpdateState(
              AppUpdateStage.offer,
              versionCode: info.versionCode,
              mandatory: mandatory,
              hidden: !mandatory && saved.snoozes(info.versionCode, now),
            );
          } else if (storeVersion != null) {
            next = AppUpdateState(
              AppUpdateStage.offer,
              versionCode: storeVersion,
              viaStore: true,
              hidden: saved.snoozes(storeVersion, now),
            );
          } else {
            next = const AppUpdateState.none();
          }
      }
    }
    saved = next.stage == AppUpdateStage.offer
        ? saved.copyWith(
            offerVersion: next.versionCode,
            offerViaStore: next.viaStore,
            offerMandatory: next.mandatory,
          )
        : saved.copyWith(clearOffer: true);
    await _save(saved);
    if (mounted) state = next;
  }

  /// The last check's offer, while this build is still older than it.
  Future<AppUpdateState?> _rememberedOffer(
    AppUpdateRecord record,
    DateTime now,
  ) async {
    final version = record.offerVersion;
    if (version == null || state.stage != AppUpdateStage.none) return null;
    final installed = await _release?.installedVersionCode();
    if (installed != null && installed >= version) return null;
    final mandatory = record.offerMandatory;
    return AppUpdateState(
      AppUpdateStage.offer,
      versionCode: version,
      viaStore: record.offerViaStore,
      mandatory: mandatory,
      hidden: !mandatory && record.snoozes(version, now),
    );
  }

  static bool _busy(PlayInstallStatus status) => switch (status) {
    PlayInstallStatus.pending ||
    PlayInstallStatus.downloading ||
    PlayInstallStatus.downloaded ||
    PlayInstallStatus.installing => true,
    _ => false,
  };

  /// The admin's build when it is newer than this one, else null.
  Future<int?> _newerInStore() async {
    final release = _release;
    if (release == null) return null;
    final latest = await release.latestAndroidVersionCode();
    if (latest == null) return null;
    final installed = await release.installedVersionCode();
    return installed != null && latest > installed ? latest : null;
  }

  /// «Позже»: the card does not offer this version again for three days;
  /// More keeps it.
  Future<void> later() async {
    final offer = state;
    if (offer.stage != AppUpdateStage.offer || offer.mandatory) return;
    state = offer.hide();
    await _snooze(offer.versionCode);
  }

  Future<void> _snooze(int versionCode) => _save(
    _record.copyWith(
      snoozedVersion: versionCode,
      snoozedUntil: _now().add(snoozeDuration),
      clearAccepted: true,
    ),
  );

  /// «Обновить»: Play asks once more, then downloads in the background.
  Future<void> update() async {
    final gateway = _gateway;
    final offer = state;
    if (gateway == null || _checking || offer.stage != AppUpdateStage.offer) {
      return;
    }
    if (offer.viaStore) {
      // Play installs it from its own page; the next check finds the new build.
      state = offer.hide();
      await gateway.openStorePage();
      return;
    }
    _checking = true;
    state = AppUpdateState(
      AppUpdateStage.downloading,
      versionCode: offer.versionCode,
    );
    _follow();
    await _save(_record.copyWith(acceptedVersion: offer.versionCode));
    final bool accepted;
    try {
      accepted = await gateway.startFlexibleUpdate();
    } finally {
      _checking = false;
    }
    if (accepted || !mounted) return;
    // Declined in Play's dialog: the same as «Позже», unless it is required.
    if (offer.mandatory) {
      state = offer;
      await _save(_record.copyWith(clearAccepted: true));
    } else {
      state = offer.hide();
      await _snooze(offer.versionCode);
    }
  }

  /// «Перезапустить»: Play installs the update and opens the app again.
  Future<void> restart() async {
    final gateway = _gateway;
    if (gateway == null || state.stage != AppUpdateStage.readyToInstall) {
      return;
    }
    await gateway.completeUpdate();
  }

  /// «Позже» on a downloaded update: the card asks again on the next launch;
  /// More keeps «Перезапустить».
  void postponeRestart() {
    if (state.stage != AppUpdateStage.readyToInstall) return;
    _restartPostponed = true;
    state = state.hide();
  }

  void _follow() {
    _progress ??= _gateway?.installStatus.listen(
      _onStatus,
      onError: (Object _) {},
    );
  }

  void _onStatus(PlayInstallStatus status) {
    if (!mounted) return;
    final versionCode = state.versionCode;
    switch (status) {
      case PlayInstallStatus.downloaded:
        if (!_restartPostponed) {
          state = AppUpdateState(
            AppUpdateStage.readyToInstall,
            versionCode: versionCode,
          );
        }
      case PlayInstallStatus.pending ||
          PlayInstallStatus.downloading ||
          PlayInstallStatus.installing:
        if (state.stage != AppUpdateStage.readyToInstall) {
          state = AppUpdateState(
            AppUpdateStage.downloading,
            versionCode: versionCode,
          );
        }
      case PlayInstallStatus.failed ||
          PlayInstallStatus.canceled ||
          PlayInstallStatus.installed:
        state = const AppUpdateState.none();
        unawaited(_save(_record.copyWith(clearAccepted: true)));
      case PlayInstallStatus.unknown:
        break;
    }
  }

  @override
  void dispose() {
    _progress?.cancel();
    super.dispose();
  }
}

final appUpdateProvider =
    StateNotifierProvider<AppUpdateController, AppUpdateState>((ref) {
      // In-app updates are a Google Play feature; iOS has nothing yet.
      if (!Platform.isAndroid) return AppUpdateController.disabled();
      return AppUpdateController(
        PlayAppUpdateGateway(),
        ref.watch(preferencesStoreProvider),
        release: ApiAppReleaseSource(ref.watch(apiClientProvider)),
      );
    });
