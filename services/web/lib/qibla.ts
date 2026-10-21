// Same great-circle bearing as the app's `qiblaBearing` (prayer_places.dart).
const KAABA_LATITUDE = 21.4225;
const KAABA_LONGITUDE = 39.8262;

/** Initial bearing to the Kaaba in degrees clockwise from geographic north, or null for invalid input. */
export function qiblaBearing(latitude: number, longitude: number): number | null {
  if (
    !Number.isFinite(latitude) ||
    !Number.isFinite(longitude) ||
    latitude < -90 ||
    latitude > 90 ||
    longitude < -180 ||
    longitude > 180
  ) {
    return null;
  }
  const latitudeRadians = radians(latitude);
  const kaabaLatitudeRadians = radians(KAABA_LATITUDE);
  const longitudeDelta = radians(KAABA_LONGITUDE - longitude);
  const y = Math.sin(longitudeDelta) * Math.cos(kaabaLatitudeRadians);
  const x =
    Math.cos(latitudeRadians) * Math.sin(kaabaLatitudeRadians) -
    Math.sin(latitudeRadians) * Math.cos(kaabaLatitudeRadians) * Math.cos(longitudeDelta);
  return (((Math.atan2(y, x) * 180) / Math.PI) + 360) % 360;
}

const EARTH_RADIUS_METERS = 6_371_000;
/** Closer than this the bearing is meaningless: the worshipper faces the Kaaba itself. */
export const KAABA_PROXIMITY_METERS = 50;

/** Great-circle distance to the Kaaba in meters, or null for invalid input. */
export function distanceToKaabaMeters(latitude: number, longitude: number): number | null {
  if (qiblaBearing(latitude, longitude) === null) return null;
  const latitudeDelta = radians(KAABA_LATITUDE - latitude);
  const longitudeDelta = radians(KAABA_LONGITUDE - longitude);
  const a =
    Math.sin(latitudeDelta / 2) ** 2 +
    Math.cos(radians(latitude)) * Math.cos(radians(KAABA_LATITUDE)) * Math.sin(longitudeDelta / 2) ** 2;
  return 2 * EARTH_RADIUS_METERS * Math.asin(Math.min(1, Math.sqrt(a)));
}

// The live compass mirrors the app's (qibla_compass.dart): same thresholds, smoothing and
// screen-top heading, so the site and the app agree on when the phone faces the Qibla.

/** Within this deviation the phone counts as facing the Qibla. */
export const QIBLA_ALIGNED_DEGREES = 3;

/**
 * The aligned state is kept until the deviation exceeds this, so sensor noise at the
 * boundary does not flicker the highlight or repeat the vibration.
 */
export const QIBLA_RELEASE_DEGREES = 5;

/** iOS reports heading accuracy in degrees; beyond this the arrow is a guess. */
const CALIBRATION_ACCURACY_DEGREES = 30;

/** Any angle in degrees mapped to `[0, 360)`. */
export function normalizeDegrees(degrees: number): number {
  const value = ((degrees % 360) + 360) % 360;
  // A tiny negative angle rounds to 360.
  return value === 360 ? 0 : value;
}

/** Shortest signed rotation from `from` to `to` in degrees, in `(-180, 180]`; positive is clockwise. */
export function angleDifference(from: number, to: number): number {
  const delta = normalizeDegrees(to - from);
  return delta > 180 ? delta - 360 : delta;
}

/**
 * Row-major device-to-earth rotation matrix (x east, y north, z up) of the W3C
 * DeviceOrientation angles: R = Rz(alpha)·Rx(beta)·Ry(gamma), the frame Android's
 * `SensorManager.getRotationMatrix` uses in the app.
 */
export function rotationMatrixFromOrientation(alpha: number, beta: number, gamma: number): number[] {
  const [cA, sA] = [Math.cos(radians(alpha)), Math.sin(radians(alpha))];
  const [cB, sB] = [Math.cos(radians(beta)), Math.sin(radians(beta))];
  const [cG, sG] = [Math.cos(radians(gamma)), Math.sin(radians(gamma))];
  return [
    cA * cG - sA * sB * sG, -cB * sA, cG * sA * sB + cA * sG,
    cG * sA + cA * sB * sG, cA * cB, sA * sG - cA * cG * sB,
    -cB * sG, sB, cB * cG,
  ];
}

/**
 * Heading of the screen's top edge in degrees clockwise from the matrix frame's north.
 * `quarterTurns` is the display rotation. The top edge is projected onto the horizon, so
 * roll and moderate pitch do not change the heading; near upright, where that projection
 * vanishes, the direction out of the back of the phone takes over.
 */
