import 'dart:math' as math;

import 'package:timezone/timezone.dart' as tz;

const localPrayerEngineId = 'adhan-js-python-adapter';
const localPrayerEngineVersion = '4.4.4-quran.1-adhanpy.1.0.5';

const _prayerCodes = <String>[
  'fajr',
  'sunrise',
  'dhuhr',
  'asr',
  'maghrib',
  'isha',
];

class LocalPrayerCalculationUnavailable implements Exception {
  const LocalPrayerCalculationUnavailable(this.reason);

  final String reason;

  @override
  String toString() => 'Local prayer calculation unavailable: $reason';
}

class LocalPrayerMethod {
  const LocalPrayerMethod({
    required this.code,
    required this.fajrAngle,
    required this.ishaAngle,
    required this.ishaIntervalMinutes,
    required this.adjustments,
  });

  final String code;
  final double fajrAngle;
  final double? ishaAngle;
  final int? ishaIntervalMinutes;
  final Map<String, int> adjustments;
}

class LocalPrayerInput {
  const LocalPrayerInput({
    required this.latitude,
    required this.longitude,
    required this.date,
    required this.method,
    required this.highLatitudeRule,
    required this.polarResolution,
    this.hanafiAsr = false,
    this.adjustments = const <String, int>{},
  });

  final double latitude;
  final double longitude;
  final DateTime date;
  final LocalPrayerMethod method;
  final String highLatitudeRule;
  final String polarResolution;
  final bool hanafiAsr;
  final Map<String, int> adjustments;

  LocalPrayerInput copyWith({DateTime? date}) => LocalPrayerInput(
    latitude: latitude,
    longitude: longitude,
    date: date ?? this.date,
    method: method,
    highLatitudeRule: highLatitudeRule,
    polarResolution: polarResolution,
    hanafiAsr: hanafiAsr,
    adjustments: adjustments,
  );
}

class LocalPrayerFallback {
  const LocalPrayerFallback({
    required this.applied,
    this.strategy,
    this.reason,
    this.referenceDate,
    this.referenceLatitude,
  });

  final bool applied;
  final String? strategy;
  final String? reason;
  final DateTime? referenceDate;
  final double? referenceLatitude;
}

class LocalPrayerResult {
  const LocalPrayerResult({required this.timesUtc, required this.fallback});

  final Map<String, DateTime> timesUtc;
  final LocalPrayerFallback fallback;
}

class LocalCivilPrayerResult {
  const LocalCivilPrayerResult({
    required this.result,
    required this.astronomicalDate,
  });

  final LocalPrayerResult result;
  final DateTime astronomicalDate;
}

/// A deterministic Dart port of IQRO backend's pinned Adhan 4.4.4 adapter.
/// It deliberately accepts only the exact engine version exposed by backend.
class LocalPrayerEngine {
  const LocalPrayerEngine();

  LocalCivilPrayerResult calculateForCivilDate(
    LocalPrayerInput input,
    tz.Location location,
  ) {
    final requestedDate = _dateOnly(input.date);
    var result = calculate(input.copyWith(date: requestedDate));
    final observed = tz.TZDateTime.from(result.timesUtc['dhuhr']!, location);
    final observedDate = DateTime.utc(
      observed.year,
      observed.month,
      observed.day,
    );
    final shift = requestedDate.difference(observedDate).inDays;
    if (shift == 0) {
      return LocalCivilPrayerResult(
        result: result,
        astronomicalDate: requestedDate,
      );
    }
    final astronomicalDate = requestedDate.add(Duration(days: shift));
    result = calculate(input.copyWith(date: astronomicalDate));
    final corrected = tz.TZDateTime.from(result.timesUtc['dhuhr']!, location);
    if (corrected.year != requestedDate.year ||
        corrected.month != requestedDate.month ||
        corrected.day != requestedDate.day) {
      throw const LocalPrayerCalculationUnavailable(
        'civil_date_alignment_failed',
      );
    }
    return LocalCivilPrayerResult(
      result: result,
      astronomicalDate: astronomicalDate,
    );
  }

