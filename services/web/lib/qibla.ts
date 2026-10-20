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

/**
 * Compass heading from a `deviceorientationabsolute` event (clockwise from north),
 * corrected for screen rotation. Returns null when the event carries no absolute heading.
 */
export function headingFromOrientation(
  event: { alpha: number | null; absolute?: boolean; webkitCompassHeading?: number },
  screenAngle = 0,
): number | null {
  if (typeof event.webkitCompassHeading === "number" && Number.isFinite(event.webkitCompassHeading)) {
    return (((event.webkitCompassHeading + screenAngle) % 360) + 360) % 360;
  }
  if (!event.absolute || event.alpha === null || !Number.isFinite(event.alpha)) return null;
  return (((360 - event.alpha + screenAngle) % 360) + 360) % 360;
}

const radians = (value: number) => (value * Math.PI) / 180;
