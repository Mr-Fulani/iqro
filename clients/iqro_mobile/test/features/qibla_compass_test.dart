import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/features/prayer/qibla_compass.dart';

void main() {
  test('angles normalize to 0..360 and differ the short way round', () {
    expect(normalizeDegrees(-10), 350);
    expect(normalizeDegrees(360), 0);
    expect(normalizeDegrees(725), 5);
    expect(normalizeDegrees(-720), 0);
    expect(normalizeDegrees(-1e-15), 0);

    expect(angleDifference(350, 10), 20);
    expect(angleDifference(10, 350), -20);
    expect(angleDifference(90, 270), 180);
    expect(angleDifference(270, 90), 180);
    expect(angleDifference(123, 123), 0);
  });

  test('declination matches the official WMM2025 test values', () {
    // NOAA WMM2025_TestValues.txt rows at 0–3 km altitude.
    expect(
      magneticDeclination(
        latitude: -13,
        longitude: -59,
        at: DateTime.utc(2027, 7, 2),
      ),
      closeTo(-17.49, .15),
    );
    expect(
      magneticDeclination(
        latitude: -76,
        longitude: -75,
        at: DateTime.utc(2028),
      ),
      closeTo(29.87, .15),
    );
    expect(
      magneticDeclination(
        latitude: -50,
        longitude: -103,
        at: DateTime.utc(2025),
      ),
      closeTo(27.96, .15),
    );
  });

  group('heading from the Android rotation matrix', () {
    test('flat phone points where its top points', () {
      for (final heading in <double>[0, 90, 225, 359]) {
        expect(
          headingFromRotationMatrix(_matrix(heading: heading)),
          closeTo(heading, 1e-9),
        );
      }
    });

    test('roll and pitch do not move the heading', () {
      expect(
        headingFromRotationMatrix(_matrix(heading: 90, roll: 40)),
        closeTo(90, 1e-9),
      );
      expect(
        headingFromRotationMatrix(_matrix(heading: 300, pitch: 50, roll: 30)),
        closeTo(300, 1e-9),
      );
      expect(
        headingFromRotationMatrix(_matrix(heading: 45, pitch: 70)),
        closeTo(45, 1e-9),
      );
    });

    test('upright phone uses the direction out of its back', () {
      expect(
        headingFromRotationMatrix(_matrix(heading: 135, pitch: 90)),
        closeTo(135, 1e-9),
      );
      expect(
        headingFromRotationMatrix(_matrix(heading: 135, pitch: 80)),
        closeTo(135, 1e-9),
      );
    });

    test('display rotation measures from the top of the screen', () {
      // The phone's top edge points west in each case.
      final west = _matrix(heading: 270);
      expect(
        headingFromRotationMatrix(west, quarterTurns: 1),
        closeTo(0, 1e-9),
      );
      expect(
        headingFromRotationMatrix(west, quarterTurns: 2),
        closeTo(90, 1e-9),
      );
      expect(
        headingFromRotationMatrix(west, quarterTurns: 3),
        closeTo(180, 1e-9),
      );
    });

    test('rejects malformed matrices', () {
      expect(headingFromRotationMatrix(const <double>[1, 0, 0]), isNull);
      expect(
        headingFromRotationMatrix(<double>[double.nan, 0, 0, 0, 1, 0, 0, 0, 1]),
        isNull,
      );
    });
  });

  group('platform events', () {
    test('Android magnetic heading gets the declination', () {
      final reading = compassReadingFromEvent(<String, Object?>{
        'matrix': _matrix(heading: 350),
        'rotation': 0,
        'status': 3,
      }, declination: 15)!;
      expect(reading.heading, closeTo(5, 1e-9));
      expect(reading.needsCalibration, isFalse);
    });

    test('Android low or unreliable magnetometer asks for calibration', () {
      for (final status in <int>[0, 1]) {
        final reading = compassReadingFromEvent(<String, Object?>{
          'matrix': _matrix(heading: 10),
          'rotation': 0,
          'status': status,
        }, declination: 0)!;
        expect(reading.needsCalibration, isTrue);
      }
      final unknown = compassReadingFromEvent(<String, Object?>{
        'matrix': _matrix(heading: 10),
        'rotation': 0,
        'status': -1,
      }, declination: 0)!;
      expect(unknown.needsCalibration, isFalse);
    });

    test('iOS prefers CoreLocation true heading', () {
      final reading = compassReadingFromEvent(<String, Object?>{
        'true': 100.0,
        'magnetic': 90.0,
        'accuracy': 10.0,
      }, declination: 15)!;
      expect(reading.heading, 100);
      expect(reading.needsCalibration, isFalse);
    });

    test('iOS without a location fix corrects the magnetic heading', () {
      final reading = compassReadingFromEvent(<String, Object?>{
        'true': -1.0,
        'magnetic': 350.0,
        'accuracy': 10.0,
      }, declination: 15)!;
      expect(reading.heading, closeTo(5, 1e-9));
    });

    test('iOS invalid or coarse accuracy asks for calibration', () {
      for (final accuracy in <double>[-1, 45]) {
        final reading = compassReadingFromEvent(<String, Object?>{
          'true': 100.0,
          'magnetic': 90.0,
          'accuracy': accuracy,
        }, declination: 0)!;
        expect(reading.needsCalibration, isTrue);
      }
    });

    test('ignores events without a heading', () {
      expect(compassReadingFromEvent(null, declination: 0), isNull);
      expect(
        compassReadingFromEvent(<String, Object?>{
          'true': -1.0,
          'magnetic': -1.0,
        }, declination: 0),
        isNull,
      );
    });
  });

  group('heading smoother', () {
    test('starts at the first sample and crosses north the short way', () {
      final smoother = HeadingSmoother();
      expect(smoother.step(350, Duration.zero), 350);
      final next = smoother.step(10, const Duration(milliseconds: 200));
      expect(next, closeTo(350 + 20 * (1 - math.exp(-1)), 1e-9));
      expect(next, greaterThan(360));
      smoother.step(10, const Duration(seconds: 5));
      expect(normalizeDegrees(smoother.value!), closeTo(10, 1e-6));
    });

    test('damps sensor jitter', () {
      final smoother = HeadingSmoother();
      const frame = Duration(milliseconds: 33);
      smoother.step(100, frame);
      final values = <double>[
        for (var index = 0; index < 120; index++)
          smoother.step(index.isEven ? 102 : 98, frame),
      ];
      for (final value in values.skip(60)) {
        expect(value, closeTo(100, .25));
      }
    });

    test('does not move without elapsed time', () {
      final smoother = HeadingSmoother()..step(40, Duration.zero);
      expect(smoother.step(80, Duration.zero), 40);
    });
  });
}

/// Android device-to-world rotation matrix (x east, y north, z up) for a phone
/// whose top edge points to [heading], raised by [pitch] and rolled by [roll].
List<double> _matrix({double heading = 0, double pitch = 0, double roll = 0}) {
  final yaw = _rotation(-heading, axis: 2);
  final tilt = _rotation(pitch, axis: 0);
  final side = _rotation(roll, axis: 1);
  return _multiply(_multiply(yaw, tilt), side);
}

List<double> _rotation(double degrees, {required int axis}) {
  final angle = degrees * math.pi / 180;
  final c = math.cos(angle);
  final s = math.sin(angle);
  return switch (axis) {
    0 => <double>[1, 0, 0, 0, c, -s, 0, s, c],
    1 => <double>[c, 0, s, 0, 1, 0, -s, 0, c],
    _ => <double>[c, -s, 0, s, c, 0, 0, 0, 1],
  };
}

List<double> _multiply(List<double> a, List<double> b) => <double>[
  for (var row = 0; row < 3; row++)
    for (var column = 0; column < 3; column++)
      a[row * 3] * b[column] +
          a[row * 3 + 1] * b[3 + column] +
          a[row * 3 + 2] * b[6 + column],
];
