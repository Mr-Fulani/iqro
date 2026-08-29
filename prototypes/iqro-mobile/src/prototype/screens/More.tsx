"use client";

import { useState } from "react";
import { IconButton, Screen, TopBar } from "../components";
import { duaEntry, duaTopics } from "../data";
import { Icon } from "../icons";
import { l, number } from "../i18n";
import { initialState } from "../initialState";
import { usePrototype } from "../store";
import type { Locale, Route, SystemState } from "../types";

const moreItems: Array<{ route: Route; icon: "spark" | "repeat" | "clock" | "bookmark" | "user" | "settings"; title: Record<Locale, string>; text: Record<Locale, string> }> = [
  { route: "dua", icon: "spark", title: { ru: "Ду’а", en: "Dua", ar: "الدعاء", tr: "Dua" }, text: { ru: "Темы и проверенные источники", en: "Topics and trusted sources", ar: "موضوعات ومصادر موثوقة", tr: "Konular ve güvenilir kaynaklar" } },
  { route: "memorization", icon: "repeat", title: { ru: "Заучивание", en: "Memorization", ar: "الحفظ", tr: "Ezber" }, text: { ru: "Повторы и прогресс", en: "Repetition and progress", ar: "التكرار والتقدم", tr: "Tekrar ve ilerleme" } },
  { route: "prayer", icon: "clock", title: { ru: "Намаз", en: "Prayer", ar: "الصلاة", tr: "Namaz" }, text: { ru: "Расписание и уведомления", en: "Times and notifications", ar: "المواقيت والإشعارات", tr: "Vakitler ve bildirimler" } },
  { route: "favorites", icon: "bookmark", title: { ru: "Избранное", en: "Favorites", ar: "المفضلة", tr: "Favoriler" }, text: { ru: "Коран и ду’а", en: "Quran and dua", ar: "القرآن والدعاء", tr: "Kur'an ve dua" } },
  { route: "account", icon: "user", title: { ru: "Аккаунт", en: "Account", ar: "الحساب", tr: "Hesap" }, text: { ru: "Устройства и синхронизация", en: "Devices and sync", ar: "الأجهزة والمزامنة", tr: "Cihazlar ve eşitleme" } },
  { route: "settings", icon: "settings", title: { ru: "Настройки", en: "Settings", ar: "الإعدادات", tr: "Ayarlar" }, text: { ru: "Язык, тема и чтение", en: "Language, theme and reading", ar: "اللغة والمظهر والقراءة", tr: "Dil, tema ve okuma" } },
];

export function MoreScreen() {
  const { state, navigate } = usePrototype();
  return (
    <Screen className="more-screen">
      <TopBar title={l(state.locale, { ru: "Ещё", en: "More", ar: "المزيد", tr: "Daha" })} subtitle={l(state.locale, { ru: "Всё остальное — рядом", en: "Everything else, close by", ar: "كل ما تحتاجه قريب", tr: "Diğer her şey yakında" })}/>
      <section className="more-profile" onClick={() => navigate("account")}><span className="profile-avatar"><Icon name="user"/></span><span><strong>{state.accountMode === "guest" ? l(state.locale, { ru: "Гостевой режим", en: "Guest mode", ar: "وضع الضيف", tr: "Misafir modu" }) : "reader@iqro.app"}</strong><small>{state.accountMode === "guest" ? l(state.locale, { ru: "Данные сохраняются на этом устройстве", en: "Data is saved on this device", ar: "تُحفظ البيانات على هذا الجهاز", tr: "Veriler bu cihazda saklanır" }) : l(state.locale, { ru: "Синхронизация включена", en: "Sync is on", ar: "المزامنة مفعلة", tr: "Eşitleme açık" })}</small></span><Icon name="chevron"/></section>
      <div className="more-grid">{moreItems.map((item) => <button key={item.route} onClick={() => navigate(item.route)}><span className={`more-icon ${item.route}`}><Icon name={item.icon}/></span><span><strong>{item.title[state.locale]}</strong><small>{item.text[state.locale]}</small></span><Icon name="chevron"/></button>)}</div>
      <section className="more-coming"><span className="eyebrow">IQRO</span><h2>{l(state.locale, { ru: "Один спокойный путь к знаниям", en: "One calm path to knowledge", ar: "طريق هادئ إلى المعرفة", tr: "Bilgiye sakin bir yol" })}</h2><p>{l(state.locale, { ru: "Книги, квизы и вопросы-ответы появятся как отдельные проверенные домены.", en: "Books, quizzes and Q&A will arrive as separate verified domains.", ar: "ستتوفر الكتب والاختبارات والأسئلة والأجوبة كمجالات مستقلة موثقة.", tr: "Kitaplar, testler ve Soru-Cevap ayrı doğrulanmış alanlar olarak gelecek." })}</p><span className="soon-badge">{l(state.locale, { ru: "Скоро", en: "Soon", ar: "قريبًا", tr: "Yakında" })}</span></section>
    </Screen>
  );
}