  LocalPrayerResult calculate(LocalPrayerInput input) {
    if (!input.latitude.isFinite ||
        !input.longitude.isFinite ||
        input.latitude < -90 ||
        input.latitude > 90 ||
        input.longitude < -180 ||
        input.longitude > 180 ||
        input.method.fajrAngle <= 0 ||
        (input.method.ishaAngle == null) ==
            (input.method.ishaIntervalMinutes == null)) {
      throw const LocalPrayerCalculationUnavailable('invalid_input');
    }
    final resolved = _resolveSolarTime(input);
    final times = _calculateTimes(input, resolved);
    if (times.length != _prayerCodes.length) {
      throw const LocalPrayerCalculationUnavailable('incomplete_result');
    }
    return LocalPrayerResult(timesUtc: times, fallback: resolved.fallback);
  }

  _ResolvedSolarTime _resolveSolarTime(LocalPrayerInput input) {
    final date = _dateOnly(input.date);
    final today = _SolarTime(date, input.latitude, input.longitude);
    final tomorrow = _SolarTime(
      date.add(const Duration(days: 1)),
      input.latitude,
      input.longitude,
    );
    if (today.valid && tomorrow.valid) {
      return _ResolvedSolarTime(
        today: today,
        tomorrow: tomorrow,
        calculationLatitude: input.latitude,
        fallback: const LocalPrayerFallback(applied: false),
      );
    }
    final resolved = switch (input.polarResolution) {
      'aqrab_yaum' => _resolveAqrabYaum(input),
      'aqrab_balad' => _resolveAqrabBalad(input),
      _ => null,
    };
    if (resolved == null) {
      throw const LocalPrayerCalculationUnavailable(
        'polar_sunrise_or_sunset_unresolved',
      );
    }
    return resolved;
  }

  _ResolvedSolarTime? _resolveAqrabYaum(LocalPrayerInput input) {
    final date = _dateOnly(input.date);
    for (var distance = 1; distance <= 183; distance += 1) {
      for (final direction in const <int>[1, -1]) {
        final reference = date.add(Duration(days: distance * direction));
        final today = _SolarTime(reference, input.latitude, input.longitude);
        final tomorrow = _SolarTime(
          reference.add(const Duration(days: 1)),
          input.latitude,
          input.longitude,
        );
        if (today.valid && tomorrow.valid) {
          return _ResolvedSolarTime(
            today: today,
            tomorrow: tomorrow,
            calculationLatitude: input.latitude,
            fallback: LocalPrayerFallback(
              applied: true,
              strategy: 'aqrab_yaum',
              reason: 'polar_sunrise_or_sunset_unavailable',
              referenceDate: reference,
            ),
          );
        }
      }
    }
    return null;
  }

  _ResolvedSolarTime? _resolveAqrabBalad(LocalPrayerInput input) {
    final direction = input.latitude > 0 ? 1.0 : -1.0;
    var latitude = input.latitude - direction * .5;
    final date = _dateOnly(input.date);
    while (latitude.abs() >= 65) {
      final today = _SolarTime(date, latitude, input.longitude);
      final tomorrow = _SolarTime(
        date.add(const Duration(days: 1)),
        latitude,
        input.longitude,
      );
      if (today.valid && tomorrow.valid) {
        return _ResolvedSolarTime(
          today: today,
          tomorrow: tomorrow,
          calculationLatitude: latitude,
          fallback: LocalPrayerFallback(
            applied: true,
            strategy: 'aqrab_balad',
            reason: 'polar_sunrise_or_sunset_unavailable',
            referenceLatitude: latitude,
          ),
        );
      }
      latitude -= direction * .5;
    }
    return null;
  }

