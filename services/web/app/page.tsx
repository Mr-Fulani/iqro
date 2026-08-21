"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { api, PrayerCalculationResponse, QuranEdition, Surah } from "../lib/api";
import { useAuth } from "../lib/auth-context";

export default function HomePage() {
  const { session, isLoggedIn, loginGuest, isLoading: authLoading } = useAuth();

  const [liveStatus, setLiveStatus] = useState<{ loading: boolean; ok?: boolean; error?: string }>({
    loading: true,
  });
  const [readyStatus, setReadyStatus] = useState<{ loading: boolean; ok?: boolean; error?: string }>({
    loading: true,
  });

  const [editions, setEditions] = useState<QuranEdition[]>([]);
  const [featuredSurahs, setFeaturedSurahs] = useState<Surah[]>([]);
  const [todayPrayer, setTodayPrayer] = useState<PrayerCalculationResponse | null>(null);

  useEffect(() => {
    // Check backend health
    api
      .getHealthLive()
      .then((res) => setLiveStatus({ loading: false, ok: res.status === "ok" }))
      .catch((err) => setLiveStatus({ loading: false, ok: false, error: api.normalizeError(err) }));

    api
      .getHealthReady()
      .then((res) => setReadyStatus({ loading: false, ok: res.status === "ok" }))
      .catch((err) => setReadyStatus({ loading: false, ok: false, error: api.normalizeError(err) }));

    // Load initial Quran editions
    api
      .getEditions()
      .then(async (res) => {
        setEditions(res);
        if (res.length > 0) {
          const surahs = await api.getSurahs(res[0].code);
          setFeaturedSurahs(surahs.slice(0, 6));
        }
      })
      .catch(() => {});

    // Load prayer times preview for today
    api
      .getPrayerMethods()
      .then(async (manifest) => {
        const defaultMethod = manifest.methods.find((m) => m.available) || manifest.methods[0];
        if (defaultMethod) {
          const today = new Date().toISOString().slice(0, 10);
          const calc = await api.calculatePrayer({
            date: today,
            timezone: "UTC",
            location: { latitude: "21.4225", longitude: "39.8262" }, // Makkah default
            method_config_id: defaultMethod.id,
            method_checksum_sha256: defaultMethod.checksum_sha256,
          });
          setTodayPrayer(calc);
        }
      })
      .catch(() => {});
  }, []);

  const formatTime = (isoString?: string) => {
    if (!isoString) return "--:--";
    const date = new Date(isoString);
    return date.toLocaleTimeString("ru-RU", { hour: "2-digit", minute: "2-digit", timeZone: "UTC" });
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 24 }}>
      {/* Hero Banner */}
      <section className="hero-card">
        <div className="hero-content">
          <p className="eyebrow" style={{ color: "#a7f3d0" }}>
            Мадинский Мусхаф Хафс · 604 страницы
          </p>
          <h2>Единая исламская платформа для чтения, прослушивания и планирования</h2>
          <p>
            Читайте текст Священного Корана с точной постраничной версткой, слушайте признанных
            чтецов, рассчитывайте времена намаза для любой точки мира и синхронизируйте свои закладки.
          </p>
        </div>

        <div className="hero-actions">
          <Link href="/quran" className="btn btn-primary btn-lg" style={{ background: "#ffffff", color: "#065f46" }}>
            📖 Читать Коран
          </Link>
          <Link href="/prayer" className="btn btn-outline-primary btn-lg" style={{ borderColor: "#a7f3d0", color: "#ffffff" }}>
            🕌 Время намаза
          </Link>
        </div>
      </section>

      {/* Backend Health & Connection Status */}
      <section className="kpi-grid">
        <article className="kpi-card">
          <div className="kpi-header">
            <span className="kpi-label">API Бэкенда (Liveness)</span>
            <span className="kpi-icon">{liveStatus.ok ? "🟢" : liveStatus.loading ? "⏳" : "🔴"}</span>
          </div>
          <div className="kpi-value">
            {liveStatus.loading ? "Проверка..." : liveStatus.ok ? "Подключено" : "Нет связи"}
          </div>
          <div className="kpi-desc">
            {liveStatus.ok ? "Django ASGI сервис активен (/health/live)" : liveStatus.error || "Ожидание запуска"}
          </div>
        </article>

        <article className="kpi-card">
          <div className="kpi-header">
            <span className="kpi-label">Готовность служб (Readiness)</span>
            <span className="kpi-icon">{readyStatus.ok ? "🟢" : readyStatus.loading ? "⏳" : "🔴"}</span>
          </div>
          <div className="kpi-value">
            {readyStatus.loading ? "Проверка..." : readyStatus.ok ? "Готов к работе" : "Недоступно"}
          </div>
          <div className="kpi-desc">
            {readyStatus.ok ? "БД PostgreSQL и Redis в норме (/health/ready)" : "Проверка зависимостей..."}
          </div>
        </article>

        <article className="kpi-card">
          <div className="kpi-header">
            <span className="kpi-label">Режим пользователя</span>
            <span className="kpi-icon">{isLoggedIn ? "👤" : "🛡️"}</span>
          </div>
          <div className="kpi-value">{isLoggedIn ? "Личный профиль" : "Гостевой режим"}</div>
          <div className="kpi-desc">
            {isLoggedIn && session
              ? `ID: ${session.user.id.slice(0, 8)}... (${session.device.platform})`
              : "Нажмите 'Войти как гость' для сохранения прогресса"}
          </div>
        </article>

        <article className="kpi-card">
          <div className="kpi-header">
            <span className="kpi-label">Каталог Корана</span>
            <span className="kpi-icon">📚</span>
          </div>
          <div className="kpi-value">{editions.length > 0 ? `${editions.length} изд.` : "Мадинский Хафс"}</div>
          <div className="kpi-desc">
            {editions.length > 0 ? editions.map((e) => e.name_ru).join(", ") : "604 страницы, 114 сур"}
          </div>
        </article>
      </section>

      {/* Guest Authentication Banner (if not logged in) */}
      {!isLoggedIn && (
        <section className="surface" style={{ background: "linear-gradient(135deg, #f0fdf4 0%, #ffffff 100%)" }}>
          <div className="surface-head">
            <div>
              <h3 className="surface-title">Быстрый старт без регистрации</h3>
              <p className="surface-subtitle">
                Quran Platform не требует ввода почты или пароля для начала чтения. Получите
                защищенный гостевой токен устройства в один клик.
              </p>
            </div>
            <button
              onClick={() => void loginGuest()}
              className="btn btn-primary"
              disabled={authLoading}
            >
              {authLoading ? "Авторизация..." : "Войти как гость"}
            </button>
          </div>
        </section>
      )}

      {/* Today's Prayer Times Preview */}
      {todayPrayer && (todayPrayer.times || todayPrayer.prayer_times) && (() => {
        const pTimes = todayPrayer.times || todayPrayer.prayer_times;
        return (
          <section className="surface">
            <div className="surface-head">
              <div>
                <p className="eyebrow">Расписание на сегодня (Мекка / MWL)</p>
                <h3 className="surface-title">Времена молитвы</h3>
              </div>
              <Link href="/prayer" className="btn btn-secondary btn-sm">
                Настроить город и метод →
              </Link>
            </div>

            <div className="prayer-grid">
              <div className="prayer-time-card">
                <span className="prayer-name-ar">الفجر</span>
                <span className="prayer-name-ru">Фаджр</span>
                <span className="prayer-time">{formatTime(pTimes?.fajr?.local)}</span>
              </div>
              <div className="prayer-time-card">
                <span className="prayer-name-ar">الشروق</span>
                <span className="prayer-name-ru">Восход</span>
                <span className="prayer-time">{formatTime(pTimes?.sunrise?.local)}</span>
              </div>
              <div className="prayer-time-card">
                <span className="prayer-name-ar">الظهر</span>
                <span className="prayer-name-ru">Зухр</span>
                <span className="prayer-time">{formatTime(pTimes?.dhuhr?.local)}</span>
              </div>
              <div className="prayer-time-card">
                <span className="prayer-name-ar">العصر</span>
                <span className="prayer-name-ru">Аср</span>
                <span className="prayer-time">{formatTime(pTimes?.asr?.local)}</span>
              </div>
              <div className="prayer-time-card">
                <span className="prayer-name-ar">المغرب</span>
                <span className="prayer-name-ru">Магриб</span>
                <span className="prayer-time">{formatTime(pTimes?.maghrib?.local)}</span>
              </div>
              <div className="prayer-time-card">
                <span className="prayer-name-ar">العشاء</span>
                <span className="prayer-name-ru">Иша</span>
                <span className="prayer-time">{formatTime(pTimes?.isha?.local)}</span>
              </div>
            </div>
          </section>
        );
      })()}

      {/* Featured Surahs */}
      <section className="surface">
        <div className="surface-head">
          <div>
            <p className="eyebrow">Каталог сур</p>
            <h3 className="surface-title">Суры Священного Корана</h3>
          </div>
          <Link href="/quran" className="btn btn-outline-primary btn-sm">
            Все 114 сур →
          </Link>
        </div>

        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(280px, 1fr))", gap: 14 }}>
          {featuredSurahs.length > 0 ? (
            featuredSurahs.map((surah) => (
              <Link
                key={surah.id}
                href={`/quran?surah=${surah.number}`}
                className="track-row"
                style={{ textDecoration: "none", color: "inherit" }}
              >
                <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
                  <span className="ayah-badge">{surah.number}</span>
                  <div>
                    <strong>{surah.name_ru}</strong>
                    <p className="kpi-desc">
                      {surah.ayah_count} аятов · {surah.revelation_type === "meccan" ? "Мекканская" : "Мединская"}
                    </p>
                  </div>
                </div>
                <span className="quran-arabic-text" style={{ fontSize: 20 }}>
                  {surah.name_ar}
                </span>
              </Link>
            ))
          ) : (
            <div className="kpi-desc" style={{ padding: 16 }}>
              Загрузка каталога сур...
            </div>
          )}
        </div>
      </section>
    </div>
  );
}
