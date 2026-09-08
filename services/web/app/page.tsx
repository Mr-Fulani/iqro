"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { ReciterAvatar } from "../components/ReciterAvatar";
import { TodayReadingCard } from "../components/TodayReadingCard";
import { PrayerReadingPlanCard } from "../components/PrayerReadingPlanCard";
import { MemorizationPlannerCard } from "../components/MemorizationPlannerCard";
import { api, PrayerCalculationResponse, QuranEdition, Reciter, Surah } from "../lib/api";
import { useAuth } from "../lib/auth-context";
import { useI18n } from "../lib/i18n-context";
import { selectHomePopularReciters } from "../lib/reciter-catalog";
import { reciterName as localizedReciterName } from "../lib/audio-content";
import { reciterPortraitUrl } from "../lib/reciter-portraits";
import { rememberReciterPreference } from "../lib/reciter-preference";
import { localizedPath } from "../lib/routing";
import { quranEditionPath, quranSurahPath } from "../lib/quran-content";
import {
  dateInTimezone,
  DEFAULT_PRAYER_LOCATION,
  loadPrayerLocationPreference,
} from "../lib/prayer-location";

const HERO_SLIDES = [
  { src: "/images/home/hero-kaaba.webp", label: "home.heroKaaba" as const },
  {
    src: "/images/home/hero-prophets-mosque.webp",
    label: "home.heroProphetsMosque" as const,
  },
  { src: "/images/home/hero-quba-mosque.webp", label: "home.heroQubaMosque" as const },
];