  Map<String, DateTime> _calculateTimes(
    LocalPrayerInput input,
    _ResolvedSolarTime resolved,
  ) {
    final date = _dateOnly(input.date);
    final tomorrowDate = date.add(const Duration(days: 1));
    final solar = resolved.today;
    final dhuhr = _asUtcDateTime(solar.transit, date);
    final sunrise = _asUtcDateTime(solar.sunrise, date);
    final sunset = _asUtcDateTime(solar.sunset, date);
    final tomorrowSunrise = _asUtcDateTime(
      resolved.tomorrow.sunrise,
      tomorrowDate,
    );
    final asr = _asUtcDateTime(solar.afternoon(input.hanafiAsr ? 2 : 1), date);
    if (dhuhr == null ||
        sunrise == null ||
        sunset == null ||
        tomorrowSunrise == null ||
        asr == null) {
      throw const LocalPrayerCalculationUnavailable(
        'required_solar_event_unavailable',
      );
    }
    final nightSeconds =
        tomorrowSunrise.difference(sunset).inMicroseconds / 1000000;
    if (!nightSeconds.isFinite || nightSeconds <= 0) {
      throw const LocalPrayerCalculationUnavailable('invalid_night_duration');
    }

    var fajr = _asUtcDateTime(
      solar.hourAngle(-input.method.fajrAngle, afterTransit: false),
      date,
    );
    if (_isMoonsighting(input.method.code) && input.latitude >= 55) {
      fajr = sunrise.subtract(_seconds(nightSeconds / 7));
    }
    final safeFajr = _safeFajr(input, sunrise, nightSeconds);
    if (fajr == null || safeFajr.isAfter(fajr)) fajr = safeFajr;

    late final DateTime isha;
    if (input.method.ishaIntervalMinutes != null) {
      isha = sunset.add(Duration(minutes: input.method.ishaIntervalMinutes!));
    } else {
      final candidate = _asUtcDateTime(
        solar.hourAngle(-input.method.ishaAngle!, afterTransit: true),
        date,
      );
      final moonCandidate =
          _isMoonsighting(input.method.code) && input.latitude >= 55
          ? sunset.add(_seconds(nightSeconds / 7))
          : candidate;
      final safeIsha = _safeIsha(input, sunset, nightSeconds);
      isha = moonCandidate == null || safeIsha.isBefore(moonCandidate)
          ? safeIsha
          : moonCandidate;
    }

    final raw = <String, DateTime>{
      'fajr': fajr,
      'sunrise': sunrise,
      'dhuhr': dhuhr,
      'asr': asr,
      'maghrib': sunset,
      'isha': isha,
    };
    return raw.map((code, value) {
      final adjustment =
          (input.method.adjustments[code] ?? 0) +
          (input.adjustments[code] ?? 0);
      return MapEntry(
        code,
        _roundNearest(value.add(Duration(minutes: adjustment))),
      );
    });
  }

  DateTime _safeFajr(
    LocalPrayerInput input,
    DateTime sunrise,
    double nightSeconds,
  ) {
    if (_isMoonsighting(input.method.code)) {
      return _seasonAdjustedMorning(input.latitude, input.date, sunrise);
    }
    return sunrise.subtract(
      _seconds(
        nightSeconds *
            _nightPortion(input.highLatitudeRule, input.method.fajrAngle),
      ),
    );
  }

  DateTime _safeIsha(
    LocalPrayerInput input,
    DateTime sunset,
    double nightSeconds,
  ) {
    if (_isMoonsighting(input.method.code)) {
      return _seasonAdjustedEvening(input.latitude, input.date, sunset);
    }
    return sunset.add(
      _seconds(
        nightSeconds *
            _nightPortion(input.highLatitudeRule, input.method.ishaAngle!),
      ),
    );
  }
}

class _ResolvedSolarTime {
  const _ResolvedSolarTime({
    required this.today,
    required this.tomorrow,
    required this.calculationLatitude,
    required this.fallback,
  });

  final _SolarTime today;
  final _SolarTime tomorrow;
  final double calculationLatitude;
  final LocalPrayerFallback fallback;
}

class _SolarTime {
  _SolarTime(DateTime date, this.latitude, this.longitude) {
    final julian = _julianDay(date.year, date.month, date.day);
    final previous = _SolarCoordinates(julian - 1);
    final current = _SolarCoordinates(julian);
    final following = _SolarCoordinates(julian + 1);
    final approximate = _approximateTransit(
      longitude,
      current.apparentSiderealTime,
      current.rightAscension,
    );
    _approximate = approximate;
    _previous = previous;
    _current = current;
    _following = following;
    transit = _correctedTransit(
      approximate,
      longitude,
      current.apparentSiderealTime,
      current.rightAscension,
      previous.rightAscension,
      following.rightAscension,
    );
    sunrise = hourAngle(-50 / 60, afterTransit: false);
    sunset = hourAngle(-50 / 60, afterTransit: true);
  }