export function DuaScreen() {
  const { state, navigate } = usePrototype();
  const [query, setQuery] = useState("");
  const filtered = duaTopics.filter((topic) => `${topic.ru} ${topic.en} ${topic.ar}`.toLowerCase().includes(query.toLowerCase()));
  return (
    <Screen className="dua-screen">
      <TopBar back title={l(state.locale, { ru: "Ду’а", en: "Dua", ar: "الدعاء", tr: "Dua" })} subtitle={l(state.locale, { ru: "Хисн аль-Муслим", en: "Hisn al-Muslim", ar: "حصن المسلم", tr: "Hısnu'l-Müslim" })} action={<IconButton label="Favorites" onClick={() => navigate("favorites")}><Icon name="bookmark" filled={state.duaFavorites.length > 0}/></IconButton>}/>
      <section className="dua-hero"><div className="dua-arch" aria-hidden="true"><span/><span/></div><span className="eyebrow light">{l(state.locale, { ru: "На каждый день", en: "For every day", ar: "لكل يوم", tr: "Her gün için" })}</span><h1>{l(state.locale, { ru: "Слова, к которым можно вернуться", en: "Words to return to", ar: "كلمات تعود إليها", tr: "Dönebileceğiniz sözler" })}</h1><p>{l(state.locale, { ru: "Арабский текст, перевод, источник и повторения — без лишнего шума.", en: "Arabic, meaning, source and repetitions — without clutter.", ar: "النص العربي والمعنى والمصدر والتكرار، بهدوء ووضوح.", tr: "Arapça metin, anlam, kaynak ve tekrarlar — sade biçimde." })}</p></section>
      <div className="search-field"><Icon name="search"/><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder={l(state.locale, { ru: "Найти тему", en: "Find a topic", ar: "ابحث عن موضوع", tr: "Konu bul" })}/></div>
      <section className="dua-topic-grid">{filtered.map((topic, index) => <button key={topic.id} className={`dua-topic tone-${index}`} onClick={() => navigate("dua-topic")}><span className="dua-topic-icon"><Icon name={topic.icon as "sunrise" | "home" | "arch" | "droplet"}/></span><span className="topic-number">{number(state.locale, topic.id)}</span><strong>{topic[state.locale]}</strong><small>{number(state.locale, topic.count)} {l(state.locale, { ru: "ду’а", en: "dua", ar: "أدعية", tr: "dua" })}</small><Icon name="chevron"/></button>)}</section>
      <p className="source-foot"><Icon name="shield" size={17}/>{l(state.locale, { ru: "Источники и версии отображаются у каждой карточки.", en: "Source and version are shown on every entry.", ar: "يظهر المصدر والإصدار في كل بطاقة.", tr: "Kaynak ve sürüm her kartta gösterilir." })}</p>
    </Screen>
  );
}

