import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:geomag/geomag.dart';

/// Within this deviation the phone counts as facing the Qibla.
const qiblaAlignedDegrees = 3.0;

/// The aligned state is kept until the deviation exceeds this, so sensor noise
/// at the boundary does not flicker the highlight or repeat the vibration.
const qiblaReleaseDegrees = 5.0;

/// iOS reports heading accuracy in degrees; beyond this the arrow is a guess.
const _calibrationAccuracyDegrees = 30.0;

/// Android `SensorManager.SENSOR_STATUS_ACCURACY_LOW`.
const _androidAccuracyLow = 1;

/// Any angle in degrees mapped to `[0, 360)`.
double normalizeDegrees(double degrees) {
  // Dart's % is never negative here, but a tiny negative angle rounds to 360.
  final value = degrees % 360;
  return value == 360 ? 0 : value;
}

/// Shortest signed rotation from [from] to [to] in degrees, in `(-180, 180]`;
/// positive is clockwise.
double angleDifference(double from, double to) {
  final delta = normalizeDegrees(to - from);
  return delta > 180 ? delta - 360 : delta;
}

/// Magnetic declination in degrees east of true north from the World Magnetic
/// Model 2025 (NOAA/BGS), the model behind phone compasses.
double magneticDeclination({
  required double latitude,
  required double longitude,
  DateTime? at,
}) => GeoMag().calculate(latitude, longitude, 0, at ?? DateTime.now()).dec;

/// Compass heading of the screen's top edge in degrees clockwise from the
/// north of the rotation matrix's frame (magnetic north on Android).
///
/// [matrix] is Android's row-major device-to-world rotation matrix
/// (x east, y north, z up); [quarterTurns] is the display rotation
/// (`Surface.ROTATION_*`). The top edge is projected onto the horizon, so roll
/// and moderate pitch do not change the heading. Near upright, where that
/// projection vanishes, the direction out of the back of the phone takes over.
double? headingFromRotationMatrix(List<double> matrix, {int quarterTurns = 0}) {
  if (matrix.length != 9 || matrix.any((value) => !value.isFinite)) {
    return null;
  }
  // Device axis that points to the top of the screen for each display rotation.
  final (upX, upY) = switch (quarterTurns % 4) {
    1 => (1.0, 0.0),
    2 => (0.0, -1.0),
    3 => (-1.0, 0.0),
    _ => (0.0, 1.0),
  };
  final topEast = matrix[0] * upX + matrix[1] * upY;
  final topNorth = matrix[3] * upX + matrix[4] * upY;
  final backEast = -matrix[2];
  final backNorth = -matrix[5];
  final topWeight =
      ((math.sqrt(topEast * topEast + topNorth * topNorth) - .2) / .3).clamp(
        0.0,
        1.0,
      );
  final east = topWeight * topEast + (1 - topWeight) * backEast;
  final north = topWeight * topNorth + (1 - topWeight) * backNorth;
  if (east * east + north * north < 1e-6) return null;
  return normalizeDegrees(math.atan2(east, north) * 180 / math.pi);
}

/// One compass sample: heading of the screen's top edge from true north.
class CompassReading {
  const CompassReading({required this.heading, this.needsCalibration = false});

  final double heading;
  final bool needsCalibration;
}

/// Converts an event of the native `forum.iqro.app/qibla_compass` stream.
///
/// iOS sends CoreLocation's `trueHeading` (negative until it knows the
/// location), `magneticHeading` and `headingAccuracy` (negative while the
/// compass needs calibration). Android sends the rotation matrix, the display
/// rotation and the magnetometer accuracy status. Magnetic headings are moved
/// to true north with [declination].
CompassReading? compassReadingFromEvent(
  Object? event, {
  required double declination,
}) {
  if (event is! Map) return null;
  final matrix = event['matrix'];
  if (matrix is List) {
    final magnetic = headingFromRotationMatrix(<double>[
      for (final value in matrix) (value as num).toDouble(),
    ], quarterTurns: (event['rotation'] as num?)?.toInt() ?? 0);
    if (magnetic == null) return null;
    final status = (event['status'] as num?)?.toInt() ?? -1;
    return CompassReading(
      heading: normalizeDegrees(magnetic + declination),
      needsCalibration: status >= 0 && status <= _androidAccuracyLow,
    );
  }
  final trueHeading = (event['true'] as num?)?.toDouble();
  final magnetic = (event['magnetic'] as num?)?.toDouble();
  final accuracy = (event['accuracy'] as num?)?.toDouble();
  final double heading;
  if (trueHeading != null && trueHeading >= 0) {
    heading = trueHeading;
  } else if (magnetic != null && magnetic >= 0) {
    heading = magnetic + declination;
  } else {
    return null;
  }
  return CompassReading(
    heading: normalizeDegrees(heading),
    needsCalibration:
        accuracy != null &&
        (accuracy < 0 || accuracy > _calibrationAccuracyDegrees),
  );
}

/// Eases the displayed heading toward the sensor heading every frame: a
/// first-order low-pass filter that hides sensor jitter and keeps the dial
/// moving smoothly between sparse samples. The value is unwrapped (it can grow
/// past 360) so the dial never spins the long way round at north.
class HeadingSmoother {
  HeadingSmoother({this.timeConstant = const Duration(milliseconds: 200)});

  final Duration timeConstant;
  double? _value;

  /// Continuous heading for rotating the dial.
  double? get value => _value;

  /// Moves toward [target] by the share of the gap that [elapsed] covers.
  double step(double target, Duration elapsed) {
    final current = _value;
    if (current == null) return _value = normalizeDegrees(target);
    final share =
        1 - math.exp(-elapsed.inMicroseconds / timeConstant.inMicroseconds);
    return _value = current + angleDifference(current, target) * share;
  }
}

/// Native heading stream. It runs the sensors only while listened to, so the
/// sheet cancels it when it closes or the app leaves the foreground.
class QiblaCompass {
  const QiblaCompass();

  static const channel = EventChannel('forum.iqro.app/qibla_compass');

  Stream<Object?> events() => channel.receiveBroadcastStream();
}
