"use client";

import { useEffect, useState } from "react";
import {
  api,
  PrayerAdjustments,
  PrayerCalculationResponse,
  PrayerMethod,
  PrayerProfile,
} from "../../lib/api";
import { useAuth } from "../../lib/auth-context";
import { useI18n } from "../../lib/i18n-context";
import { MessageKey } from "../../lib/i18n";

const PRESET_CITIES = [
  { label: "prayer.city.makkah" as MessageKey, lat: "21.4225", lng: "39.8262", tz: "Asia/Riyadh" },
  { label: "prayer.city.madinah" as MessageKey, lat: "24.4672", lng: "39.6111", tz: "Asia/Riyadh" },
  { label: "prayer.city.moscow" as MessageKey, lat: "55.7558", lng: "37.6173", tz: "Europe/Moscow" },
  { label: "prayer.city.kazan" as MessageKey, lat: "55.7887", lng: "49.1221", tz: "Europe/Moscow" },
  { label: "prayer.city.tashkent" as MessageKey, lat: "41.2995", lng: "69.2401", tz: "Asia/Tashkent" },
  { label: "prayer.city.istanbul" as MessageKey, lat: "41.0082", lng: "28.9784", tz: "Europe/Istanbul" },
  { label: "prayer.city.london" as MessageKey, lat: "51.5074", lng: "-0.1278", tz: "Europe/London" },
];

const ADJUSTMENT_LABELS: Array<[keyof PrayerAdjustments, MessageKey]> = [
  ["fajr", "prayer.fajr"],
  ["sunrise", "prayer.sunrise"],
  ["dhuhr", "prayer.dhuhr"],
  ["asr", "prayer.asr"],
  ["maghrib", "prayer.maghrib"],
  ["isha", "prayer.isha"],
];

