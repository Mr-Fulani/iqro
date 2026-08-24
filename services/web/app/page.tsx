"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { ReciterAvatar } from "../components/ReciterAvatar";
import { api, PrayerCalculationResponse, QuranEdition, Reciter, Surah } from "../lib/api";
import { useAuth } from "../lib/auth-context";
import { useI18n } from "../lib/i18n-context";
import { localizedPath } from "../lib/routing";
import { quranEditionPath, quranSurahPath } from "../lib/quran-content";

const RECITER_PORTRAITS: Record<string, string> = {
  "qf-159-maher-al-muaiqly": "/reciters/maher-al-muaiqly.webp",
  "qf-7-mishari-rashid-al-afasy": "/reciters/mishari-rashid-al-afasy.webp",
  "qf-174-yasser-ad-dussary": "/reciters/yasser-ad-dussary.webp",
};

export default function HomePage() {
  const { session, isLoggedIn, loginGuest, isLoading: authLoading } = useAuth();
  const { locale, t, formatDate } = useI18n();
  const isActiveAccount = session?.user.status === "active";

  const [editions, setEditions] = useState<QuranEdition[]>([]);
  const [featuredSurahs, setFeaturedSurahs] = useState<Surah[]>([]);
  const [featuredReciters, setFeaturedReciters] = useState<Reciter[]>([]);
  const [recitersLoading, setRecitersLoading] = useState(true);
  const [todayPrayer, setTodayPrayer] = useState<PrayerCalculationResponse | null>(null);

  useEffect(() => {
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

    api
      .getReciters()
      .then((res) => setFeaturedReciters((res.results || []).slice(0, 6)))
      .catch(() => setFeaturedReciters([]))
      .finally(() => setRecitersLoading(false));

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
  const reciterName = (reciter: Reciter) =>
    locale === "ar" ? reciter.name_ar : locale === "ru" ? reciter.name_ru : reciter.name_en;
  const reciterSecondaryName = (reciter: Reciter) => {
    const primary = reciterName(reciter);
    const secondary = locale === "ar" ? reciter.name_en : reciter.name_ar;
    return secondary && secondary !== primary ? secondary : t("home.reciterSubtitle");
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 24 }}>
      {/* Hero Banner */}
      <section className="hero-card">
        <div className="hero-content">
          <p className="eyebrow" style={{ color: "#a7f3d0" }}>
            {t("home.eyebrow")}
          </p>
          <h1>{t("home.title")}</h1>
          <p>{t("home.description")}</p>
        </div>

        <div className="hero-actions">
          <Link href={localizedPath(locale, "/quran")} className="btn btn-primary btn-lg" style={{ background: "#ffffff", color: "#065f46" }}>
            {t("home.readQuran")}
          </Link>
          <Link href={localizedPath(locale, "/prayer")} className="btn btn-outline-primary btn-lg" style={{ borderColor: "#a7f3d0", color: "#ffffff" }}>
            {t("home.prayerTimes")}
          </Link>
        </div>
      </section>

      {/* Reader and Quran catalog summary */}
      <section className="kpi-grid">
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
              <Link href={localizedPath(locale, "/login")} className="btn btn-primary">
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

      {/* Featured Reciters */}
      <section className="surface reciter-showcase" data-testid="featured-reciters">
        <div className="surface-head">
          <div>
            <p className="eyebrow">{t("home.recitersEyebrow")}</p>
            <h3 className="surface-title">{t("home.recitersTitle")}</h3>
            <p className="surface-subtitle">{t("home.recitersDescription")}</p>
          </div>
          <Link href={localizedPath(locale, "/audio")} className="btn btn-outline-primary btn-sm">
            {t("home.allReciters")}
          </Link>
        </div>

        {featuredReciters.length > 0 ? (
          <div className="reciter-grid">
            {featuredReciters.map((reciter, index) => {
              const name = reciterName(reciter);
              return (
                <Link
                  key={reciter.id}
                  href={localizedPath(locale, `/audio?reciter=${encodeURIComponent(reciter.id)}`)}
                  className="reciter-card"
                  aria-label={t("home.listenReciter", { name })}
                  data-testid="featured-reciter"
                >
                  <ReciterAvatar
                    name={name || reciter.name_en}
                    portraitUrl={reciter.portrait_url || RECITER_PORTRAITS[reciter.slug]}
                    tone={index}
                  />
                  <span className="reciter-card-copy">
                    <strong>{name || reciter.name_en}</strong>
                    <span lang={locale === "ar" ? "en" : "ar"} dir={locale === "ar" ? "ltr" : "rtl"}>
                      {reciterSecondaryName(reciter)}
                    </span>
                  </span>
                </Link>
              );
            })}
          </div>
        ) : (
          <div className="reciter-empty" aria-live="polite">
            {recitersLoading ? t("home.loadingReciters") : t("home.recitersEmpty")}
          </div>
        )}
      </section>

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
              <Link href={localizedPath(locale, "/prayer")} className="btn btn-secondary btn-sm">
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
          <Link
            href={localizedPath(
              locale,
              editions[0] ? quranEditionPath(editions[0].code) : "/quran",
            )}
            className="btn btn-outline-primary btn-sm"
          >
            {t("home.allSurahs")}
          </Link>
        </div>

        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(280px, 1fr))", gap: 14 }}>
          {featuredSurahs.length > 0 ? (
            featuredSurahs.map((surah) => (
              <Link
                key={surah.id}
                href={localizedPath(
                  locale,
                  quranSurahPath(editions[0]?.code || "madani-hafs", surah.number),
                )}
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
