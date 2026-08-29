"use client";

import { BrandMark, ProgressBar } from "../components";
import { Icon } from "../icons";
import { l, number, ui } from "../i18n";
import { usePrototype } from "../store";
import type { Locale } from "../types";

const languages: Array<{ code: Locale; native: string; secondary: string }> = [
  { code: "ru", native: "Русский", secondary: "Russian" },
  { code: "en", native: "English", secondary: "English" },
  { code: "ar", native: "العربية", secondary: "Arabic · RTL" },
  { code: "tr", native: "Türkçe", secondary: "Turkish" },
];

export function OnboardingLanguage() {
  const { state, setState, navigate } = usePrototype();
  return (
    <div className="onboarding-screen">
      <div className="onboarding-brand"><BrandMark /></div>
      <div className="onboarding-art" aria-hidden="true">
        <span className="orbit orbit-one" /><span className="orbit orbit-two" />
        <div className="open-book-mark"><Icon name="book" size={44} /></div>
      </div>
      <div className="onboarding-copy">
        <span className="step-pill">1 / 3</span>
        <h1>{l(state.locale, { ru: "Как вам удобнее?", en: "Which language feels natural?", ar: "ما اللغة الأنسب لك؟", tr: "Hangi dili tercih edersiniz?" })}</h1>
        <p>{l(state.locale, { ru: "Язык можно изменить в любой момент. Арабская версия полностью поддерживает RTL.", en: "You can change it anytime. Arabic includes full RTL support.", ar: "يمكنك تغيير اللغة في أي وقت. الواجهة العربية تدعم الاتجاه من اليمين إلى اليسار بالكامل.", tr: "Dili istediğiniz zaman değiştirebilirsiniz. Arapça tam RTL desteğine sahiptir." })}</p>
      </div>
      <div className="language-list">
        {languages.map((language) => (
          <button key={language.code} className={`language-option ${state.locale === language.code ? "is-selected" : ""}`} onClick={() => setState((current) => ({ ...current, locale: language.code }))}>
            <span><strong>{language.native}</strong><small>{language.secondary}</small></span>
            <span className="radio-mark">{state.locale === language.code ? <Icon name="check" size={16} /> : null}</span>
          </button>
        ))}
      </div>
      <button className="button primary wide" onClick={() => navigate("onboarding-goal")}>
        {l(state.locale, ui.common.continue)} <Icon name="chevron" />
      </button>
    </div>
  );
}

