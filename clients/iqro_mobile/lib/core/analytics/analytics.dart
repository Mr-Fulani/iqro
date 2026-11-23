import 'dart:async';
import 'dart:convert';

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

/// One gentle reminder for people who declined statistics: not sooner than
/// [analyticsReminderAfterDays] days after the refusal, and only after the app
/// was opened on [analyticsReminderActiveDays] different days since then. The
/// site keeps the same pair in services/web/lib/analytics.ts.
const analyticsReminderAfterDays = 30;
const analyticsReminderActiveDays = 5;

/// What the reminder needs to know, kept on the device as JSON (the site keeps
/// the same record in localStorage). Days are local calendar days.
class AnalyticsReminder {
  const AnalyticsReminder({
    this.declinedOn,
    this.lastDay,
    this.days = 0,
    this.done = false,
  });

  /// The day of the refusal, «2026-11-21»; for a refusal made before the
  /// reminder existed, the first day the app ran with it.
  final String? declinedOn;

  /// The last day the app was opened, and how many different days so far.
  final String? lastDay;
  final int days;

  /// The reminder was answered: nothing asks again.
  final bool done;

  static AnalyticsReminder parse(String? value) {
    try {
      final json = jsonDecode(value ?? '') as Map<String, Object?>;
      return AnalyticsReminder(
        declinedOn: json['declinedOn'] as String?,
        lastDay: json['lastDay'] as String?,
        days: json['days'] as int? ?? 0,
        done: json['done'] as bool? ?? false,
      );
    } on Object {
      return const AnalyticsReminder();
    }
  }

  String encode() => jsonEncode(<String, Object?>{
    'declinedOn': declinedOn,
    'lastDay': lastDay,
    'days': days,
    'done': done,
  });

  static String _day(DateTime now) =>
      '${now.year.toString().padLeft(4, '0')}-'
      '${now.month.toString().padLeft(2, '0')}-'
      '${now.day.toString().padLeft(2, '0')}';

  /// The app was opened on [now] while statistics are declined.
  AnalyticsReminder noteDay(DateTime now) {
    final today = _day(now);
    if (done || lastDay == today) return this;
    return declinedOn == null
        ? AnalyticsReminder(declinedOn: today, lastDay: today, days: 1)
        : AnalyticsReminder(
            declinedOn: declinedOn,
            lastDay: today,
            days: days + 1,
          );
  }

  bool due(DateTime now) {
    final declined = DateTime.tryParse('${declinedOn}T00:00:00Z');
    if (done || declined == null) return false;
    final today = DateTime.utc(now.year, now.month, now.day);
    return days >= analyticsReminderActiveDays &&
        today.difference(declined).inDays >= analyticsReminderAfterDays;
  }

  /// The record after an answer given on [now]. Any answer to the reminder
  /// is final; a refusal before it starts the count from that day.
  AnalyticsReminder afterAnswer(AnalyticsConsent consent, DateTime now) {
    if (done) return this;
    if (due(now)) {
      return AnalyticsReminder(
        declinedOn: declinedOn,
        lastDay: lastDay,
        days: days,
        done: true,
      );
    }
    return consent == AnalyticsConsent.denied
        ? const AnalyticsReminder().noteDay(now)
        : this;
  }
}

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
  AnalyticsController(
    PreferencesStore store,
    AnalyticsBackend backend, {
    DateTime Function() clock = DateTime.now,
  }) : _store = store,
       _backend = backend,
       _clock = clock,
       _reminder = AnalyticsReminder.parse(store.analyticsReminder),
       super(parseAnalyticsConsent(store.analyticsConsent)) {
    if (state == AnalyticsConsent.granted) _run(backend.enable);
    noteVisit();
  }

  /// A build without Firebase IDs: no question, no events.
  AnalyticsController.disabled()
    : _store = null,
      _backend = null,
      _clock = DateTime.now,
      _reminder = const AnalyticsReminder(),
      super(null);

  final PreferencesStore? _store;
  final AnalyticsBackend? _backend;
  final DateTime Function() _clock;
  AnalyticsReminder _reminder;

  /// Whether the card should ask once more ([AnalyticsReminder]).
  final reminderDue = ValueNotifier<bool>(false);

  /// The app was opened or came back to the screen: counts the day for
  /// someone who declined.
  void noteVisit() {
    if (_backend == null || state != AnalyticsConsent.denied) return;
    _setReminder(_reminder.noteDay(_clock()));
  }

  void _setReminder(AnalyticsReminder next) {
    if (!identical(next, _reminder)) {
      _reminder = next;
      _run(() => _store!.writeAnalyticsReminder(next.encode()));
    }
    reminderDue.value = state == AnalyticsConsent.denied && next.due(_clock());
  }

  @override
  void dispose() {
    reminderDue.dispose();
    super.dispose();
  }

  /// Whether this build reports anywhere; otherwise no card and no setting.
  bool get available => _backend != null;

  Future<void> setConsent(AnalyticsConsent consent) async {
    final backend = _backend;
    if (backend == null) return;
    // «Нет, спасибо» on the reminder repeats the stored answer and still
    // closes it for good.
    final next = _reminder.afterAnswer(consent, _clock());
    if (consent == state) return _setReminder(next);
    state = consent;
    _setReminder(next);
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
