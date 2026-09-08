import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import 'hijri_calendar_service.dart';

const calendarMethod = 'ummalqura-hijri-3.0.1';

class CalendarEvent {
  CalendarEvent.fromJson(Map<String, Object?> json)
    : code = json['code']! as String,
      kind = json['kind']! as String,
      month = json['month']! as int,
      dayStart = json['day_start']! as int,
      dayEnd = json['day_end']! as int,
      excludeRamadan = json['exclude_ramadan']! as bool,
      titles = Map<String, String>.from(json['titles']! as Map),
      descriptions = Map<String, String>.from(json['descriptions']! as Map),
      source = Map<String, String>.from(json['source']! as Map) {
    final uri = Uri.tryParse(source['url'] ?? '');
    if (!RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(code) ||
        !['occasion', 'voluntary_fast', 'no_fast'].contains(kind) ||
        month < 0 ||
        month > 12 ||
        dayStart < 1 ||
        dayEnd > 30 ||
        dayEnd < dayStart ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (source['label']?.trim().isEmpty ?? true) ||
        ['ru', 'en', 'ar', 'tr'].any(
          (locale) =>
              (titles[locale]?.trim().isEmpty ?? true) ||
              (descriptions[locale]?.trim().isEmpty ?? true),
        )) {
      throw const FormatException('Invalid calendar event');
    }
  }

  final String code, kind;
  final int month, dayStart, dayEnd;
  final bool excludeRamadan;
  final Map<String, String> titles, descriptions, source;

  String title(String locale) => titles[locale] ?? titles['en']!;
  String description(String locale) =>
      descriptions[locale] ?? descriptions['en']!;

  bool matches(HijriDate date) {
    if ((month != 0 && month != date.month) ||
        date.day < dayStart ||
        date.day > dayEnd ||
        (excludeRamadan && date.month == 9)) {
      return false;
    }
    final noFast =
        (date.month == 10 && date.day == 1) ||
        (date.month == 12 && date.day >= 10 && date.day <= 13);
    return !(kind == 'voluntary_fast' && noFast);
  }
}

class CalendarCatalog {
  CalendarCatalog.fromJson(Object? value) {
    try {
      final json = Map<String, Object?>.from(value! as Map);
      if (json['schema_version'] != 1 ||
          json['method'] != calendarMethod ||
          json['min_year'] != 1356 ||
          json['max_year'] != 1500 ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(json['version']! as String)) {
        throw const FormatException('Unsupported calendar catalog');
      }
      version = json['version']! as String;
      final rows = json['events']! as List;
      if (rows.length > 500) {
        throw const FormatException('Calendar catalog too large');
      }
      events = List.unmodifiable(
        rows.map(
          (row) =>
              CalendarEvent.fromJson(Map<String, Object?>.from(row as Map)),
        ),
      );
      if (events.map((e) => e.code).toSet().length != events.length) {
        throw const FormatException('Duplicate calendar event');
      }
    } on TypeError {
      throw const FormatException('Malformed calendar catalog');
    }
  }
  late final String version;
  late final List<CalendarEvent> events;
  List<CalendarEvent> forDate(HijriDate date) =>
      events.where((event) => event.matches(date)).toList(growable: false);
}

/// Immediately renders the bundled catalog, then last-good disk data, then
/// the common public API. Failed or malformed refreshes never destroy offline data.
/// A server-published empty catalog stays empty (no resurrection of old events).
final calendarCatalogProvider = StreamProvider.autoDispose<CalendarCatalog>((
  ref,
) async* {
  final api = ref.watch(apiClientProvider);
  final database = ref.watch(localDatabaseProvider);
  final origin = ref.watch(appConfigProvider).apiV1;
  final key = 'calendar:$origin:catalog-v1';
  final timer = Timer(const Duration(minutes: 5), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  var hasCache = false;
  try {
    final cached = await database.readCache(key);
    if (cached != null) {
      yield CalendarCatalog.fromJson(cached.value);
      hasCache = true;
    }
  } on Object {
    // Corrupt cache is not a valid replacement for the bundled catalog.
  }
  if (!hasCache) {
    yield CalendarCatalog.fromJson(
      jsonDecode(await rootBundle.loadString('assets/calendar/events-v1.json')),
    );
  }
  try {
    final raw = await api.get('/calendar/catalog', public: true);
    final catalog = CalendarCatalog.fromJson(raw);
    yield catalog;
    await database.writeCache(key, raw, maxAge: const Duration(minutes: 4));
  } on Object {
    // Calendar dates and the last valid event catalog remain available offline.
  }
});