  final double latitude;
  final double longitude;
  late final double _approximate;
  late final _SolarCoordinates _previous;
  late final _SolarCoordinates _current;
  late final _SolarCoordinates _following;
  late final double transit;
  late final double sunrise;
  late final double sunset;

  bool get valid => sunrise.isFinite && sunset.isFinite;

  double hourAngle(double angle, {required bool afterTransit}) =>
      _correctedHourAngle(
        _approximate,
        angle,
        latitude,
        longitude,
        afterTransit,
        _current.apparentSiderealTime,
        _current.rightAscension,
        _previous.rightAscension,
        _following.rightAscension,
        _current.declination,
        _previous.declination,
        _following.declination,
      );

  double afternoon(int shadowLength) {
    final tangent = (latitude - _current.declination).abs();
    final inverse = shadowLength + math.tan(_radians(tangent));
    final angle = _degrees(math.atan(1 / inverse));
    return hourAngle(angle, afterTransit: true);
  }
}

class _SolarCoordinates {
  _SolarCoordinates(double julianDay) {
    final century = (julianDay - 2451545.0) / 36525;
    final meanSolar = _meanSolarLongitude(century);
    final meanLunar = _meanLunarLongitude(century);
    final node = _ascendingLunarNodeLongitude(century);
    final longitude = _radians(_apparentSolarLongitude(century, meanSolar));
    final sidereal = _meanSiderealTime(century);
    final nutationLongitude = _nutationInLongitude(meanSolar, meanLunar, node);
    final nutationObliquity = _nutationInObliquity(meanSolar, meanLunar, node);
    final meanObliquity = _meanObliquity(century);
    final apparentObliquity = _radians(
      _apparentObliquity(century, meanObliquity),
    );
    declination = _degrees(
      math.asin(math.sin(apparentObliquity) * math.sin(longitude)),
    );
    rightAscension = _unwind(
      _degrees(
        math.atan2(
          math.cos(apparentObliquity) * math.sin(longitude),
          math.cos(longitude),
        ),
      ),
    );
    apparentSiderealTime =
        sidereal +
        ((nutationLongitude * 3600) *
                math.cos(_radians(meanObliquity + nutationObliquity))) /
            3600;
  }

  late final double declination;
  late final double rightAscension;
  late final double apparentSiderealTime;
}

double _julianDay(int year, int month, int day) {
  final y = month > 2 ? year : year - 1;
  final m = month > 2 ? month : month + 12;
  final a = (y / 100).floor();
  final b = (2 - a + a / 4).floor();
  final i0 = (365.25 * (y + 4716)).toInt();
  final i1 = (30.6001 * (m + 1)).toInt();
  return i0 + i1 + day + b - 1524.5;
}

double _meanSolarLongitude(double t) =>
    _unwind(280.4664567 + 36000.76983 * t + .0003032 * t * t);
double _meanLunarLongitude(double t) => _unwind(218.3165 + 481267.8813 * t);
double _ascendingLunarNodeLongitude(double t) => _unwind(
  125.04452 - 1934.136261 * t + .0020708 * t * t + t * t * t / 450000,
);
double _meanSolarAnomaly(double t) =>
    _unwind(357.52911 + 35999.05029 * t - .0001537 * t * t);
double _solarEquation(double t, double anomaly) {
  final m = _radians(anomaly);
  return (1.914602 - .004817 * t - .000014 * t * t) * math.sin(m) +
      (.019993 - .000101 * t) * math.sin(2 * m) +
      .000289 * math.sin(3 * m);
}

double _apparentSolarLongitude(double t, double meanSolar) {
  final longitude = meanSolar + _solarEquation(t, _meanSolarAnomaly(t));
  final omega = 125.04 - 1934.136 * t;
  return _unwind(longitude - .00569 - .00478 * math.sin(_radians(omega)));
}

