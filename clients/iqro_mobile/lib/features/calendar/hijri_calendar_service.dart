import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hijri/hijri_calendar.dart';

final calendarClockProvider = StreamProvider<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(minutes: 1), (_) => DateTime.now());
});

class HijriDate {
  const HijriDate(this.year, this.month, this.day, this.daysInMonth);
  final int year;
  final int month;
  final int day;
  final int daysInMonth;
}

/// Umm al-Qura date table, not a claim of local crescent observation.
/// All day arithmetic uses UTC civil components to avoid DST's 23/25-hour days.
class HijriCalendarService {
  const HijriCalendarService();
  static const minYear = 1356;
  static const maxYear = 1500;

  HijriDate? forCivilDate(DateTime date, {int adjustment = 0}) {
    final civil = DateTime.utc(
      date.year,
      date.month,
      date.day + adjustment.clamp(-2, 2),
    );
    if (civil.isBefore(DateTime.utc(1937, 3, 14)) ||
        !civil.isBefore(DateTime.utc(2077, 11, 17))) {
      return null;
    }
    try {
      final h = HijriCalendar.fromDate(civil);
      return HijriDate(h.hYear, h.hMonth, h.hDay, h.lengthOfMonth);
    } on Object {
      // Dates outside the pinned upstream table are displayed as unavailable.
      return null;
    }
  }

  DateTime civilDate(int year, int month, int day, {int adjustment = 0}) {
    if (year < minYear || year > maxYear || month < 1 || month > 12) {
      throw RangeError('Date outside supported Umm al-Qura table');
    }
    final converter = HijriCalendar();
    final length = converter.getDaysInMonth(year, month);
    if (day < 1 || day > length) throw RangeError.range(day, 1, length);
    final civil = converter.hijriToGregorian(year, month, day);
    return DateTime.utc(
      civil.year,
      civil.month,
      civil.day - adjustment.clamp(-2, 2),
    );
  }

  int monthLength(int year, int month) =>
      HijriCalendar().getDaysInMonth(year, month);

  HijriDate? now(DateTime clock, {int adjustment = 0, DateTime? maghribUtc}) {
    // Use sunset only for a supplied schedule for this civil day; never guess 18:00.
    final sunsetLocal = clock.isUtc
        ? maghribUtc?.toUtc()
        : maghribUtc?.toLocal();
    final sameDay =
        sunsetLocal != null &&
        sunsetLocal.year == clock.year &&
        sunsetLocal.month == clock.month &&
        sunsetLocal.day == clock.day;
    final afterSunset = sameDay && !clock.toUtc().isBefore(maghribUtc!);
    final day = DateTime.utc(
      clock.year,
      clock.month,
      clock.day + (afterSunset ? 1 : 0),
    );
    return forCivilDate(day, adjustment: adjustment);
  }
}

enum IslamicDay {
  ramadan,
  eidFitr,
  arafah,
  eidAdha,
  tashriq,
  ashura,
  whiteDays,
  lastTenNights,
}

List<IslamicDay> islamicDays(HijriDate day) {
  if (day.month == 10 && day.day == 1) return [IslamicDay.eidFitr];
  if (day.month == 12 && day.day == 10) return [IslamicDay.eidAdha];
  if (day.month == 12 && day.day >= 11 && day.day <= 13) {
    return [IslamicDay.tashriq];
  }
  return [
    if (day.month == 9) IslamicDay.ramadan,
    if (day.month == 9 && day.day >= 21) IslamicDay.lastTenNights,
    if (day.month == 12 && day.day == 9) IslamicDay.arafah,
    if (day.month == 1 && day.day == 10) IslamicDay.ashura,
    // Ramadan already has its own marker. Never recommend a voluntary fast on
    // the 13th of Dhul-Hijjah (a day of Tashriq).
    if (day.month != 9 && day.day >= 13 && day.day <= 15) IslamicDay.whiteDays,
  ];
}

String islamicDaySource(IslamicDay day) => switch (day) {
  IslamicDay.ramadan => 'https://quran.com/2/185',
  IslamicDay.eidFitr || IslamicDay.eidAdha => 'https://sunnah.com/bukhari:1990',
  IslamicDay.arafah || IslamicDay.ashura => 'https://sunnah.com/muslim:1162b',
  IslamicDay.tashriq => 'https://sunnah.com/muslim:1141a',
  IslamicDay.whiteDays => 'https://sunnah.com/abudawud:2449',
  IslamicDay.lastTenNights => 'https://sunnah.com/bukhari:2017',
};