export default function PrayerPage() {
  const { isLoggedIn, loginGuest } = useAuth();
  const { locale, t, formatDate } = useI18n();
  const [methods, setMethods] = useState<PrayerMethod[]>([]);
  const [selectedMethodId, setSelectedMethodId] = useState<string>("");
  const [date, setDate] = useState<string>(() => new Date().toISOString().slice(0, 10));
  const [latitude, setLatitude] = useState<string>("21.4225");
  const [longitude, setLongitude] = useState<string>("39.8262");
  const [timezone, setTimezone] = useState<string>("Asia/Riyadh");
  const [asrMethod, setAsrMethod] = useState<"standard" | "hanafi">("standard");
  const [highLatitudeRule, setHighLatitudeRule] = useState<
    PrayerProfile["high_latitude_rule"]
  >("middle_of_night");
  const [polarResolution, setPolarResolution] = useState<PrayerProfile["polar_resolution"]>(
    "unresolved",
  );
  const [adjustments, setAdjustments] = useState<PrayerAdjustments>({
    fajr: 0,
    sunrise: 0,
    dhuhr: 0,
    asr: 0,
    maghrib: 0,
    isha: 0,
  });
  const [profileTimezoneMode, setProfileTimezoneMode] = useState<
    PrayerProfile["timezone_mode"]
  >("device_local");
  const [fixedTimezone, setFixedTimezone] = useState<string>("Europe/Istanbul");
  const [profileRevision, setProfileRevision] = useState<number>(0);
  const [profileMessage, setProfileMessage] = useState<string | null>(null);
  const [savingProfile, setSavingProfile] = useState<boolean>(false);

  const [result, setResult] = useState<PrayerCalculationResponse | null>(null);
  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  // Load methods on mount
  useEffect(() => {
    api
      .getPrayerMethods()
      .then((res) => {
        setMethods(res.methods || []);
        const defaultMethod = res.methods.find((m) => m.available) || res.methods[0];
        if (defaultMethod) {
          setSelectedMethodId(defaultMethod.id);
        }
      })
      .catch((err) => {
        setError(api.normalizeError(err));
      });
  }, []);

  useEffect(() => {
    if (!isLoggedIn) return;
    let active = true;
    api
      .getPrayerProfile()
      .then((profile) => {
        if (!active) return;
        setSelectedMethodId(profile.method_config.id);
        setAsrMethod(profile.asr_method);
        setHighLatitudeRule(profile.high_latitude_rule);
        setPolarResolution(profile.polar_resolution);
        setAdjustments(profile.adjustments);
        setProfileTimezoneMode(profile.timezone_mode);
        if (profile.fixed_timezone) {
          setFixedTimezone(profile.fixed_timezone);
          setTimezone(profile.fixed_timezone);
        }
        setProfileRevision(profile.revision);
        setProfileMessage(
          profile.method_available
            ? t("prayer.profileLoaded", { revision: profile.revision })
            : t("prayer.methodUnavailable"),
        );
      })
      .catch(() => {
        if (active) setProfileRevision(0);
      });
    return () => {
      active = false;
    };
  }, [isLoggedIn, t]);

  const handleCitySelect = (cityIndex: number) => {
    const city = PRESET_CITIES[cityIndex];
    if (city) {
      setLatitude(city.lat);
      setLongitude(city.lng);
      setTimezone(city.tz);
    }
  };

  const handleDetectLocation = () => {
    if ("geolocation" in navigator) {
      navigator.geolocation.getCurrentPosition(
        (pos) => {
          setLatitude(pos.coords.latitude.toFixed(4));
          setLongitude(pos.coords.longitude.toFixed(4));
          try {
            const detectedTz = Intl.DateTimeFormat().resolvedOptions().timeZone;
            if (detectedTz) setTimezone(detectedTz);
          } catch {
            // keep current timezone
          }
        },
        () => {
          setError(t("prayer.locationError"));
        },
      );
    }
  };

  const handleCalculate = async () => {
    if (!selectedMethodId) return;
    setLoading(true);
    setError(null);

    const activeMethod = methods.find((m) => m.id === selectedMethodId);

    try {
      const calc = await api.calculatePrayer({
        date,
        timezone,
        location: {
          latitude: Number(latitude),
          longitude: Number(longitude),
        },
        method_config_id: selectedMethodId,
        method_checksum_sha256: activeMethod?.checksum_sha256,
        asr_method: asrMethod,
        high_latitude_rule: highLatitudeRule,
        polar_resolution: polarResolution,
        adjustments,
      });
      setResult(calc);
    } catch (err) {
      setError(api.normalizeError(err));
    } finally {
      setLoading(false);
    }
  };

  const handleSaveProfile = async () => {
    const activeMethod = methods.find((method) => method.id === selectedMethodId);
    if (!activeMethod) return;
    setSavingProfile(true);
    setError(null);
    setProfileMessage(null);
    try {
      if (!isLoggedIn) {
        const guest = await loginGuest();
        if (!guest) return;
      }
      const profile = await api.savePrayerProfile({
        base_revision: profileRevision,
        method_config_id: activeMethod.id,
        method_checksum_sha256: activeMethod.checksum_sha256,
        asr_method: asrMethod,
        high_latitude_rule: highLatitudeRule,
        polar_resolution: polarResolution,
        adjustments,
        timezone_mode: profileTimezoneMode,
        ...(profileTimezoneMode === "fixed" ? { fixed_timezone: fixedTimezone } : {}),
      });
      setProfileRevision(profile.revision);
      setProfileMessage(t("prayer.profileSaved", { revision: profile.revision }));
    } catch (err) {
      setError(api.normalizeError(err));
    } finally {
      setSavingProfile(false);
    }
  };

  // Calculate automatically when the selected method becomes available.
  useEffect(() => {
    if (selectedMethodId) {
      void handleCalculate();
    }
    // Recalculate here only when the method changes; the form submit handles other edits.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedMethodId]);

  const formatPrayerTime = (isoString?: string) => {
    if (!isoString) return "--:--";
    try {
      return formatDate(isoString, { hour: "2-digit", minute: "2-digit", timeZone: "UTC" });
    } catch {
      return "--:--";
    }
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 20 }}>
      {/* Header Form */}
      <section className="surface">
        <div className="surface-head">
          <div>
            <p className="eyebrow">{t("prayer.eyebrow")}</p>
            <h1 className="surface-title">{t("prayer.title")}</h1>
            <p className="surface-subtitle">{t("prayer.description")}</p>
          </div>

          <button
            className="btn btn-outline-primary"
            onClick={handleDetectLocation}
            type="button"
          >
            {t("prayer.myLocation")}
          </button>
        </div>

        {error && <div className="alert alert-error" style={{ marginBottom: 16 }}>{error}</div>}

        <form
          onSubmit={(e) => {
            e.preventDefault();
            void handleCalculate();
          }}
          style={{ display: "flex", flexDirection: "column", gap: 16 }}
        >
          <div className="form-row">
            <div className="form-group">
              <label className="form-label">{t("prayer.quickCity")}</label>
              <select onChange={(e) => handleCitySelect(Number(e.target.value))}>
                {PRESET_CITIES.map((city, idx) => (
                  <option key={city.label} value={idx}>
                    {t(city.label)}
                  </option>
                ))}
              </select>
            </div>

            <div className="form-group">
              <label className="form-label">{t("prayer.method")}</label>
              <select
                value={selectedMethodId}
                onChange={(e) => setSelectedMethodId(e.target.value)}
                disabled={methods.length === 0}
              >
                {methods.map((m) => (
                  <option key={m.id} value={m.id}>
                    {(locale === "ar" ? m.name.ar : locale === "ru" ? m.name.ru : m.name.en) || m.code} ({m.code})
                  </option>
                ))}
              </select>
            </div>

            <div className="form-group">
              <label className="form-label">{t("prayer.date")}</label>
              <input
                type="date"
                value={date}
                onChange={(e) => setDate(e.target.value)}
              />
            </div>
          </div>

          <div className="form-row">
            <div className="form-group">
              <label className="form-label">{t("prayer.latitude")}</label>
              <input
                type="text"
                value={latitude}
                onChange={(e) => setLatitude(e.target.value)}
              />
            </div>

            <div className="form-group">
              <label className="form-label">{t("prayer.longitude")}</label>
              <input
                type="text"
                value={longitude}
                onChange={(e) => setLongitude(e.target.value)}
              />
            </div>

            <div className="form-group">
              <label className="form-label">{t("prayer.timezone")}</label>
              <input
                type="text"
                value={timezone}
                onChange={(e) => setTimezone(e.target.value)}
              />
            </div>

            <div className="form-group">
              <label className="form-label">{t("prayer.asrSchool")}</label>
              <select
                value={asrMethod}
                onChange={(e) => setAsrMethod(e.target.value as "standard" | "hanafi")}
              >
                <option value="standard">{t("prayer.standardSchool")}</option>
                <option value="hanafi">{t("prayer.hanafiSchool")}</option>
              </select>
            </div>
          </div>

          <details
            open
            style={{
              padding: 14,
              border: "1px solid var(--border)",
              borderRadius: "var(--radius-md)",
              background: "var(--bg-subtle)",
            }}
          >
            <summary style={{ cursor: "pointer", fontWeight: 700 }}>
              {t("prayer.profileSettings")}
            </summary>
            <div style={{ display: "flex", flexDirection: "column", gap: 14, marginTop: 14 }}>
              {profileMessage && <div className="alert alert-info">{profileMessage}</div>}
              <div className="form-row">
                <div className="form-group">
                  <label className="form-label" htmlFor="high-latitude-rule">
                    {t("prayer.highLatitude")}
                  </label>
                  <select
                    id="high-latitude-rule"
                    value={highLatitudeRule}
                    onChange={(event) =>
                      setHighLatitudeRule(
                        event.target.value as PrayerProfile["high_latitude_rule"],
                      )
                    }
                  >
                    <option value="middle_of_night">{t("prayer.middleNight")}</option>
                    <option value="seventh_of_night">{t("prayer.seventhNight")}</option>
                    <option value="twilight_angle">{t("prayer.twilightAngle")}</option>
                  </select>
                </div>
                <div className="form-group">
                  <label className="form-label" htmlFor="polar-resolution">
                    {t("prayer.polar")}
                  </label>
                  <select
                    id="polar-resolution"
                    value={polarResolution}
                    onChange={(event) =>
                      setPolarResolution(
                        event.target.value as PrayerProfile["polar_resolution"],
                      )
                    }
                  >
                    <option value="unresolved">{t("prayer.unresolved")}</option>
                    <option value="aqrab_balad">{t("prayer.nearestLatitude")}</option>
                    <option value="aqrab_yaum">{t("prayer.nearestDay")}</option>
                  </select>
                </div>
                <div className="form-group">
                  <label className="form-label" htmlFor="profile-timezone-mode">
                    {t("prayer.profileTimezone")}
                  </label>
                  <select
                    id="profile-timezone-mode"
                    value={profileTimezoneMode}
                    onChange={(event) =>
                      setProfileTimezoneMode(
                        event.target.value as PrayerProfile["timezone_mode"],
                      )
                    }
                  >
                    <option value="device_local">{t("prayer.deviceTimezone")}</option>
                    <option value="fixed">{t("prayer.fixedTimezoneMode")}</option>
                  </select>
                </div>
                {profileTimezoneMode === "fixed" && (
                  <div className="form-group">
                    <label className="form-label" htmlFor="profile-fixed-timezone">
                      {t("prayer.fixedTimezone")}
                    </label>
                    <input
                      id="profile-fixed-timezone"
                      value={fixedTimezone}
                      onChange={(event) => setFixedTimezone(event.target.value)}
                      placeholder="Europe/Istanbul"
                    />
                  </div>
                )}
              </div>

              <div>
                <p className="form-label" style={{ marginBottom: 8 }}>
                  {t("prayer.adjustments")}
                </p>
                <div className="form-row">
                  {ADJUSTMENT_LABELS.map(([key, label]) => (
                    <div className="form-group" key={key}>
                      <label className="form-label" htmlFor={`adjustment-${key}`}>
                        {t(label)}
                      </label>
                      <input
                        id={`adjustment-${key}`}
                        type="number"
                        min={-120}
                        max={120}
                        value={adjustments[key]}
                        onChange={(event) =>
                          setAdjustments({
                            ...adjustments,
                            [key]: Number(event.target.value),
                          })
                        }
                      />
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </details>

          <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
            <button type="submit" className="btn btn-primary" disabled={loading}>
              {loading ? t("prayer.calculating") : t("prayer.calculate")}
            </button>
            <button
              type="button"
              className="btn btn-secondary"
              disabled={savingProfile || !selectedMethodId}
              onClick={() => void handleSaveProfile()}
            >
              {savingProfile ? t("common.saving") : t("prayer.saveProfile")}
            </button>
          </div>
        </form>
      </section>

      {/* Calculated Results */}
      {result && (result.times || result.prayer_times) && (() => {
        const pTimes = result.times || result.prayer_times;
        return (
          <section className="surface">
            <div className="surface-head">
              <div>
                <p className="eyebrow">{t("prayer.results", { date: result.date })}</p>
                <h3 className="surface-title">
                  {(locale === "ar" ? result.method?.name?.ar : locale === "ru" ? result.method?.name?.ru : result.method?.name?.en) || result.method?.code || t("prayer.schedule")}
                </h3>
              </div>
              <span className="status-chip ok">{t("prayer.timezoneValue", { timezone: result.timezone })}</span>
            </div>

            <div className="prayer-grid">
              <div className="prayer-time-card">
                <span className="prayer-name-ar">الفجر</span>
                <span className="prayer-name-ru">{t("prayer.fajrFull")}</span>
                <span className="prayer-time">{formatPrayerTime(pTimes?.fajr?.local)}</span>
                <span className="kpi-desc">{t("prayer.fajrStart")}</span>
              </div>

              <div className="prayer-time-card">
                <span className="prayer-name-ar">الشروق</span>
                <span className="prayer-name-ru">{t("prayer.sunriseFull")}</span>
                <span className="prayer-time">{formatPrayerTime(pTimes?.sunrise?.local)}</span>
                <span className="kpi-desc">{t("prayer.fajrEnd")}</span>
              </div>

              <div className="prayer-time-card">
                <span className="prayer-name-ar">الظهر</span>
                <span className="prayer-name-ru">{t("prayer.dhuhrFull")}</span>
                <span className="prayer-time">{formatPrayerTime(pTimes?.dhuhr?.local)}</span>
                <span className="kpi-desc">{t("prayer.afterZenith")}</span>
              </div>

              <div className="prayer-time-card">
                <span className="prayer-name-ar">العصر</span>
                <span className="prayer-name-ru">{t("prayer.asrFull")}</span>
                <span className="prayer-time">{formatPrayerTime(pTimes?.asr?.local)}</span>
                <span className="kpi-desc">{asrMethod === "hanafi" ? t("prayer.hanafi") : t("prayer.standard")}</span>
              </div>

              <div className="prayer-time-card">
                <span className="prayer-name-ar">المغرب</span>
                <span className="prayer-name-ru">{t("prayer.maghribFull")}</span>
                <span className="prayer-time">{formatPrayerTime(pTimes?.maghrib?.local)}</span>
                <span className="kpi-desc">{t("prayer.sunsetIftar")}</span>
              </div>

              <div className="prayer-time-card">
                <span className="prayer-name-ar">العشاء</span>
                <span className="prayer-name-ru">{t("prayer.ishaFull")}</span>
                <span className="prayer-time">{formatPrayerTime(pTimes?.isha?.local)}</span>
                <span className="kpi-desc">{t("prayer.nightfall")}</span>
              </div>
            </div>
          </section>
        );
      })()}
    </div>
  );
}
