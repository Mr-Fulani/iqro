import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/calendar/hijri_calendar_service.dart';
import 'package:iqro_mobile/features/calendar/hijri_calendar_screen.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

void main() {
  const service = HijriCalendarService();
  test('documented Umm al-Qura conversion and inverse', () {
    final h = service.forCivilDate(DateTime(2018, 11, 12))!;
    expect((h.year, h.month, h.day), (1440, 3, 4));
    expect(service.civilDate(1440, 3, 4), DateTime.utc(2018, 11, 12));
  });
  test('month boundaries and dates round-trip without timezone drift', () {
    for (var year = 1400; year <= 1500; year++) {
      for (var month = 1; month <= 12; month++) {
        final length = service.monthLength(year, month);
        expect(length, inInclusiveRange(29, 30));
        for (final day in [1, length]) {
          for (final offset in [-2, 0, 2]) {
            final civil = service.civilDate(
              year,
              month,
              day,
              adjustment: offset,
            );
            final h = service.forCivilDate(civil, adjustment: offset)!;
            expect((h.year, h.month, h.day), (year, month, day));
          }
        }
      }
    }
  });
  test('sunset moves to the next Hijri date, never a guessed time', () {
    final before = DateTime.utc(2026, 9, 7, 15);
    final sunset = DateTime.utc(2026, 9, 7, 16);
    final base = service.now(before, maghribUtc: sunset)!;
    expect(service.now(before)!.day, base.day);
    expect(
      service
          .now(before, maghribUtc: sunset.subtract(const Duration(days: 1)))!
          .day,
      base.day,
    );
    final after = service.now(sunset, maghribUtc: sunset)!;
    final next = service.forCivilDate(DateTime.utc(2026, 9, 8))!;
    expect(
      (after.year, after.month, after.day),
      (next.year, next.month, next.day),
    );
  });
  test(
    'unsupported dates fail safely and invalid Hijri dates are rejected',
    () {
      expect(service.forCivilDate(DateTime(1900)), isNull);
      expect(service.forCivilDate(DateTime(2100)), isNull);
      expect(() => service.civilDate(1448, 13, 1), throwsRangeError);
      expect(() => service.civilDate(1448, 1, 0), throwsRangeError);
      expect(() => service.civilDate(1448, 1, 31), throwsRangeError);
    },
  );
  test('Eid and Tashriq never get a voluntary fasting marker', () {
    expect(islamicDays(const HijriDate(1448, 10, 1, 30)), [IslamicDay.eidFitr]);
    expect(islamicDays(const HijriDate(1448, 12, 10, 30)), [
      IslamicDay.eidAdha,
    ]);
    for (var day = 11; day <= 13; day++) {
      expect(islamicDays(HijriDate(1448, 12, day, 30)), [IslamicDay.tashriq]);
    }
    expect(islamicDays(const HijriDate(1448, 12, 14, 30)), [
      IslamicDay.whiteDays,
    ]);
    expect(islamicDays(const HijriDate(1448, 9, 27, 30)), [
      IslamicDay.ramadan,
      IslamicDay.lastTenNights,
    ]);
    expect(
      IslamicDay.values.every(
        (e) => Uri.parse(islamicDaySource(e)).scheme == 'https',
      ),
      isTrue,
    );
  });
  for (final locale in ['ru', 'en', 'ar', 'tr']) {
    testWidgets(
      '$locale calendar at narrow width and large text remains usable',
      (tester) async {
        tester.view.physicalSize = const Size(360, 950);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        int? selected;
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(1.8)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: HijriMonthGrid(
                    year: 1448,
                    month: 9,
                    selectedDay: 1,
                    today: const HijriDate(1448, 9, 1, 30),
                    adjustment: 0,
                    onSelect: (day) => selected = day,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('hijri-day-2')));
        expect(selected, 2);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
