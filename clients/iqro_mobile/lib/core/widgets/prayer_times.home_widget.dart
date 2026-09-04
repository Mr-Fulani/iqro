// dart format off
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

class PrayerTimesHomeWidget {
  const PrayerTimesHomeWidget._();

  static const String _$appGroupId = 'group.forum.iqro.app';

  static const String _$paramPrefix = 'home_widget.PrayerTimes';

  static Future<void> saveData({
    String? title,
    String? fajrLabel,
    String? dhuhrLabel,
    String? asrLabel,
    String? maghribLabel,
    String? ishaLabel,
    Map<DateTime, PrayerTimesTimedData>? timedData,
  }) {
    return Future.wait([
      if (title != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.title', title, appGroupId: _$appGroupId),
      if (fajrLabel != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.fajrLabel', fajrLabel, appGroupId: _$appGroupId),
      if (dhuhrLabel != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.dhuhrLabel', dhuhrLabel, appGroupId: _$appGroupId),
      if (asrLabel != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.asrLabel', asrLabel, appGroupId: _$appGroupId),
      if (maghribLabel != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.maghribLabel', maghribLabel, appGroupId: _$appGroupId),
      if (ishaLabel != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.ishaLabel', ishaLabel, appGroupId: _$appGroupId),
      if (timedData != null) () async {
        final _timedTimes = timedData.keys.toList()..sort();
        if (_timedTimes.isEmpty) {
          await HomeWidget.saveWidgetData('${_$paramPrefix}.timedData', null, appGroupId: _$appGroupId);
          try {
            await HomeWidget.cancelScheduledWidgetUpdates(androidName: 'PrayerTimesHomeWidgetReceiver');
          } catch (error, stackTrace) {
            // Cancelling is best effort; the data was deleted.
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stackTrace,
                library: 'home_widget',
                context: ErrorDescription('cancelling scheduled updates for the PrayerTimes widget'),
              ),
            );
          }
          return;
        }
        final _timedJson = <String, dynamic>{
          for (final _time in _timedTimes)
            _time.toUtc().millisecondsSinceEpoch.toString(): timedData[_time]!.toJson(),
        };
        await HomeWidget.saveFile('${_$paramPrefix}.timedData', Uint8List.fromList(utf8.encode(jsonEncode(_timedJson))), extension: 'json', appGroupId: _$appGroupId);
        try {
          await HomeWidget.scheduleWidgetUpdates(_timedTimes, androidName: 'PrayerTimesHomeWidgetReceiver');
        } catch (error, stackTrace) {
          // Scheduling is best effort; the data was saved.
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'home_widget',
              context: ErrorDescription('scheduling updates for the PrayerTimes widget'),
            ),
          );
        }
      }(),
    ]);
  }

  static Future<void> deleteData({
    bool title = false,
    bool fajrLabel = false,
    bool dhuhrLabel = false,
    bool asrLabel = false,
    bool maghribLabel = false,
    bool ishaLabel = false,
    bool timedData = false,
  }) {
    return Future.wait([
      if (title) HomeWidget.saveWidgetData('${_$paramPrefix}.title', null, appGroupId: _$appGroupId),
      if (fajrLabel) HomeWidget.saveWidgetData('${_$paramPrefix}.fajrLabel', null, appGroupId: _$appGroupId),
      if (dhuhrLabel) HomeWidget.saveWidgetData('${_$paramPrefix}.dhuhrLabel', null, appGroupId: _$appGroupId),
      if (asrLabel) HomeWidget.saveWidgetData('${_$paramPrefix}.asrLabel', null, appGroupId: _$appGroupId),
      if (maghribLabel) HomeWidget.saveWidgetData('${_$paramPrefix}.maghribLabel', null, appGroupId: _$appGroupId),
      if (ishaLabel) HomeWidget.saveWidgetData('${_$paramPrefix}.ishaLabel', null, appGroupId: _$appGroupId),
      if (timedData) () async {
        await HomeWidget.saveWidgetData('${_$paramPrefix}.timedData', null, appGroupId: _$appGroupId);
        try {
          await HomeWidget.cancelScheduledWidgetUpdates(androidName: 'PrayerTimesHomeWidgetReceiver');
        } catch (error, stackTrace) {
          // Cancelling is best effort; the data was deleted.
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stackTrace,
              library: 'home_widget',
              context: ErrorDescription('cancelling scheduled updates for the PrayerTimes widget'),
            ),
          );
        }
      }(),
    ]);
  }