export function DuaTopicScreen() {
  const { state, navigate } = usePrototype();
  return (
    <Screen className="dua-topic-screen">
      <TopBar back title={duaEntry.title[state.locale]} subtitle={l(state.locale, { ru: "2 ду’а", en: "2 dua", ar: "دعاءان", tr: "2 dua" })}/>
      <section className="topic-intro"><span className="list-icon gold"><Icon name="sunrise"/></span><span><h1>{duaEntry.title[state.locale]}</h1><p>{l(state.locale, { ru: "Мягкое начало дня с достоверным источником.", en: "A gentle start to the day with a trusted source.", ar: "بداية هادئة لليوم من مصدر موثوق.", tr: "Güvenilir bir kaynakla güne sakin başlangıç." })}</p></span></section>
      <button className="dua-entry-preview" onClick={() => navigate("dua-entry")}><header><span>№ {number(state.locale, 1)}</span><span><Icon name="repeat" size={16}/> ×{number(state.locale, 1)}</span></header><p lang="ar" dir="rtl">{duaEntry.arabic}</p><strong>{duaEntry.title[state.locale]}</strong><small>{duaEntry.source}</small><div><span>{l(state.locale, { ru: "Открыть", en: "Open", ar: "فتح", tr: "Aç" })}</span><Icon name="chevron"/></div></button>
      <button className="dua-entry-preview muted" onClick={() => navigate("dua-entry")}><header><span>№ {number(state.locale, 2)}</span><span><Icon name="repeat" size={16}/> ×{number(state.locale, 1)}</span></header><p lang="ar" dir="rtl">الْحَمْدُ لِلَّهِ</p><strong>{l(state.locale, { ru: "Следующее ду’а", en: "Next dua", ar: "الدعاء التالي", tr: "Sonraki dua" })}</strong><small>Hisn al-Muslim</small><div><span>{l(state.locale, { ru: "Открыть", en: "Open", ar: "فتح", tr: "Aç" })}</span><Icon name="chevron"/></div></button>
    </Screen>
  );
}

export function DuaEntryScreen() {
  const { state, setState, notify } = usePrototype();
  const [playing, setPlaying] = useState(false);
  const favorite = state.duaFavorites.includes(duaEntry.sourceNumber);
  return (
    <Screen className="dua-entry-screen" nav={false}>
      <TopBar back title={duaEntry.title[state.locale]} subtitle={`Hisn al-Muslim · № ${number(state.locale, duaEntry.sourceNumber)}`} action={<IconButton label="Bookmark" className={favorite ? "is-active" : ""} onClick={() => {
        setState((current) => ({ ...current, duaFavorites: favorite ? current.duaFavorites.filter((item) => item !== duaEntry.sourceNumber) : [...current.duaFavorites, duaEntry.sourceNumber] }));
        notify(favorite ? l(state.locale, { ru: "Удалено из избранного", en: "Removed from favorites", ar: "أُزيل من المفضلة", tr: "Favorilerden kaldırıldı" }) : l(state.locale, { ru: "Добавлено в избранное", en: "Added to favorites", ar: "أُضيف إلى المفضلة", tr: "Favorilere eklendi" }));
      }}><Icon name="bookmark" filled={favorite}/></IconButton>}/>
      <article className="dua-detail-card"><div className="dua-detail-meta"><span>{l(state.locale, { ru: "Повторить", en: "Repeat", ar: "التكرار", tr: "Tekrar" })} ×{number(state.locale, duaEntry.repetitions)}</span><span className="verified-chip"><Icon name="shield" size={15}/>{l(state.locale, { ru: "Источник указан", en: "Source cited", ar: "المصدر موثق", tr: "Kaynak belirtilmiş" })}</span></div><p className="dua-arabic" lang="ar" dir="rtl">{duaEntry.arabic}</p><button className="dua-audio-button" onClick={() => setPlaying((value) => !value)}><Icon name={playing ? "pause" : "play"} filled/><span><strong>{playing ? l(state.locale, { ru: "Пауза", en: "Pause", ar: "إيقاف مؤقت", tr: "Duraklat" }) : l(state.locale, { ru: "Прослушать", en: "Listen", ar: "استمع", tr: "Dinle" })}</strong><small>00:{playing ? "08" : "00"} / 00:12</small></span><span className="audio-mini-wave"><i/><i/><i/><i/></span></button><section><span className="detail-label">{l(state.locale, { ru: "Перевод", en: "Meaning", ar: "المعنى", tr: "Anlam" })}</span><p>{duaEntry.meaning[state.locale]}</p></section>{state.locale === "ru" ? <section><span className="detail-label">{l(state.locale, { ru: "Транслитерация", en: "Transliteration", ar: "النقل الصوتي", tr: "Transliterasyon" })}</span><p className="transliteration">{duaEntry.transliteration}</p></section> : null}<details className="source-details" open><summary><Icon name="info"/> {l(state.locale, { ru: "Источник и достоверность", en: "Source and verification", ar: "المصدر والتحقق", tr: "Kaynak ve doğrulama" })}</summary><p>{duaEntry.source}</p><small>IslamHouse · source-only verification</small></details><button className="coming-action" disabled><Icon name="repeat"/><span><strong>{l(state.locale, { ru: "Добавить в заучивание", en: "Add to memorization", ar: "إضافة إلى الحفظ", tr: "Ezbere ekle" })}</strong><small>{l(state.locale, { ru: "Синхронизируемый flow появится позже", en: "A synced flow comes later", ar: "ستتوفر مزامنة هذا المسار لاحقًا", tr: "Eşitlenen akış daha sonra gelecek" })}</small></span><span className="soon-badge">{l(state.locale, { ru: "Скоро", en: "Soon", ar: "قريبًا", tr: "Yakında" })}</span></button></article>
    </Screen>
  );
}

