import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/calendar/calendar_catalog.dart';
import 'package:iqro_mobile/features/calendar/hijri_calendar_service.dart';

void main() {
  Map<String, Object?> seed() => Map<String, Object?>.from(
    jsonDecode(File('assets/calendar/events-v1.json').readAsStringSync())
        as Map,
  );

  test('common catalog and offline rules preserve all reviewed markers', () {
    final catalog = CalendarCatalog.fromJson(seed());
    expect(catalog.events.length, 8);
    for (var month = 1; month <= 12; month++) {
      for (var day = 1; day <= 30; day++) {
        final date = HijriDate(1448, month, day, 30);
        final legacy = islamicDays(date).map((e) => e.name).toList();
        final updated = catalog
            .forDate(date)
            .map(
              (e) => switch (e.code) {
                'white_days' => 'whiteDays',
                'last_ten_nights' => 'lastTenNights',
                'eid_fitr' => 'eidFitr',
                'eid_adha' => 'eidAdha',
                _ => e.code,
              },
            )
            .toList();
        expect(updated, legacy, reason: '$month/$day');
      }
    }
  });

  test('all month boundaries match the backend pinned table', () {
    final table =
        jsonDecode(
              File(
                '../../services/backend/src/quran_backend/modules/calendar/data/ummalqura-v1.json',
              ).readAsStringSync(),
            )
            as Map;
    final starts = (table['month_starts_mcjdn'] as List).cast<int>();
    const service = HijriCalendarService();
    final epoch = DateTime.utc(1858, 11, 16);
    for (var index = 0; index < starts.length - 1; index++) {
      expect(
        service.civilDate(1356 + index ~/ 12, index % 12 + 1, 1),
        epoch.add(Duration(days: starts[index])),
      );
    }
  });

  test('server edits and empty catalog replace bundled events', () {
    final json = seed();
    final events = json['events']! as List;
    (events.first['titles'] as Map)['ru'] = 'Название из админки';
    expect(
      CalendarCatalog.fromJson(json).events.first.title('ru'),
      'Название из админки',
    );
    expect(CalendarCatalog.fromJson({...json, 'events': []}).events, isEmpty);
  });

  test(
    'malformed versions, duplicates, dates and unsafe sources are rejected',
    () {
      for (final patch in <Map<String, Object?>>[
        {'method': 'tabular'},
        {'schema_version': 2},
        {'events': null},
        {'version': ''},
      ]) {
        expect(
          () => CalendarCatalog.fromJson({...seed(), ...patch}),
          throwsFormatException,
        );
      }
      final duplicate = seed();
      final events = duplicate['events']! as List;
      events.add(events.first);
      expect(() => CalendarCatalog.fromJson(duplicate), throwsFormatException);
      for (final url in [
        'http://example.org',
        'javascript:alert(1)',
        'https://user:pass@example.org',
      ]) {
        final json = seed();
        ((json['events']! as List).first['source'] as Map)['url'] = url;
        expect(() => CalendarCatalog.fromJson(json), throwsFormatException);
      }
    },
  );
}