double _meanSiderealTime(double t) {
  final julian = t * 36525 + 2451545;
  return _unwind(
    280.46061837 +
        360.98564736629 * (julian - 2451545) +
        .000387933 * t * t -
        t * t * t / 38710000,
  );
}

double _nutationInLongitude(double l0, double lp, double node) =>
    (-17.2 / 3600) * math.sin(_radians(node)) -
    (1.32 / 3600) * math.sin(2 * _radians(l0)) -
    (.23 / 3600) * math.sin(2 * _radians(lp)) +
    (.21 / 3600) * math.sin(2 * _radians(node));
double _nutationInObliquity(double l0, double lp, double node) =>
    (9.2 / 3600) * math.cos(_radians(node)) +
    (.57 / 3600) * math.cos(2 * _radians(l0)) +
    (.10 / 3600) * math.cos(2 * _radians(lp)) -
    (.09 / 3600) * math.cos(2 * _radians(node));
double _meanObliquity(double t) =>
    23.439291 - .013004167 * t - .0000001639 * t * t + .0000005036 * t * t * t;
double _apparentObliquity(double t, double mean) =>
    mean + .00256 * math.cos(_radians(125.04 - 1934.136 * t));

double _approximateTransit(
  double longitude,
  double sidereal,
  double rightAscension,
) {
  final transit = _normalize((rightAscension - longitude - sidereal) / 360, 1);
  final expected = _normalize((12 - longitude / 15) / 24, 1);
  if (transit - expected > .5) return transit - 1;
  if (expected - transit > .5) return transit + 1;
  return transit;
}

double _correctedTransit(
  double m0,
  double longitude,
  double sidereal,
  double rightAscension,
  double previousRightAscension,
  double followingRightAscension,
) {
  final longitudeWest = -longitude;
  final theta = _unwind(sidereal + 360.985647 * m0);
  final alpha = _unwind(
    _interpolateAngles(
      rightAscension,
      previousRightAscension,
      followingRightAscension,
      m0,
    ),
  );
  final h = _closestAngle(theta - longitudeWest - alpha);
  return (m0 + h / -360) * 24;
}

double _correctedHourAngle(
  double m0,
  double angle,
  double latitude,
  double longitude,
  bool afterTransit,
  double sidereal,
  double rightAscension,
  double previousRightAscension,
  double followingRightAscension,
  double declination,
  double previousDeclination,
  double followingDeclination,
) {
  final term1 =
      math.sin(_radians(angle)) -
      math.sin(_radians(latitude)) * math.sin(_radians(declination));
  final term2 = math.cos(_radians(latitude)) * math.cos(_radians(declination));
  final h0 = _degrees(math.acos(term1 / term2));
  if (!h0.isFinite) return double.nan;
  final m = afterTransit ? m0 + h0 / 360 : m0 - h0 / 360;
  final theta = _unwind(sidereal + 360.985647 * m);
  final alpha = _unwind(
    _interpolateAngles(
      rightAscension,
      previousRightAscension,
      followingRightAscension,
      m,
    ),
  );
  final delta = _interpolate(
    declination,
    previousDeclination,
    followingDeclination,
    m,
  );
  final h = theta + longitude - alpha;
  final altitude = _altitude(latitude, delta, h);
  final denominator =
      360 *
      math.cos(_radians(delta)) *
      math.cos(_radians(latitude)) *
      math.sin(_radians(h));
  final correction = (altitude - angle) / denominator;
  return (m + correction) * 24;
}

double _interpolate(double y2, double y1, double y3, double n) {
  final a = y2 - y1;
  final b = y3 - y2;
  return y2 + n / 2 * (a + b + n * (b - a));
}

double _interpolateAngles(double y2, double y1, double y3, double n) {
  final a = _unwind(y2 - y1);
  final b = _unwind(y3 - y2);
  return y2 + n / 2 * (a + b + n * (b - a));
}

