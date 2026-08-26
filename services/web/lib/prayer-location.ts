export type PrayerLocationPreference = {
  latitude: string;
  longitude: string;
  timezone: string;
  updated_at: string;
};

const STORAGE_PREFIX = "quran_prayer_location_v1";

function storageKey(userId?: string | null): string {
  return `${STORAGE_PREFIX}:${userId || "anonymous"}`;
}

function normalizeLocation(
  value: Pick<PrayerLocationPreference, "latitude" | "longitude" | "timezone">,
): PrayerLocationPreference | null {
  const latitude = Number(value.latitude);
  const longitude = Number(value.longitude);
  const timezone = value.timezone.trim();
  if (
    !Number.isFinite(latitude) ||
    latitude < -90 ||
    latitude > 90 ||
    !Number.isFinite(longitude) ||
    longitude < -180 ||
    longitude > 180 ||
    !timezone ||
    timezone.length > 64
  ) {
    return null;
  }
  return {
    latitude: String(value.latitude).trim(),
    longitude: String(value.longitude).trim(),
    timezone,
    updated_at: new Date().toISOString(),
  };
}

export function loadPrayerLocationPreference(
  userId?: string | null,
): PrayerLocationPreference | null {
  if (typeof window === "undefined") return null;
  try {
    const raw = window.localStorage.getItem(storageKey(userId));
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Partial<PrayerLocationPreference>;
    if (
      typeof parsed.latitude !== "string" ||
      typeof parsed.longitude !== "string" ||
      typeof parsed.timezone !== "string"
    ) {
      return null;
    }
    return normalizeLocation({
      latitude: parsed.latitude,
      longitude: parsed.longitude,
      timezone: parsed.timezone,
    });
  } catch {
    return null;
  }
}

export function savePrayerLocationPreference(
  userId: string | null | undefined,
  value: Pick<PrayerLocationPreference, "latitude" | "longitude" | "timezone">,
): PrayerLocationPreference | null {
  const normalized = normalizeLocation(value);
  if (!normalized || typeof window === "undefined") return normalized;
  try {
    window.localStorage.setItem(storageKey(userId), JSON.stringify(normalized));
  } catch {
    // A blocked or full browser storage must not prevent prayer calculation.
  }
  return normalized;
}

export function clearPrayerLocationPreference(userId?: string | null): void {
  if (typeof window === "undefined") return;
  try {
    window.localStorage.removeItem(storageKey(userId));
  } catch {
    // Ignore unavailable browser storage during sign-out cleanup.
  }
}