export function FavoritesScreen() {
  const { state, navigate } = usePrototype();
  const [filter, setFilter] = useState<"all" | "quran" | "dua">("all");
  const showQuran = filter !== "dua";
  const showDua = filter !== "quran";
  return (
    <Screen className="favorites-screen">
      <TopBar back title={l(state.locale, { ru: "Избранное", en: "Favorites", ar: "المفضلة", tr: "Favoriler" })} subtitle={l(state.locale, { ru: "Точные места, без лишнего текста", en: "Exact places, easy to return", ar: "مواضع دقيقة للعودة بسهولة", tr: "Kolay dönüş için tam konumlar" })}/>
      <div className="filter-pills"><button className={filter === "all" ? "is-active" : ""} onClick={() => setFilter("all")}>{l(state.locale, { ru: "Все", en: "All", ar: "الكل", tr: "Tümü" })}</button><button className={filter === "quran" ? "is-active" : ""} onClick={() => setFilter("quran")}>{l(state.locale, { ru: "Коран", en: "Quran", ar: "القرآن", tr: "Kur'an" })}</button><button className={filter === "dua" ? "is-active" : ""} onClick={() => setFilter("dua")}>{l(state.locale, { ru: "Ду’а", en: "Dua", ar: "الدعاء", tr: "Dua" })}</button></div>
      {showQuran ? <section className="favorite-section"><div className="section-heading"><h2>{l(state.locale, { ru: "Коран", en: "Quran", ar: "القرآن", tr: "Kur'an" })}</h2><span className="count-chip">{number(state.locale, state.quranBookmarks.length)}</span></div>{state.quranBookmarks.length ? state.quranBookmarks.map((key) => <button className="favorite-row" key={key} onClick={() => navigate("reader")}><span className="list-icon green"><Icon name="bookmark" filled/></span><span><strong>{state.locale === "ar" ? "الفاتحة" : "Аль-Фатиха"} · {key}</strong><small>{l(state.locale, { ru: "Страница 1 · Джуз 1", en: "Page 1 · Juz 1", ar: "الصفحة ١ · الجزء ١", tr: "Sayfa 1 · Cüz 1" })}</small></span><Icon name="chevron"/></button>) : <div className="empty-state small"><Icon name="bookmark"/><p>{l(state.locale, { ru: "Закладок Корана пока нет", en: "No Quran bookmarks yet", ar: "لا توجد علامات للقرآن بعد", tr: "Henüz Kur'an yer imi yok" })}</p></div>}</section> : null}
      {showDua ? <section className="favorite-section"><div className="section-heading"><h2>{l(state.locale, { ru: "Ду’а", en: "Dua", ar: "الدعاء", tr: "Dua" })}</h2><span className="count-chip">{number(state.locale, state.duaFavorites.length)}</span></div>{state.duaFavorites.length ? <button className="favorite-row" onClick={() => navigate("dua-entry")}><span className="list-icon gold"><Icon name="bookmark" filled/></span><span><strong>{duaEntry.title[state.locale]}</strong><small>Hisn al-Muslim · № {number(state.locale, 1)}</small></span><Icon name="chevron"/></button> : <div className="empty-state small"><Icon name="spark"/><p>{l(state.locale, { ru: "Сохраните ду’а, чтобы вернуться к нему здесь", en: "Save a dua to find it here", ar: "احفظ دعاءً لتجده هنا", tr: "Burada bulmak için bir dua kaydedin" })}</p></div>}</section> : null}
    </Screen>
  );
}

