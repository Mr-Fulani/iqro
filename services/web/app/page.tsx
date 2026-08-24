"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { api, PrayerCalculationResponse, QuranEdition, Surah } from "../lib/api";
import { useAuth } from "../lib/auth-context";
import { useI18n } from "../lib/i18n-context";

export default function HomePage() {
  const { session, isLoggedIn, loginGuest, isLoading: authLoading } = useAuth();
  const { locale, t, formatDate } = useI18n();
  const isActiveAccount = session?.user.status === "active";

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
    return formatDate(isoString, { hour: "2-digit", minute: "2-digit", timeZone: "UTC" });
  };

  const editionName = (edition: QuranEdition) =>
    locale === "ar" ? edition.name_ar : locale === "ru" ? edition.name_ru : edition.name_en;
  const surahName = (surah: Surah) =>
    locale === "ar" ? surah.name_ar : locale === "ru" ? surah.name_ru : surah.name_en;

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 24 }}>
      {/* Hero Banner */}
      <section className="hero-card">
        <div className="hero-content">
          <p className="eyebrow" style={{ color: "#a7f3d0" }}>
            {t("home.eyebrow")}
          </p>
          <h2>{t("home.title")}</h2>
          <p>{t("home.description")}</p>
        </div>

        <div className="hero-actions">
          <Link href="/quran" className="btn btn-primary btn-lg" style={{ background: "#ffffff", color: "#065f46" }}>
            {t("home.readQuran")}
          </Link>
          <Link href="/prayer" className="btn btn-outline-primary btn-lg" style={{ borderColor: "#a7f3d0", color: "#ffffff" }}>
            {t("home.prayerTimes")}
          </Link>
        </div>
      </section>

      {/* Backend Health & Connection Status */}
      <section className="kpi-grid">
        <article className="kpi-card">
          <div className="kpi-header">
            <span className="kpi-label">{t("home.backendApi")} (Liveness)</span>
            <span className="kpi-icon">{liveStatus.ok ? "🟢" : liveStatus.loading ? "⏳" : "🔴"}</span>
          </div>
          <div className="kpi-value">
            {liveStatus.loading ? t("common.checking") : liveStatus.ok ? t("home.connected") : t("home.disconnected")}
          </div>
          <div className="kpi-desc">
            {liveStatus.ok ? t("home.liveOk") : liveStatus.error || t("home.waitingBackend")}
          </div>
        </article>

        <article className="kpi-card">
          <div className="kpi-header">
            <span className="kpi-label">{t("home.servicesReady")} (Readiness)</span>
            <span className="kpi-icon">{readyStatus.ok ? "🟢" : readyStatus.loading ? "⏳" : "🔴"}</span>
          </div>
          <div className="kpi-value">
            {readyStatus.loading ? t("common.checking") : readyStatus.ok ? t("home.ready") : t("home.unavailable")}
          </div>
          <div className="kpi-desc">
            {readyStatus.ok ? t("home.readyOk") : t("home.checkingDependencies")}
          </div>
        </article>

        <article className="kpi-card">
          <div className="kpi-header">
            <span className="kpi-label">{t("home.userMode")}</span>
            <span className="kpi-icon">{isActiveAccount ? "👤" : "🛡️"}</span>
          </div>
          <div className="kpi-value">
            {isActiveAccount ? t("home.verifiedAccount") : t("auth.guest")}
          </div>
          <div className="kpi-desc">
            {isActiveAccount
              ? session.user.email
              : isLoggedIn && session
                ? t("home.deviceOnly", { id: session.user.id.slice(0, 8) })
                : t("home.readWithoutRegistration")}
          </div>
        </article>

        <article className="kpi-card">
          <div className="kpi-header">
            <span className="kpi-label">{t("home.quranCatalog")}</span>
            <span className="kpi-icon">📚</span>
          </div>
          <div className="kpi-value">{editions.length > 0 ? t("home.editions", { count: editions.length }) : t("home.madaniHafs")}</div>
          <div className="kpi-desc">
            {editions.length > 0 ? editions.map(editionName).join(", ") : t("home.catalogFallback")}
          </div>
        </article>
      </section>

      {/* Account upgrade banner */}
      {!isActiveAccount && (
        <section className="surface" style={{ background: "linear-gradient(135deg, #f0fdf4 0%, #ffffff 100%)" }}>
          <div className="surface-head">
            <div>
              <h3 className="surface-title">{t("home.upgradeTitle")}</h3>
              <p className="surface-subtitle">{t("home.upgradeDescription")}</p>
            </div>
            <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
              <Link href="/login" className="btn btn-primary">
                {t("auth.emailLogin")}
              </Link>
              {!isLoggedIn && (
                <button
                  onClick={() => void loginGuest()}
                  className="btn btn-secondary"
                  disabled={authLoading}
                >
                  {authLoading ? t("home.preparing") : t("home.continueGuest")}
                </button>
              )}
            </div>
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
                <p className="eyebrow">{t("home.todaySchedule")}</p>
                <h3 className="surface-title">{t("home.prayers")}</h3>
              </div>
              <Link href="/prayer" className="btn btn-secondary btn-sm">
                {t("home.configurePrayer")}
              </Link>
            </div>

            <div className="prayer-grid">
              <div className="prayer-time-card">
                <span className="prayer-name-ar">الفجر</span>
                <span className="prayer-name-ru">{t("prayer.fajr")}</span>
                <span className="prayer-time">{formatTime(pTimes?.fajr?.local)}</span>
              </div>
              <div className="prayer-time-card">
                <span className="prayer-name-ar">الشروق</span>
                <span className="prayer-name-ru">{t("prayer.sunrise")}</span>
                <span className="prayer-time">{formatTime(pTimes?.sunrise?.local)}</span>
              </div>
              <div className="prayer-time-card">
                <span className="prayer-name-ar">الظهر</span>
                <span className="prayer-name-ru">{t("prayer.dhuhr")}</span>
                <span className="prayer-time">{formatTime(pTimes?.dhuhr?.local)}</span>
              </div>
              <div className="prayer-time-card">
                <span className="prayer-name-ar">العصر</span>
                <span className="prayer-name-ru">{t("prayer.asr")}</span>
                <span className="prayer-time">{formatTime(pTimes?.asr?.local)}</span>
              </div>
              <div className="prayer-time-card">
                <span className="prayer-name-ar">المغرب</span>
                <span className="prayer-name-ru">{t("prayer.maghrib")}</span>
                <span className="prayer-time">{formatTime(pTimes?.maghrib?.local)}</span>
              </div>
              <div className="prayer-time-card">
                <span className="prayer-name-ar">العشاء</span>
                <span className="prayer-name-ru">{t("prayer.isha")}</span>
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
            <p className="eyebrow">{t("home.surahCatalog")}</p>
            <h3 className="surface-title">{t("home.surahTitle")}</h3>
          </div>
          <Link href="/quran" className="btn btn-outline-primary btn-sm">
            {t("home.allSurahs")}
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
                    <strong>{surahName(surah)}</strong>
                    <p className="kpi-desc">
                      {t("home.ayahCount", { count: surah.ayah_count })} · {surah.revelation_type === "meccan" ? t("home.meccan") : t("home.medinan")}
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
              {t("home.loadingSurahs")}
            </div>
          )}
        </div>
      </section>
    </div>
  );
}
