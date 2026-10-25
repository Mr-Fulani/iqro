import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/preferences_store.dart';

// Usage statistics: Google Analytics 4 through Firebase, the same «IQRO»
// property the site reports to (docs/analytics.md). Nothing starts until the
// user presses «Принять» on the statistics card. The Firebase IDs come from
// config/firebase.json at build time; without them the card is not shown and
// Firebase is never initialized.

enum AnalyticsConsent { granted, denied }

AnalyticsConsent? parseAnalyticsConsent(String? value) => switch (value) {
  'granted' => AnalyticsConsent.granted,
  'denied' => AnalyticsConsent.denied,
  _ => null,
};

/// The events the site sends too; names and parameters stay the same.
enum AnalyticsEvent {
  surahOpen('surah_open'),
  audioPlay('audio_play'),
  lessonComplete('lesson_complete'),
  share('share'),
  login('login');

  const AnalyticsEvent(this.id);
  final String id;
}

/// The Firebase app for this platform, or null when the build has no IDs.
FirebaseOptions? firebaseOptionsFor(
  TargetPlatform platform, {
  String projectId = const String.fromEnvironment('FIREBASE_PROJECT_ID'),
  String senderId = const String.fromEnvironment('FIREBASE_SENDER_ID'),
  String androidAppId = const String.fromEnvironment('FIREBASE_ANDROID_APP_ID'),
  String androidApiKey = const String.fromEnvironment(
    'FIREBASE_ANDROID_API_KEY',
  ),
  String iosAppId = const String.fromEnvironment('FIREBASE_IOS_APP_ID'),
  String iosApiKey = const String.fromEnvironment('FIREBASE_IOS_API_KEY'),
}) {
  final (appId, apiKey) = switch (platform) {
    TargetPlatform.android => (androidAppId, androidApiKey),
    TargetPlatform.iOS => (iosAppId, iosApiKey),
    _ => ('', ''),
  };
  if ([projectId, senderId, appId, apiKey].any((value) => value.isEmpty)) {
    return null;
  }
  return FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: senderId,
    projectId: projectId,
    iosBundleId: platform == TargetPlatform.iOS ? 'forum.iqro.app' : null,
  );
}

abstract interface class AnalyticsBackend {
  Future<void> enable();
  Future<void> disable();
  Future<void> logEvent(String name, Map<String, Object> parameters);
}

class FirebaseAnalyticsBackend implements AnalyticsBackend {
  FirebaseAnalyticsBackend(this._options);

  final FirebaseOptions _options;
  Future<FirebaseAnalytics>? _analytics;

  Future<FirebaseAnalytics> _start() => _analytics ??= Firebase.initializeApp(
    options: _options,
  ).then((_) => FirebaseAnalytics.instance);

  @override
  Future<void> enable() async {
    final analytics = await _start();
    // Religion is a sensitive category: statistics only, nothing for ads.
    await analytics.setConsent(
      analyticsStorageConsentGranted: true,
      adStorageConsentGranted: false,
      adUserDataConsentGranted: false,
      adPersonalizationSignalsConsentGranted: false,
    );
    await analytics.setAnalyticsCollectionEnabled(true);
  }

  @override
  Future<void> disable() async {
    // Never started in this run: the manifest and Info.plist keep collection
    // off, and nothing was initialized.
    final analytics = await _analytics;
    if (analytics == null) return;
    await analytics.setAnalyticsCollectionEnabled(false);
    await analytics.resetAnalyticsData();
  }

  @override
  Future<void> logEvent(String name, Map<String, Object> parameters) async {
    final analytics = await _start();
    await analytics.logEvent(name: name, parameters: parameters);
  }
}

/// The user's choice and the events. Before consent, and in builds without
/// Firebase IDs, events are dropped.
class AnalyticsController extends StateNotifier<AnalyticsConsent?> {
  AnalyticsController(PreferencesStore store, AnalyticsBackend backend)
    : _store = store,
      _backend = backend,
      super(parseAnalyticsConsent(store.analyticsConsent)) {
    if (state == AnalyticsConsent.granted) _run(backend.enable);
  }

  /// A build without Firebase IDs: no question, no events.
  AnalyticsController.disabled() : _store = null, _backend = null, super(null);

  final PreferencesStore? _store;
  final AnalyticsBackend? _backend;

  /// Whether this build reports anywhere; otherwise no card and no setting.
  bool get available => _backend != null;

  Future<void> setConsent(AnalyticsConsent consent) async {
    final backend = _backend;
    if (backend == null || consent == state) return;
    state = consent;
    await _store!.writeAnalyticsConsent(consent.name);
    _run(
      consent == AnalyticsConsent.granted ? backend.enable : backend.disable,
    );
  }

  void track(AnalyticsEvent event, Map<String, Object> parameters) {
    final backend = _backend;
    if (backend == null || state != AnalyticsConsent.granted) return;
    _run(() => backend.logEvent(event.id, parameters));
  }

  // Statistics never get in the way: a failure loses one hit, nothing else.
  void _run(Future<void> Function() action) {
    unawaited(action().catchError((Object _) {}));
  }
}