export function AccountScreen() {
  const { state, setState, navigate, notify } = usePrototype();
  return (
    <Screen className="account-screen">
      <TopBar back title={l(state.locale, { ru: "Аккаунт", en: "Account", ar: "الحساب", tr: "Hesap" })} subtitle={state.accountMode === "guest" ? l(state.locale, { ru: "Гостевой режим", en: "Guest mode", ar: "وضع الضيف", tr: "Misafir modu" }) : "reader@iqro.app"}/>
      <section className="account-identity"><span className="profile-avatar large"><Icon name="user" size={30}/></span><span><strong>{state.accountMode === "guest" ? l(state.locale, { ru: "Ваше чтение на этом устройстве", en: "Your reading on this device", ar: "قراءتك على هذا الجهاز", tr: "Bu cihazdaki okumanız" }) : "reader@iqro.app"}</strong><small>{l(state.locale, { ru: "Изменения сохраняются на устройстве и отправятся в аккаунт после восстановления сети.", en: "Changes stay on device and sync to your account when the connection returns.", ar: "تُحفظ التغييرات على الجهاز وتُرسل إلى حسابك عند عودة الاتصال.", tr: "Değişiklikler cihazda kalır ve bağlantı geldiğinde hesabınıza eşitlenir." })}</small></span></section>
      {state.accountMode === "guest" ? <button className="button primary wide" onClick={() => { setState((current) => ({ ...current, accountMode: "verified" })); notify(l(state.locale, { ru: "Демо: аккаунт подтверждён", en: "Demo: account verified", ar: "تجربة: تم توثيق الحساب", tr: "Demo: hesap doğrulandı" })); }}><Icon name="mail"/>{l(state.locale, { ru: "Войти по email", en: "Sign in with email", ar: "تسجيل الدخول بالبريد", tr: "E-posta ile giriş" })}</button> : null}
      <section className="account-group"><h2>{l(state.locale, { ru: "Устройства и данные", en: "Devices & data", ar: "الأجهزة والبيانات", tr: "Cihazlar ve veriler" })}</h2><button><span className="list-icon green"><Icon name="device"/></span><span><strong>{l(state.locale, { ru: "Этот iPhone", en: "This iPhone", ar: "هذا الآيفون", tr: "Bu iPhone" })}</strong><small>{l(state.locale, { ru: "Синхронизировано только что", en: "Synced just now", ar: "تمت المزامنة الآن", tr: "Az önce eşitlendi" })}</small></span><span className="current-chip">{l(state.locale, { ru: "Текущее", en: "Current", ar: "الحالي", tr: "Mevcut" })}</span></button><button><span className="list-icon sand"><Icon name="refresh"/></span><span><strong>{l(state.locale, { ru: "Синхронизация", en: "Synchronization", ar: "المزامنة", tr: "Eşitleme" })}</strong><small>{l(state.locale, { ru: "0 изменений ожидают отправки", en: "0 changes waiting to sync", ar: "لا تغييرات بانتظار الإرسال", tr: "Eşitleme bekleyen 0 değişiklik" })}</small></span><Icon name="chevron"/></button></section>
      <section className="account-group"><h2>{l(state.locale, { ru: "Предпочтения", en: "Preferences", ar: "التفضيلات", tr: "Tercihler" })}</h2><button onClick={() => navigate("settings")}><span className="list-icon blue"><Icon name="globe"/></span><span><strong>{l(state.locale, { ru: "Язык и тема", en: "Language & theme", ar: "اللغة والمظهر", tr: "Dil ve tema" })}</strong><small>{state.locale.toUpperCase()} · {state.theme === "dark" ? l(state.locale, { ru: "Тёмная", en: "Dark", ar: "داكن", tr: "Koyu" }) : l(state.locale, { ru: "Светлая", en: "Light", ar: "فاتح", tr: "Açık" })}</small></span><Icon name="chevron"/></button><button onClick={() => navigate("settings")}><span className="list-icon green"><Icon name="headphones"/></span><span><strong>{l(state.locale, { ru: "Чтец и Мусхаф", en: "Reciter & Mushaf", ar: "القارئ والمصحف", tr: "Kâri ve Mushaf" })}</strong><small>KFGQPC Hafs</small></span><Icon name="chevron"/></button></section>
      <section className="account-group"><h2>{l(state.locale, { ru: "Конфиденциальность", en: "Privacy", ar: "الخصوصية", tr: "Gizlilik" })}</h2><button><span className="list-icon sand"><Icon name="download"/></span><span><strong>{l(state.locale, { ru: "Экспортировать данные", en: "Export data", ar: "تصدير البيانات", tr: "Verileri dışa aktar" })}</strong><small>{l(state.locale, { ru: "Подготовить копию", en: "Prepare a copy", ar: "إعداد نسخة", tr: "Bir kopya hazırla" })}</small></span><Icon name="chevron"/></button><button className="danger-row"><span className="list-icon danger"><Icon name="trash"/></span><span><strong>{l(state.locale, { ru: "Удалить аккаунт", en: "Delete account", ar: "حذف الحساب", tr: "Hesabı sil" })}</strong><small>{l(state.locale, { ru: "С подтверждением по email", en: "Requires email confirmation", ar: "يتطلب تأكيد البريد", tr: "E-posta onayı gerektirir" })}</small></span><Icon name="chevron"/></button></section>
    </Screen>
  );
}

