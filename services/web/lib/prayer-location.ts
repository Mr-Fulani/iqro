export type PrayerLocationPreference = {
  latitude: string;
  longitude: string;
  timezone: string;
  method_config_id?: string;
  asr_method?: "standard" | "hanafi";
  updated_at: string;
};

const STORAGE_PREFIX = "quran_prayer_location_v1";

function storageKey(userId?: string | null): string {
  return `${STORAGE_PREFIX}:${userId || "anonymous"}`;
}

function normalizePreference(
  value: Pick<PrayerLocationPreference, "latitude" | "longitude" | "timezone"> &
    Partial<Pick<PrayerLocationPreference, "method_config_id" | "asr_method">>,
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
    ...(typeof value.method_config_id === "string" && value.method_config_id.trim()
      ? { method_config_id: value.method_config_id.trim() }
      : {}),
    ...(value.asr_method === "standard" || value.asr_method === "hanafi"
      ? { asr_method: value.asr_method }
      : {}),
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
    return normalizePreference({
      latitude: parsed.latitude,
      longitude: parsed.longitude,
      timezone: parsed.timezone,
      method_config_id: parsed.method_config_id,
      asr_method: parsed.asr_method,
    });
  } catch {
    return null;
  }
}

export function savePrayerLocationPreference(
  userId: string | null | undefined,
  value: Pick<PrayerLocationPreference, "latitude" | "longitude" | "timezone"> &
    Partial<Pick<PrayerLocationPreference, "method_config_id" | "asr_method">>,
): PrayerLocationPreference | null {
  const existing = loadPrayerLocationPreference(userId);
  const normalized = normalizePreference({
    ...existing,
    ...value,
  });
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
