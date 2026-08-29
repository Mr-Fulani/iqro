"use client";

import type { CSSProperties } from "react";
import { IconButton, ProgressBar, Screen, TopBar } from "../components";
import { reciters } from "../data";
import { Icon } from "../icons";
import { l, number } from "../i18n";
import { usePrototype } from "../store";

export function HomeScreen() {
  const { state, navigate } = usePrototype();
  const locale = state.locale;
  const progress = Math.round((state.dailyAchieved / state.dailyTarget) * 100);
  const prayerTotal = Object.values(state.prayerPages).reduce((sum, value) => sum + value, 0);
  const reciter = reciters.find((item) => item.id === state.selectedReciter) || reciters[0];
  return (
    <Screen className="home-screen">
      <TopBar
        title={l(locale, { ru: "Ас-саляму алейкум", en: "Assalamu alaikum", ar: "السلام عليكم", tr: "Selamün aleyküm" })}
        subtitle={l(locale, { ru: "Воскресенье, 30 августа", en: "Sunday, 30 August", ar: "الأحد، ٣٠ أغسطس", tr: "Pazar, 30 Ağustos" })}
        action={<IconButton label="Settings" onClick={() => navigate("settings")}><Icon name="settings" /></IconButton>}
      />

      <section className="continue-card">
        <div className="continue-orbit" aria-hidden="true" />
        <span className="eyebrow light">{l(locale, { ru: "Продолжить чтение", en: "Continue reading", ar: "متابعة القراءة", tr: "Okumaya devam et" })}</span>
        <h1>{locale === "ar" ? "الفاتحة" : locale === "ru" ? "Аль-Фатиха" : locale === "tr" ? "Fâtiha" : "Al-Faatiha"}</h1>
        <p>{l(locale, { ru: `Аят ${state.lastPosition.ayah} · Страница ${state.lastPosition.page}`, en: `Ayah ${state.lastPosition.ayah} · Page ${state.lastPosition.page}`, ar: `الآية ${number(locale, state.lastPosition.ayah)} · الصفحة ${number(locale, state.lastPosition.page)}`, tr: `Ayet ${state.lastPosition.ayah} · Sayfa ${state.lastPosition.page}` })}</p>
        <button className="button inverse" onClick={() => navigate(state.readerMode === "text" ? "reader" : "mushaf")}>
          <Icon name="book" /> {l(locale, { ru: "Читать", en: "Read", ar: "اقرأ", tr: "Oku" })}
        </button>
        <div className="continue-meta"><Icon name="refresh" size={16} /> {l(locale, { ru: "Место сохранено автоматически", en: "Position saved automatically", ar: "تم حفظ موضعك تلقائيًا", tr: "Konum otomatik kaydedildi" })}</div>
      </section>

      <section className="next-prayer-strip" onClick={() => navigate("prayer")}>
        <span className="prayer-symbol"><Icon name="arch" /></span>
        <span><small>{l(locale, { ru: "Следующая молитва", en: "Next prayer", ar: "الصلاة التالية", tr: "Sonraki namaz" })}</small><strong>{l(locale, { ru: "Магриб", en: "Maghrib", ar: "المغرب", tr: "Akşam" })}</strong></span>
        <span className="prayer-countdown"><strong>19:42</strong><small>{l(locale, { ru: "через 1 ч 18 мин", en: "in 1h 18m", ar: "بعد ساعة و١٨ دقيقة", tr: "1 sa 18 dk sonra" })}</small></span>
        <Icon name="chevron" />
      </section>

      <section className="today-progress">
        <div className="section-heading"><div><span className="eyebrow">{l(locale, { ru: "Ваш ритм", en: "Your rhythm", ar: "إيقاعك", tr: "Ritminiz" })}</span><h2>{l(locale, { ru: "Сегодня", en: "Today", ar: "اليوم", tr: "Bugün" })}</h2></div><button className="text-button" onClick={() => navigate("plan")}>{l(locale, { ru: "Открыть план", en: "Open plan", ar: "فتح الخطة", tr: "Planı aç" })}</button></div>
        <div className="progress-hero-row">
          <div className="progress-ring" style={{ "--progress": `${progress * 3.6}deg` } as CSSProperties}><span><strong>{number(locale, state.dailyAchieved)}</strong><small>{l(locale, { ru: `из ${state.dailyTarget}`, en: `of ${state.dailyTarget}`, ar: `من ${number(locale, state.dailyTarget)}`, tr: `/${state.dailyTarget}` })}</small></span></div>
          <div className="progress-copy"><strong>{l(locale, { ru: "Спокойный темп", en: "A calm pace", ar: "وتيرة هادئة", tr: "Sakin bir tempo" })}</strong><p>{l(locale, { ru: `Осталось ${Math.max(0, state.dailyTarget - state.dailyAchieved)} страницы. Без давления — продолжите, когда удобно.`, en: `${Math.max(0, state.dailyTarget - state.dailyAchieved)} pages left. Continue when it suits you.`, ar: `تبقى ${number(locale, Math.max(0, state.dailyTarget - state.dailyAchieved))} صفحات. تابع عندما يناسبك.`, tr: `${Math.max(0, state.dailyTarget - state.dailyAchieved)} sayfa kaldı. Size uygun olduğunda devam edin.` })}</p><ProgressBar value={state.dailyAchieved} max={state.dailyTarget} /></div>
        </div>
      </section>

      <div className="home-asym-grid">
        <button className="feature-panel sand" onClick={() => navigate("prayer-reading")}>
          <span className="feature-icon"><Icon name="clock" /></span>
          <span className="feature-copy"><small>{l(locale, { ru: "После намаза", en: "After prayer", ar: "بعد الصلاة", tr: "Namaz sonrası" })}</small><strong>{number(locale, prayerTotal)} / {number(locale, 10)} {l(locale, { ru: "стр.", en: "pp.", ar: "صفحات", tr: "sf." })}</strong></span>
          <span className="mini-bars"><i className="done"/><i className="done"/><i/><i/><i/></span>
        </button>
        <button className="feature-panel ink" onClick={() => navigate("memorization")}>
          <span className="feature-icon"><Icon name="repeat" /></span>
          <span className="feature-copy"><small>{l(locale, { ru: "Заучивание", en: "Memorization", ar: "الحفظ", tr: "Ezber" })}</small><strong>{locale === "ar" ? "الفاتحة ١–٣" : "Аль-Фатиха 1–3"}</strong></span>
          <span className="mini-progress">{number(locale, state.memorization.completedRepetitions)} / {number(locale, state.memorization.targetRepetitions)}</span>
        </button>
      </div>

      <section className="home-list-card">
        <button className="home-list-row" onClick={() => navigate("audio")}>
          <span className="reciter-avatar small">{reciter.initials}</span>
          <span><small>{l(locale, { ru: "Недавний чтец", en: "Recent reciter", ar: "القارئ الأخير", tr: "Son kâri" })}</small><strong>{reciter[locale]}</strong></span><Icon name="play" filled />
        </button>
        <button className="home-list-row" onClick={() => navigate("dua")}>
          <span className="list-icon gold"><Icon name="spark" /></span>
          <span><small>{l(locale, { ru: "Ду’а дня", en: "Dua of the day", ar: "دعاء اليوم", tr: "Günün duası" })}</small><strong>{l(locale, { ru: "После пробуждения", en: "When waking up", ar: "عند الاستيقاظ", tr: "Uyanınca" })}</strong></span><Icon name="chevron" />
        </button>
      </section>

      <section className="coming-strip">
        <div><span className="eyebrow">{l(locale, { ru: "Дальше", en: "Next", ar: "قادم", tr: "Sırada" })}</span><h2>{l(locale, { ru: "Учиться в своём темпе", en: "Learn at your own pace", ar: "تعلم وفق وتيرتك", tr: "Kendi hızınızda öğrenin" })}</h2></div>
        <div className="coming-pills"><span><Icon name="book" />{l(locale, { ru: "Книги", en: "Books", ar: "كتب", tr: "Kitaplar" })}</span><span><Icon name="target" />{l(locale, { ru: "Квизы", en: "Quizzes", ar: "اختبارات", tr: "Testler" })}</span><span><Icon name="spark" />Q&amp;A</span></div>
        <span className="soon-badge">{l(locale, { ru: "Скоро", en: "Soon", ar: "قريبًا", tr: "Yakında" })}</span>
      </section>

      {state.accountMode === "guest" ? <button className="guest-sync-card" onClick={() => navigate("account")}><Icon name="shield" /><span><strong>{l(locale, { ru: "Читаете как гость", en: "Reading as guest", ar: "تقرأ كضيف", tr: "Misafir olarak okuyorsunuz" })}</strong><small>{l(locale, { ru: "Войдите, чтобы продолжить на другом устройстве", en: "Sign in to continue on another device", ar: "سجّل الدخول للمتابعة على جهاز آخر", tr: "Başka cihazda devam etmek için giriş yapın" })}</small></span><Icon name="chevron" /></button> : null}
    </Screen>
  );
}