export default function HomePage() {
  const { session, isLoggedIn, isLoading: authLoading } = useAuth();
  const { locale, t, formatDate } = useI18n();
  const isActiveAccount = session?.user.status === "active";
  const sessionUserId = session?.user.id;

  const [editions, setEditions] = useState<QuranEdition[]>([]);
  const [featuredSurahs, setFeaturedSurahs] = useState<Surah[]>([]);
  const [featuredReciters, setFeaturedReciters] = useState<Reciter[]>([]);
  const [recitersLoading, setRecitersLoading] = useState(true);
  const [todayPrayer, setTodayPrayer] = useState<PrayerCalculationResponse | null>(null);
  const [heroSlide, setHeroSlide] = useState(0);
  const [heroPaused, setHeroPaused] = useState(false);

  useEffect(() => {
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    if (reducedMotion.matches || heroPaused) return;

    const intervalId = window.setInterval(() => {
      setHeroSlide((current) => (current + 1) % HERO_SLIDES.length);
    }, 7000);

    return () => window.clearInterval(intervalId);
  }, [heroPaused]);

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
      .then((res) => setFeaturedReciters(selectHomePopularReciters(res.results || [])))
      .catch(() => setFeaturedReciters([]))
      .finally(() => setRecitersLoading(false));

  }, []);

  useEffect(() => {
    if (authLoading) return;
    let active = true;

    const loadPrayerPreview = async () => {
      const manifest = await api.getPrayerMethods();
      const availableMethods = manifest.methods.filter((method) => method.available);
      const profile = sessionUserId
        ? await api.getPrayerProfile().catch(() => null)
        : null;
      const preference = loadPrayerLocationPreference(sessionUserId);
      const method =
        manifest.methods.find(
          (candidate) =>
            candidate.available && candidate.id === preference?.method_config_id,
        ) ||
        manifest.methods.find(
          (candidate) => candidate.available && candidate.id === profile?.method_config.id,
        ) ||
        availableMethods[0] ||
        manifest.methods[0];
      if (!method) return;

      const location = preference || DEFAULT_PRAYER_LOCATION;
      const timezoneName = location.timezone;
      const calc = await api.calculatePrayer({
        date: dateInTimezone(timezoneName),
        timezone: timezoneName,
        location: {
          latitude: Number(location.latitude),
          longitude: Number(location.longitude),
        },
        method_config_id: method.id,
        method_checksum_sha256: method.checksum_sha256,
        asr_method: preference?.asr_method || profile?.asr_method || "standard",
        high_latitude_rule: profile?.high_latitude_rule,
        polar_resolution: profile?.polar_resolution,
        adjustments: profile?.adjustments,
      });
      if (active) setTodayPrayer(calc);
    };

    setTodayPrayer(null);
    void loadPrayerPreview().catch(() => {});
    return () => {
      active = false;
    };
  }, [authLoading, sessionUserId]);

  const formatTime = (isoString?: string) => {
    if (!isoString) return "--:--";
    return formatDate(isoString, {
      hour: "2-digit",
      minute: "2-digit",
      timeZone: todayPrayer?.timezone || DEFAULT_PRAYER_LOCATION.timezone,
    });
  };

  const editionName = (edition: QuranEdition) =>
    locale === "ar" ? edition.name_ar : locale === "ru" ? edition.name_ru : edition.name_en;
  const surahName = (surah: Surah) =>
    locale === "ar" ? surah.name_ar : locale === "ru" ? surah.name_ru : surah.name_en;
  const reciterName = (reciter: Reciter) => localizedReciterName(reciter, locale);
  const reciterSecondaryName = (reciter: Reciter) => {
    const primary = reciterName(reciter);
    const secondary = locale === "ar" ? reciter.name_en : reciter.name_ar;
    return secondary && secondary !== primary ? secondary : t("home.reciterSubtitle");
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 24 }}>
      {/* Hero Banner */}
      <section className="hero-card" data-testid="home-hero">
        <div
          key={HERO_SLIDES[heroSlide].src}
          className="hero-media"
          data-testid="hero-media"
          style={{ backgroundImage: `url(${HERO_SLIDES[heroSlide].src})` }}
          aria-hidden="true"
        />
        <div className="hero-scrim" aria-hidden="true" />

        <div className="hero-content">
          <p className="eyebrow" style={{ color: "#a7f3d0" }}>
            {t("home.eyebrow")}
          </p>
          <h1>{t("home.title")}</h1>
          <p>{t("home.description")}</p>
          <div className="hero-actions">
            <Link href={localizedPath(locale, "/quran")} className="btn btn-primary btn-lg hero-primary-action">
              {t("home.readQuran")}
            </Link>
            <Link href={localizedPath(locale, "/audio")} className="btn btn-outline-primary btn-lg hero-secondary-action">
              {t("home.listenQuran")}
            </Link>
            <Link href={localizedPath(locale, "/dua")} className="btn btn-outline-primary btn-lg hero-secondary-action">
              {t("home.openDua")}
            </Link>
            <Link href={localizedPath(locale, "/prayer")} className="btn btn-outline-primary btn-lg hero-secondary-action">
              {t("home.prayerTimes")}
            </Link>
          </div>
        </div>

        <div className="hero-carousel" aria-label={t("home.heroCarousel")} aria-live="polite">
          <span className="hero-carousel-label">{t(HERO_SLIDES[heroSlide].label)}</span>
          <div className="hero-carousel-dots">
            {HERO_SLIDES.map((slide, index) => (
              <button
                key={slide.src}
                type="button"
                className={`hero-carousel-dot ${index === heroSlide ? "is-active" : ""}`}
                onClick={() => setHeroSlide(index)}
                aria-label={t("home.showHeroSlide", { name: t(slide.label) })}
                aria-pressed={index === heroSlide}
                data-testid={`hero-slide-${index}`}
              />
            ))}
          </div>
          <button
            type="button"
            className="hero-carousel-toggle"
            onClick={() => setHeroPaused((paused) => !paused)}
            aria-label={heroPaused ? t("home.playHeroCarousel") : t("home.pauseHeroCarousel")}
            title={heroPaused ? t("home.playHeroCarousel") : t("home.pauseHeroCarousel")}
          >
            {heroPaused ? "▶" : "Ⅱ"}
          </button>
        </div>
      </section>

      <TodayReadingCard />

      <PrayerReadingPlanCard />

      <MemorizationPlannerCard />

      <section className="surface home-planner-cta">
        <div className="surface-head">
          <div>
            <p className="eyebrow">{t("planner.eyebrow")}</p>
            <h2 className="surface-title">{t("planner.homeTitle")}</h2>
            <p className="surface-subtitle">{t("planner.homeDescription")}</p>
          </div>
          <Link href={localizedPath(locale, "/planner")} className="btn btn-primary">
            {t("planner.open")}
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
                ? t("home.deviceOnly")
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
                  onClick={() => rememberReciterPreference(reciter)}
                  aria-label={t("home.listenReciter", { name })}
                  data-testid="featured-reciter"
                >
                  <ReciterAvatar
                    name={name || reciter.name_en}
                    portraitUrl={reciterPortraitUrl(reciter)}
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
          <section className="surface" data-testid="home-prayer-schedule">
            <div className="surface-head">
              <div>
                <p className="eyebrow">{t("home.todaySchedule")}</p>
                <h3 className="surface-title">{t("home.prayers")}</h3>
              </div>
              <div style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap" }}>
                <span className="status-chip ok">
                  {t("prayer.timezoneValue", { timezone: todayPrayer.timezone })}
                </span>
                <Link href={localizedPath(locale, "/prayer")} className="btn btn-secondary btn-sm">
                  {t("home.configurePrayer")}
                </Link>
              </div>
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