export function SettingsScreen() {
  const { state, setState, notify } = usePrototype();
  const states: Array<{ id: SystemState; label: string }> = [
    { id: "loading", label: "Loading" }, { id: "offline", label: "Offline" }, { id: "api-error", label: "API error" },
    { id: "session-expired", label: "Session" }, { id: "sync-conflict", label: "Sync conflict" }, { id: "notifications-denied", label: "No notifications" },
    { id: "geolocation-denied", label: "No location" }, { id: "no-audio", label: "No audio" }, { id: "offline-unavailable", label: "No offline copy" },
  ];
  return (
    <Screen className="settings-screen">
      <TopBar back title={l(state.locale, { ru: "Настройки", en: "Settings", ar: "الإعدادات", tr: "Ayarlar" })} subtitle={l(state.locale, { ru: "Прототип", en: "Prototype", ar: "النموذج الأولي", tr: "Prototip" })}/>
      <section className="settings-group"><h2>{l(state.locale, { ru: "Внешний вид", en: "Appearance", ar: "المظهر", tr: "Görünüm" })}</h2><div className="theme-choice"><button className={state.theme === "light" ? "is-selected" : ""} onClick={() => setState((current) => ({ ...current, theme: "light" }))}><span className="theme-preview light"><Icon name="sun"/></span>{l(state.locale, { ru: "Светлая", en: "Light", ar: "فاتح", tr: "Açık" })}</button><button className={state.theme === "dark" ? "is-selected" : ""} onClick={() => setState((current) => ({ ...current, theme: "dark" }))}><span className="theme-preview dark"><Icon name="moon"/></span>{l(state.locale, { ru: "Тёмная", en: "Dark", ar: "داكن", tr: "Koyu" })}</button></div><label className="field"><span>{l(state.locale, { ru: "Язык", en: "Language", ar: "اللغة", tr: "Dil" })}</span><select value={state.locale} onChange={(event) => setState((current) => ({ ...current, locale: event.target.value as Locale }))}><option value="ru">Русский</option><option value="en">English</option><option value="ar">العربية</option><option value="tr">Türkçe</option></select></label></section>
      <section className="settings-group"><h2>{l(state.locale, { ru: "Чтение", en: "Reading", ar: "القراءة", tr: "Okuma" })}</h2><div className="setting-line"><span><strong>{l(state.locale, { ru: "Режим по умолчанию", en: "Default mode", ar: "الوضع الافتراضي", tr: "Varsayılan mod" })}</strong><small>{state.readerMode === "text" ? l(state.locale, { ru: "Текст", en: "Text", ar: "النص", tr: "Metin" }) : l(state.locale, { ru: "Мусхаф", en: "Mushaf", ar: "المصحف", tr: "Mushaf" })}</small></span><div className="segmented tiny"><button className={state.readerMode === "text" ? "is-active" : ""} onClick={() => setState((current) => ({ ...current, readerMode: "text" }))}>{l(state.locale, { ru: "Текст", en: "Text", ar: "نص", tr: "Metin" })}</button><button className={state.readerMode === "mushaf" ? "is-active" : ""} onClick={() => setState((current) => ({ ...current, readerMode: "mushaf" }))}>{l(state.locale, { ru: "Мусхаф", en: "Mushaf", ar: "مصحف", tr: "Mushaf" })}</button></div></div><label className="field"><span>{l(state.locale, { ru: "Мусхаф", en: "Mushaf", ar: "المصحف", tr: "Mushaf" })}</span><select value={state.mushafId} onChange={(event) => setState((current) => ({ ...current, mushafId: Number(event.target.value) }))}><option value="5">KFGQPC Hafs</option><option value="19">QCF V4 Tajweed</option></select></label></section>
      <section className="settings-group prototype-lab"><h2>{l(state.locale, { ru: "Системные состояния", en: "System states", ar: "حالات النظام", tr: "Sistem durumları" })}</h2><p>{l(state.locale, { ru: "Только для проверки прототипа: показывает понятные состояния без технических кодов.", en: "Prototype-only controls for testing user-friendly states without technical codes.", ar: "أدوات تجريبية لاختبار الحالات المفهومة دون رموز تقنية.", tr: "Teknik kodlar olmadan anlaşılır durumları test etmek için prototip kontrolleri." })}</p><div className="state-chip-grid">{states.map((item) => <button key={item.id} className={state.systemState === item.id ? "is-active" : ""} onClick={() => setState((current) => ({ ...current, systemState: item.id }))}>{item.label}</button>)}</div><button className="button secondary wide" onClick={() => { window.localStorage.clear(); setState({ ...initialState, route: "settings", previousRoute: "more", onboarded: true }); notify(l(state.locale, { ru: "Демо-данные сброшены", en: "Demo data reset", ar: "تمت إعادة ضبط البيانات التجريبية", tr: "Demo verileri sıfırlandı" })); }}><Icon name="refresh"/>{l(state.locale, { ru: "Сбросить демо-данные", en: "Reset demo data", ar: "إعادة ضبط البيانات التجريبية", tr: "Demo verilerini sıfırla" })}</button></section>
    </Screen>
  );
}
