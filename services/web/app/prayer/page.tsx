"use client";

import { useEffect, useState } from "react";
import {
  api,
  PrayerCalculationResponse,
  PrayerMethod,
} from "../../lib/api";

const PRESET_CITIES = [
  { name: "Мекка (Саудовская Аравия)", lat: "21.4225", lng: "39.8262", tz: "Asia/Riyadh" },
  { name: "Медина (Саудовская Аравия)", lat: "24.4672", lng: "39.6111", tz: "Asia/Riyadh" },
  { name: "Москва (Россия)", lat: "55.7558", lng: "37.6173", tz: "Europe/Moscow" },
  { name: "Казань (Россия)", lat: "55.7887", lng: "49.1221", tz: "Europe/Moscow" },
  { name: "Ташкент (Узбекистан)", lat: "41.2995", lng: "69.2401", tz: "Asia/Tashkent" },
  { name: "Стамбул (Турция)", lat: "41.0082", lng: "28.9784", tz: "Europe/Istanbul" },
  { name: "Лондон (Великобритания)", lat: "51.5074", lng: "-0.1278", tz: "Europe/London" },
];

export default function PrayerPage() {
  const [methods, setMethods] = useState<PrayerMethod[]>([]);
  const [selectedMethodId, setSelectedMethodId] = useState<string>("");
  const [date, setDate] = useState<string>(() => new Date().toISOString().slice(0, 10));
  const [latitude, setLatitude] = useState<string>("21.4225");
  const [longitude, setLongitude] = useState<string>("39.8262");
  const [timezone, setTimezone] = useState<string>("Asia/Riyadh");
  const [asrMethod, setAsrMethod] = useState<"standard" | "hanafi">("standard");

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
          setError("Не удалось определить геопозицию автоматически. Выберите город из списка.");
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
      });
      setResult(calc);
    } catch (err) {
      setError(api.normalizeError(err));
    } finally {
      setLoading(false);
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
      const d = new Date(isoString);
      return d.toLocaleTimeString("ru-RU", { hour: "2-digit", minute: "2-digit", timeZone: "UTC" });
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
            <p className="eyebrow">Точный астрономический расчет</p>
            <h2 className="surface-title">Расписание времени намаза</h2>
            <p className="surface-subtitle">
              Расчет времени обязательных молитв по каноническим мировым методикам (Всемирная Исламская Лига, Умм аль-Кура, ISNA и др.).
            </p>
          </div>

          <button
            className="btn btn-outline-primary"
            onClick={handleDetectLocation}
            type="button"
          >
            📍 Мое местоположение
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
              <label className="form-label">Быстрый выбор города</label>
              <select onChange={(e) => handleCitySelect(Number(e.target.value))}>
                {PRESET_CITIES.map((city, idx) => (
                  <option key={city.name} value={idx}>
                    {city.name}
                  </option>
                ))}
              </select>
            </div>

            <div className="form-group">
              <label className="form-label">Метод расчета</label>
              <select
                value={selectedMethodId}
                onChange={(e) => setSelectedMethodId(e.target.value)}
                disabled={methods.length === 0}
              >
                {methods.map((m) => (
                  <option key={m.id} value={m.id}>
                    {m.name.ru || m.code} ({m.code})
                  </option>
                ))}
              </select>
            </div>

            <div className="form-group">
              <label className="form-label">Дата расчета</label>
              <input
                type="date"
                value={date}
                onChange={(e) => setDate(e.target.value)}
              />
            </div>
          </div>

          <div className="form-row">
            <div className="form-group">
              <label className="form-label">Широта (Latitude)</label>
              <input
                type="text"
                value={latitude}
                onChange={(e) => setLatitude(e.target.value)}
              />
            </div>

            <div className="form-group">
              <label className="form-label">Долгота (Longitude)</label>
              <input
                type="text"
                value={longitude}
                onChange={(e) => setLongitude(e.target.value)}
              />
            </div>

            <div className="form-group">
              <label className="form-label">Часовой пояс (IANA)</label>
              <input
                type="text"
                value={timezone}
                onChange={(e) => setTimezone(e.target.value)}
              />
            </div>

            <div className="form-group">
              <label className="form-label">Мазхаб для времени Аср</label>
              <select
                value={asrMethod}
                onChange={(e) => setAsrMethod(e.target.value as "standard" | "hanafi")}
              >
                <option value="standard">Стандартный (Шафии, Малики, Ханбали)</option>
                <option value="hanafi">Ханафитский (тень x2)</option>
              </select>
            </div>
          </div>

          <div>
            <button type="submit" className="btn btn-primary" disabled={loading}>
              {loading ? "Рассчитываем..." : "Рассчитать расписание"}
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
                <p className="eyebrow">Результаты расчета на {result.date}</p>
                <h3 className="surface-title">
                  {result.method?.name?.ru || result.method?.code || "Расписание намаза"}
                </h3>
              </div>
              <span className="status-chip ok">Часовой пояс: {result.timezone}</span>
            </div>

            <div className="prayer-grid">
              <div className="prayer-time-card">
                <span className="prayer-name-ar">الفجر</span>
                <span className="prayer-name-ru">Фаджр (Утренний)</span>
                <span className="prayer-time">{formatPrayerTime(pTimes?.fajr?.local)}</span>
                <span className="kpi-desc">Начало рассвета</span>
              </div>

              <div className="prayer-time-card">
                <span className="prayer-name-ar">الشروق</span>
                <span className="prayer-name-ru">Восход солнца</span>
                <span className="prayer-time">{formatPrayerTime(pTimes?.sunrise?.local)}</span>
                <span className="kpi-desc">Конец Фаджра</span>
              </div>

              <div className="prayer-time-card">
                <span className="prayer-name-ar">الظهر</span>
                <span className="prayer-name-ru">Зухр (Полуденный)</span>
                <span className="prayer-time">{formatPrayerTime(pTimes?.dhuhr?.local)}</span>
                <span className="kpi-desc">После зенита</span>
              </div>

              <div className="prayer-time-card">
                <span className="prayer-name-ar">العصر</span>
                <span className="prayer-name-ru">Аср (Послеполуденный)</span>
                <span className="prayer-time">{formatPrayerTime(pTimes?.asr?.local)}</span>
                <span className="kpi-desc">{asrMethod === "hanafi" ? "Ханафи" : "Стандарт"}</span>
              </div>

              <div className="prayer-time-card">
                <span className="prayer-name-ar">المغرب</span>
                <span className="prayer-name-ru">Магриб (Вечерний)</span>
                <span className="prayer-time">{formatPrayerTime(pTimes?.maghrib?.local)}</span>
                <span className="kpi-desc">Заход солнца / Ифтар</span>
              </div>

              <div className="prayer-time-card">
                <span className="prayer-name-ar">العشاء</span>
                <span className="prayer-name-ru">Иша (Ночной)</span>
                <span className="prayer-time">{formatPrayerTime(pTimes?.isha?.local)}</span>
                <span className="kpi-desc">Наступление ночи</span>
              </div>
            </div>
          </section>
        );
      })()}
    </div>
  );
}