  /// Reads every stored value back.
  ///
  /// The keys of [timedData] are local-time [DateTime]s, so they compare equal to a
  /// local [DateTime] for the same instant. Timestamps are stored as epoch
  /// milliseconds: sub-millisecond precision of the saved keys is not preserved.
  /// Keys are compared by instant, so a local [DateTime] and its `toUtc()` twin
  /// denote the same entry and only one of them survives a save.
  static Future<({String? title, String? fajrLabel, String? dhuhrLabel, String? asrLabel, String? maghribLabel, String? ishaLabel, Map<DateTime, PrayerTimesTimedData>? timedData})> getData() async {
    final _timedDataPath = await HomeWidget.getWidgetData<String>('${_$paramPrefix}.timedData', appGroupId: _$appGroupId);
    Map<DateTime, PrayerTimesTimedData>? timedData;
    if (_timedDataPath != null) {
      try {
        final raw = await File(_timedDataPath).readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final entries = <DateTime, PrayerTimesTimedData>{};
          for (final entry in decoded.entries) {
            final millis = int.tryParse(entry.key);
            if (millis == null) continue;
            final value = entry.value;
            entries[DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal()] = PrayerTimesTimedData.fromJson(value is Map<String, dynamic> ? value : null);
          }
          timedData = entries;
        }
      } on Exception {
        timedData = null;
      }
    }
    return (
      title: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.title', defaultValue: 'IQRO', appGroupId: _$appGroupId),
      fajrLabel: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.fajrLabel', appGroupId: _$appGroupId),
      dhuhrLabel: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.dhuhrLabel', appGroupId: _$appGroupId),
      asrLabel: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.asrLabel', appGroupId: _$appGroupId),
      maghribLabel: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.maghribLabel', appGroupId: _$appGroupId),
      ishaLabel: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.ishaLabel', appGroupId: _$appGroupId),
      timedData: timedData,
    );
  }


  static Future<bool?> updateWidget() {
    return HomeWidget.updateWidget(
      androidName: 'PrayerTimesHomeWidgetReceiver',
      iOSName: 'PrayerTimesHomeWidget',
    );
  }

  /// The URL a tap on the widget opens the app with, as the app
  /// will receive it.
  ///
  /// The configured `widgetUrl` carrying the `homeWidget` query
  /// parameter, parsed — so its scheme is lower-cased, exactly like
  /// the URL handed to the app.
  static final Uri widgetUrl = Uri.parse('iqro://open/prayer?homeWidget');

  /// The URL the app was launched with by a tap on the widget, or null
  /// when it was started any other way.
  ///
  /// Only the URL this widget opens on the platform the app is running
  /// on is reported; a tap on any other widget is not.
  static Future<Uri?> initiallyLaunchedFromWidget() async {
    final uri = await HomeWidget.initiallyLaunchedFromHomeWidget();
    if (uri == null || !_$matchesWidgetUrl(uri)) {
      return null;
    }
    return uri;
  }

  /// The URL of every tap on the widget while the app is running.
  ///
  /// A tap that started the app in the first place is not replayed here
  /// — read [initiallyLaunchedFromWidget] for that one, or listen to
  /// [launchedFromWidget] for both.
  ///
  /// Only the URL this widget opens on the platform the app is running
  /// on is reported; a tap on any other widget is not.
  static Stream<Uri> get widgetClicked =>
      HomeWidget.widgetClicked
          .where((uri) => uri != null && _$matchesWidgetUrl(uri))
          .cast<Uri>();

  /// Every tap on the widget, launch included.
  ///
  /// Yields the launch URL first when the app was started by a tap on
  /// the widget, then every tap that follows while it runs. Taps landing
  /// while the launch URL is still being read are kept, not dropped.
  ///
  /// Only the URL this widget opens on the platform the app is running
  /// on is reported; a tap on any other widget is not.
  static Stream<Uri> launchedFromWidget() async* {
    final clicks = StreamController<Uri>();
    final subscription = HomeWidget.widgetClicked.listen(
      (uri) {
        if (uri != null && _$matchesWidgetUrl(uri)) clicks.add(uri);
      },
      onDone: clicks.close,
    );
    try {
      final initial = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (initial != null && _$matchesWidgetUrl(initial)) yield initial;
      yield* clicks.stream;
    } finally {
      await subscription.cancel();
      await clicks.close();
    }
  }

  /// Whether [uri] is the URL this platform's widget opens.
  ///
  /// Schemes are compared case-insensitively: the URL reaches the app parsed,
  /// which lower-cases the scheme it was written with.
  static bool _$matchesWidgetUrl(Uri uri) {
    final url = _$platformWidgetUrl;
    if (url == null) return false;
    return _$lowerCaseScheme(uri) == _$lowerCaseScheme(url);
  }

  /// The URL the widget opens on the platform the app is running on, or
  /// null where it opens none.
  static Uri? get _$platformWidgetUrl {
    if (Platform.isAndroid) return widgetUrl;
    if (Platform.isIOS) return widgetUrl;
    return null;
  }

  static String _$lowerCaseScheme(Uri uri) {
    final text = uri.toString();
    return uri.scheme.toLowerCase() + text.substring(uri.scheme.length);
  }
}

class PrayerTimesTimedData {
  final String? dateLocation;
  final String? nextLabel;
  final String? nextPrayer;
  final String? fajrTime;
  final String? dhuhrTime;
  final String? asrTime;
  final String? maghribTime;
  final String? ishaTime;

  const PrayerTimesTimedData({
    this.dateLocation,
    this.nextLabel,
    this.nextPrayer,
    this.fajrTime,
    this.dhuhrTime,
    this.asrTime,
    this.maghribTime,
    this.ishaTime,
  });

  factory PrayerTimesTimedData.fromJson(Map<String, dynamic>? json) {
    json ??= const {};
    return PrayerTimesTimedData(
      dateLocation: _readString(json['dateLocation']) ?? '',
      nextLabel: _readString(json['nextLabel']) ?? '',
      nextPrayer: _readString(json['nextPrayer']) ?? '',
      fajrTime: _readString(json['fajrTime']) ?? '—',
      dhuhrTime: _readString(json['dhuhrTime']) ?? '—',
      asrTime: _readString(json['asrTime']) ?? '—',
      maghribTime: _readString(json['maghribTime']) ?? '—',
      ishaTime: _readString(json['ishaTime']) ?? '—',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (dateLocation != null) 'dateLocation': dateLocation,
      if (nextLabel != null) 'nextLabel': nextLabel,
      if (nextPrayer != null) 'nextPrayer': nextPrayer,
      if (fajrTime != null) 'fajrTime': fajrTime,
      if (dhuhrTime != null) 'dhuhrTime': dhuhrTime,
      if (asrTime != null) 'asrTime': asrTime,
      if (maghribTime != null) 'maghribTime': maghribTime,
      if (ishaTime != null) 'ishaTime': ishaTime,
    };
  }
}

String? _readString(Object? value) => value is String ? value : null;