export function OnboardingGoal() {
  const { state, setState, navigate, goBack } = usePrototype();
  const goals = [
    { id: "reading", icon: "book" as const, title: { ru: "Читать регулярно", en: "Read regularly", ar: "القراءة بانتظام", tr: "Düzenli okumak" }, text: { ru: "Небольшой ежедневный ритм", en: "A calm daily rhythm", ar: "وتيرة يومية هادئة", tr: "Sakin bir günlük ritim" } },
    { id: "memorization", icon: "repeat" as const, title: { ru: "Заучивать аяты", en: "Memorize ayahs", ar: "حفظ الآيات", tr: "Ayet ezberlemek" }, text: { ru: "Повторы и самооценка", en: "Repetition and reflection", ar: "التكرار والتقييم الذاتي", tr: "Tekrar ve öz değerlendirme" } },
    { id: "prayer", icon: "clock" as const, title: { ru: "Быть рядом с намазом", en: "Stay close to prayer", ar: "المحافظة على الصلاة", tr: "Namaza yakın kalmak" }, text: { ru: "Расписание и чтение после молитвы", en: "Times and after-prayer reading", ar: "المواقيت والقراءة بعد الصلاة", tr: "Vakitler ve namaz sonrası okuma" } },
    { id: "dua", icon: "spark" as const, title: { ru: "Читать ду’а", en: "Read dua", ar: "قراءة الدعاء", tr: "Dua okumak" }, text: { ru: "Проверенные источники по темам", en: "Trusted sources by topic", ar: "مصادر موثوقة حسب الموضوع", tr: "Konulara göre güvenilir kaynaklar" } },
  ] as const;
  return (
    <div className="onboarding-screen">
      <div className="onboarding-top"><button className="icon-button" onClick={goBack} aria-label="Back"><Icon name="arrow" /></button><span className="step-pill">2 / 3</span></div>
      <div className="onboarding-copy compact">
        <h1>{l(state.locale, { ru: "С чего начнём?", en: "What brings you here?", ar: "بماذا نبدأ؟", tr: "Nereden başlayalım?" })}</h1>
        <p>{l(state.locale, { ru: "IQRO подстроит Главную под вашу основную цель.", en: "IQRO will shape Home around your main goal.", ar: "سيخصص IQRO الصفحة الرئيسية لهدفك الأساسي.", tr: "IQRO ana sayfayı temel hedefinize göre düzenler." })}</p>
      </div>
      <div className="goal-grid">
        {goals.map((goal) => (
          <button key={goal.id} className={`goal-card ${state.goal === goal.id ? "is-selected" : ""}`} onClick={() => setState((current) => ({ ...current, goal: goal.id }))}>
            <span className="goal-icon"><Icon name={goal.icon} /></span>
            <strong>{l(state.locale, goal.title)}</strong><small>{l(state.locale, goal.text)}</small>
          </button>
        ))}
      </div>
      <button className="button primary wide" onClick={() => navigate("onboarding-norm")}>{l(state.locale, ui.common.continue)} <Icon name="chevron" /></button>
    </div>
  );
}

export function OnboardingNorm() {
  const { state, setState, navigate, goBack } = usePrototype();
  const options = [2, 4, 6, 10];
  return (
    <div className="onboarding-screen">
      <div className="onboarding-top"><button className="icon-button" onClick={goBack} aria-label="Back"><Icon name="arrow" /></button><span className="step-pill">3 / 3</span></div>
      <div className="onboarding-copy compact">
        <h1>{l(state.locale, { ru: "Мягкая ежедневная норма", en: "A gentle daily goal", ar: "هدف يومي ميسّر", tr: "Yumuşak bir günlük hedef" })}</h1>
        <p>{l(state.locale, { ru: "Пропуски не становятся долгом. Норму всегда можно изменить.", en: "Missed days never become debt. You can adjust this anytime.", ar: "الأيام الفائتة لا تتحول إلى دَين، ويمكنك تعديل الهدف في أي وقت.", tr: "Kaçırılan günler borca dönüşmez. Hedefi istediğiniz zaman değiştirebilirsiniz." })}</p>
      </div>
      <div className="norm-hero">
        <span>{number(state.locale, state.dailyTarget)}</span>
        <small>{l(state.locale, ui.common.pages)}</small>
        <ProgressBar value={state.dailyTarget} max={10} />
      </div>
      <div className="choice-row" role="group" aria-label="Daily target">
        {options.map((option) => <button key={option} className={state.dailyTarget === option ? "is-selected" : ""} onClick={() => setState((current) => ({ ...current, dailyTarget: option }))}>{number(state.locale, option)}</button>)}
      </div>
      <div className="calm-note"><Icon name="bell" /><span>{l(state.locale, { ru: "Уведомления предложим позже — когда вы настроите План.", en: "We’ll offer notifications later, when you set up your Plan.", ar: "سنقترح الإشعارات لاحقًا عند إعداد خطتك.", tr: "Bildirimleri daha sonra, Planınızı kurarken önereceğiz." })}</span></div>
      <button className="button primary wide" onClick={() => {
        setState((current) => ({ ...current, onboarded: true, accountMode: "guest" }));
        navigate("home");
      }}><Icon name="shield" /> {l(state.locale, { ru: "Продолжить как гость", en: "Continue as guest", ar: "المتابعة كضيف", tr: "Misafir olarak devam et" })}</button>
    </div>
  );
}