export function headingFromRotationMatrix(matrix: readonly number[], quarterTurns = 0): number | null {
  if (matrix.length !== 9 || matrix.some((value) => !Number.isFinite(value))) return null;
  // Device axis that points to the top of the screen for each display rotation.
  const [upX, upY] = [[0, 1], [1, 0], [0, -1], [-1, 0]][((quarterTurns % 4) + 4) % 4];
  const topEast = matrix[0] * upX + matrix[1] * upY;
  const topNorth = matrix[3] * upX + matrix[4] * upY;
  const backEast = -matrix[2];
  const backNorth = -matrix[5];
  const topWeight = Math.min(1, Math.max(0, (Math.hypot(topEast, topNorth) - 0.2) / 0.3));
  const east = topWeight * topEast + (1 - topWeight) * backEast;
  const north = topWeight * topNorth + (1 - topWeight) * backNorth;
  if (east * east + north * north < 1e-6) return null;
  return normalizeDegrees((Math.atan2(east, north) * 180) / Math.PI);
}

export type OrientationSample = {
  alpha: number | null;
  beta?: number | null;
  gamma?: number | null;
  absolute?: boolean;
  webkitCompassHeading?: number;
  webkitCompassAccuracy?: number;
};

/**
 * Magnetic heading of the screen's top edge from a device orientation event: iOS's
 * `webkitCompassHeading`, or the absolute angles of `deviceorientationabsolute`.
 * `screenAngle` is `screen.orientation.angle`. Null when the event has no absolute heading.
 */
export function headingFromOrientation(event: OrientationSample, screenAngle = 0): number | null {
  const compassHeading = event.webkitCompassHeading;
  // iOS reports a negative heading while it has none.
  if (typeof compassHeading === "number" && Number.isFinite(compassHeading) && compassHeading >= 0) {
    return normalizeDegrees(compassHeading + screenAngle);
  }
  if (!event.absolute || event.alpha === null || !Number.isFinite(event.alpha)) return null;
  return headingFromRotationMatrix(
    rotationMatrixFromOrientation(event.alpha, event.beta ?? 0, event.gamma ?? 0),
    Math.round(screenAngle / 90),
  );
}

/** One compass sample: heading of the screen's top edge from true north. */
export type CompassReading = {
  heading: number;
  needsCalibration: boolean;
  /** Only iOS reports accuracy; elsewhere a bad calibration cannot be detected. */
  accuracyKnown: boolean;
};

/** A compass sample from an orientation event; magnetic headings move to true north by `declination`. */
export function compassReadingFromOrientation(
  event: OrientationSample,
  screenAngle: number,
  declination: number,
): CompassReading | null {
  const magnetic = headingFromOrientation(event, screenAngle);
  if (magnetic === null) return null;
  const accuracy = event.webkitCompassAccuracy;
  const accuracyKnown = typeof accuracy === "number" && Number.isFinite(accuracy);
  return {
    heading: normalizeDegrees(magnetic + declination),
    needsCalibration: accuracyKnown && (accuracy < 0 || accuracy > CALIBRATION_ACCURACY_DEGREES),
    accuracyKnown,
  };
}

/** Whether the phone faces the Qibla, with hysteresis. An uncalibrated compass never claims it. */
export function facesQibla(heading: number, bearing: number, wasFacing: boolean, needsCalibration: boolean): boolean {
  if (needsCalibration) return false;
  return Math.abs(angleDifference(heading, bearing)) <= (wasFacing ? QIBLA_RELEASE_DEGREES : QIBLA_ALIGNED_DEGREES);
}

/**
 * Eases the displayed heading toward the sensor heading every frame: a first-order
 * low-pass filter that hides sensor jitter. The value is unwrapped (it can grow past 360),
 * so the dial never spins the long way round at north.
 */
export class HeadingSmoother {
  private current: number | null = null;
  private readonly timeConstantMs: number;

  constructor(timeConstantMs = 200) {
    this.timeConstantMs = timeConstantMs;
  }

  /** Continuous heading for rotating the dial. */
  get value(): number | null {
    return this.current;
  }

  /** Moves toward `target` by the share of the gap that `elapsedMs` covers. */
  step(target: number, elapsedMs: number): number {
    if (this.current === null) return (this.current = normalizeDegrees(target));
    const share = 1 - Math.exp(-elapsedMs / this.timeConstantMs);
    return (this.current += angleDifference(this.current, target) * share);
  }
}

const radians = (value: number) => (value * Math.PI) / 180;