double _altitude(double latitude, double declination, double hourAngle) =>
    _degrees(
      math.asin(
        math.sin(_radians(latitude)) * math.sin(_radians(declination)) +
            math.cos(_radians(latitude)) *
                math.cos(_radians(declination)) *
                math.cos(_radians(hourAngle)),
      ),
    );

DateTime? _asUtcDateTime(double value, DateTime date) {
  if (!value.isFinite) return null;
  final hours = value.floor();
  final minutes = ((value - hours) * 60).floor();
  final seconds = ((value - (hours + minutes / 60)) * 3600).floor();
  return DateTime.utc(
    date.year,
    date.month,
    date.day,
  ).add(Duration(hours: hours, minutes: minutes, seconds: seconds));
}

DateTime _roundNearest(DateTime value) {
  final offset = value.second >= 30 ? 60 - value.second : -value.second;
  return value.add(Duration(seconds: offset, microseconds: -value.microsecond));
}

double _nightPortion(String rule, double angle) => switch (rule) {
  'middle_of_night' => .5,
  'seventh_of_night' => 1 / 7,
  'twilight_angle' => angle / 60,
  _ => throw const LocalPrayerCalculationUnavailable(
    'invalid_high_latitude_rule',
  ),
};

bool _isMoonsighting(String code) =>
    code.replaceAll('-', '_') == 'moonsighting_committee';

DateTime _seasonAdjustedMorning(
  double latitude,
  DateTime date,
  DateTime sunrise,
) {
  final absolute = latitude.abs();
  final adjustment = _seasonalAdjustment(date, latitude, <double>[
    75 + 28.65 / 55 * absolute,
    75 + 19.44 / 55 * absolute,
    75 + 32.74 / 55 * absolute,
    75 + 48.10 / 55 * absolute,
  ]);
  return sunrise.subtract(Duration(seconds: (adjustment * 60 + .5).floor()));
}

DateTime _seasonAdjustedEvening(
  double latitude,
  DateTime date,
  DateTime sunset,
) {
  final absolute = latitude.abs();
  final adjustment = _seasonalAdjustment(date, latitude, <double>[
    75 + 25.6 / 55 * absolute,
    75 + 2.05 / 55 * absolute,
    75 - 9.21 / 55 * absolute,
    75 + 6.14 / 55 * absolute,
  ]);
  return sunset.add(Duration(seconds: (adjustment * 60 + .5).floor()));
}

double _seasonalAdjustment(
  DateTime date,
  double latitude,
  List<double> values,
) {
  final dayOfYear =
      DateTime.utc(
        date.year,
        date.month,
        date.day,
      ).difference(DateTime.utc(date.year)).inDays +
      1;
  final daysInYear = _isLeapYear(date.year) ? 366 : 365;
  late final int day;
  if (latitude >= 0) {
    final result = dayOfYear + 10;
    day = result >= daysInYear ? result - daysInYear : result;
  } else {
    final result = dayOfYear - (_isLeapYear(date.year) ? 173 : 172);
    day = result < 0 ? result + daysInYear : result;
  }
  final a = values[0];
  final b = values[1];
  final c = values[2];
  final d = values[3];
  if (day < 91) return a + (b - a) / 91 * day;
  if (day < 137) return b + (c - b) / 46 * (day - 91);
  if (day < 183) return c + (d - c) / 46 * (day - 137);
  if (day < 229) return d + (c - d) / 46 * (day - 183);
  if (day < 275) return c + (b - c) / 46 * (day - 229);
  return b + (a - b) / 91 * (day - 275);
}

bool _isLeapYear(int year) =>
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
Duration _seconds(double value) =>
    Duration(microseconds: (value * 1000000).round());
DateTime _dateOnly(DateTime value) =>
    DateTime.utc(value.year, value.month, value.day);
double _normalize(double value, double bound) =>
    value - bound * (value / bound).floor();
double _unwind(double value) => _normalize(value, 360);
double _closestAngle(double value) =>
    value >= -180 && value <= 180 ? value : value - 360 * (value / 360).round();
double _radians(double degrees) => degrees * math.pi / 180;
double _degrees(double radians) => radians * 180 / math.pi;
