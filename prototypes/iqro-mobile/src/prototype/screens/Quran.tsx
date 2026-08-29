"use client";

import { useMemo, useState } from "react";
import { IconButton, Screen, TopBar } from "../components";
import { alFatihaAyahs, reciters, surahs } from "../data";
import { Icon } from "../icons";
import { l, number } from "../i18n";
import { usePrototype } from "../store";

function SurahName({ surah }: { surah: (typeof surahs)[number] }) {
  const { state } = usePrototype();
  return <>{surah[state.locale]}</>;
}

export function QuranScreen() {
  const { state, setState, navigate } = usePrototype();
  const [query, setQuery] = useState("");
  const filtered = useMemo(() => surahs.filter((surah) => `${surah.ru} ${surah.en} ${surah.ar} ${surah.number}`.toLowerCase().includes(query.toLowerCase())), [query]);
  const locale = state.locale;
  const openSelection = () => navigate(state.readerMode === "text" ? "reader" : "mushaf");
  return (
    <Screen className="quran-screen">
      <TopBar title={l(locale, { ru: "Коран", en: "Quran", ar: "القرآن", tr: "Kur'an" })} subtitle={l(locale, { ru: "Мадинский Мусхаф · Хафс", en: "Madani Mushaf · Hafs", ar: "مصحف المدينة · حفص", tr: "Medine Mushafı · Hafs" })} action={<IconButton label="Quick jump" onClick={() => setState((current) => ({ ...current, modal: "quick-jump" }))}><Icon name="layers" /></IconButton>} />

      <section className="quran-mode-card">
        <div className="segmented" role="tablist" aria-label="Reader mode">
          <button className={state.readerMode === "text" ? "is-active" : ""} onClick={() => setState((current) => ({ ...current, readerMode: "text" }))}><Icon name="list" />{l(locale, { ru: "Текст", en: "Text", ar: "النص", tr: "Metin" })}</button>
          <button className={state.readerMode === "mushaf" ? "is-active" : ""} onClick={() => setState((current) => ({ ...current, readerMode: "mushaf" }))}><Icon name="book" />{l(locale, { ru: "Мусхаф", en: "Mushaf", ar: "المصحف", tr: "Mushaf" })}</button>
        </div>
        <button className="mushaf-choice" onClick={() => setState((current) => ({ ...current, mushafId: current.mushafId === 5 ? 19 : 5 }))}>
          <span><small>{l(locale, { ru: "Выбранный Мусхаф", en: "Selected Mushaf", ar: "المصحف المختار", tr: "Seçili Mushaf" })}</small><strong>{state.mushafId === 19 ? "QCF V4 Tajweed" : "KFGQPC Hafs"}</strong></span><Icon name="chevron" />
        </button>
      </section>

      <button className="resume-reading" onClick={openSelection}>
        <span className="resume-icon"><Icon name={state.readerMode === "text" ? "list" : "book"} /></span>
        <span><small>{l(locale, { ru: "Продолжить с сохранённого места", en: "Continue from saved position", ar: "متابعة من الموضع المحفوظ", tr: "Kayıtlı yerden devam et" })}</small><strong>{locale === "ar" ? "الفاتحة" : locale === "ru" ? "Аль-Фатиха" : "Al-Faatiha"} · {number(locale, state.lastPosition.ayah)}</strong><em>{l(locale, { ru: "Сохранено автоматически", en: "Saved automatically", ar: "حُفظ تلقائيًا", tr: "Otomatik kaydedildi" })}</em></span>
        <Icon name="chevron" />
      </button>

      <div className="search-field"><Icon name="search" /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder={l(locale, { ru: "Сура, аят, джуз или страница", en: "Surah, ayah, juz or page", ar: "السورة أو الآية أو الجزء أو الصفحة", tr: "Sure, ayet, cüz veya sayfa" })} aria-label="Search Quran" /></div>

      <div className="catalog-tabs"><button className="is-active">{l(locale, { ru: "Суры", en: "Surahs", ar: "السور", tr: "Sureler" })}</button><button onClick={() => setState((current) => ({ ...current, modal: "quick-jump" }))}>{l(locale, { ru: "Джузы", en: "Juz", ar: "الأجزاء", tr: "Cüzler" })}</button><button onClick={() => setState((current) => ({ ...current, modal: "quick-jump" }))}>{l(locale, { ru: "Страницы", en: "Pages", ar: "الصفحات", tr: "Sayfalar" })}</button></div>
      <section className="surah-list" aria-label="Surah catalog">
        {filtered.map((surah) => (
          <button key={surah.number} className="surah-row" onClick={() => {
            setState((current) => ({ ...current, selectedAyah: 1, lastPosition: { surah: surah.number, ayah: 1, page: surah.number === 1 ? 1 : Math.min(604, surah.number * 4) } }));
            navigate(state.readerMode === "text" ? "reader" : "mushaf");
          }}>
            <span className="surah-number">{number(locale, surah.number)}</span>
            <span className="surah-copy"><strong><SurahName surah={surah} /></strong><small>{number(locale, surah.ayahs)} {l(locale, { ru: "аятов", en: "ayahs", ar: "آيات", tr: "ayet" })} · {l(locale, surah.place === "meccan" ? { ru: "Мекканская", en: "Meccan", ar: "مكية", tr: "Mekkî" } : { ru: "Мединская", en: "Medinan", ar: "مدنية", tr: "Medenî" })}</small></span>
            <span className="surah-arabic" lang="ar" dir="rtl">{surah.ar}</span>
          </button>
        ))}
      </section>
      {state.modal === "quick-jump" ? <QuickJump /> : null}
    </Screen>
  );
}

function QuickJump() {
  const { state, setState, navigate } = usePrototype();
  const [tab, setTab] = useState<"ayah" | "juz" | "page">("ayah");
  return (
    <div className="sheet-backdrop" role="presentation" onClick={() => setState((current) => ({ ...current, modal: "" }))}>
      <section className="bottom-sheet" role="dialog" aria-modal="true" aria-labelledby="jump-title" onClick={(event) => event.stopPropagation()}>
        <div className="sheet-handle" /><div className="sheet-title"><div><span className="eyebrow">{l(state.locale, { ru: "Навигация", en: "Navigation", ar: "التنقل", tr: "Gezinme" })}</span><h2 id="jump-title">{l(state.locale, { ru: "Быстрый переход", en: "Quick jump", ar: "انتقال سريع", tr: "Hızlı geçiş" })}</h2></div><IconButton label="Close" onClick={() => setState((current) => ({ ...current, modal: "" }))}><Icon name="close" /></IconButton></div>
        <div className="segmented compact"><button className={tab === "ayah" ? "is-active" : ""} onClick={() => setTab("ayah")}>{l(state.locale, { ru: "Аят", en: "Ayah", ar: "آية", tr: "Ayet" })}</button><button className={tab === "juz" ? "is-active" : ""} onClick={() => setTab("juz")}>{l(state.locale, { ru: "Джуз", en: "Juz", ar: "جزء", tr: "Cüz" })}</button><button className={tab === "page" ? "is-active" : ""} onClick={() => setTab("page")}>{l(state.locale, { ru: "Страница", en: "Page", ar: "صفحة", tr: "Sayfa" })}</button></div>
        {tab === "ayah" ? <div className="form-grid two"><label><span>{l(state.locale, { ru: "Сура", en: "Surah", ar: "السورة", tr: "Sure" })}</span><select defaultValue="1"><option value="1">1. {state.locale === "ar" ? "الفاتحة" : "Аль-Фатиха"}</option><option value="2">2. {state.locale === "ar" ? "البقرة" : "Аль-Бакара"}</option></select></label><label><span>{l(state.locale, { ru: "Аят", en: "Ayah", ar: "الآية", tr: "Ayet" })}</span><input type="number" min="1" max="7" defaultValue="2" /></label></div> : <label className="field"><span>{tab === "juz" ? l(state.locale, { ru: "Номер джуза", en: "Juz number", ar: "رقم الجزء", tr: "Cüz numarası" }) : l(state.locale, { ru: "Номер страницы", en: "Page number", ar: "رقم الصفحة", tr: "Sayfa numarası" })}</span><input type="number" min="1" max={tab === "juz" ? 30 : 604} defaultValue="1" /></label>}
        <button className="button primary wide" onClick={() => {
          setState((current) => ({ ...current, modal: "", selectedAyah: 2, lastPosition: { surah: 1, ayah: 2, page: 1 } }));
          navigate(state.readerMode === "text" ? "reader" : "mushaf");
        }}>{l(state.locale, { ru: "Открыть", en: "Open", ar: "فتح", tr: "Aç" })}<Icon name="chevron" /></button>
      </section>
    </div>
  );
}

export function ReaderScreen() {
  const { state, setState, navigate, notify } = usePrototype();
  const [showTranslation, setShowTranslation] = useState(true);
  const [showTafsir, setShowTafsir] = useState(false);
  const locale = state.locale;
  const activeReciter = reciters.find((item) => item.id === state.selectedReciter) || reciters[0];
  const toggleBookmark = (ayah: number) => {
    const key = `1:${ayah}`;
    const active = state.quranBookmarks.includes(key);
    setState((current) => ({ ...current, quranBookmarks: active ? current.quranBookmarks.filter((item) => item !== key) : [...current.quranBookmarks, key] }));
    notify(active ? l(locale, { ru: "Закладка удалена", en: "Bookmark removed", ar: "تمت إزالة العلامة", tr: "Yer imi kaldırıldı" }) : l(locale, { ru: "Добавлено в избранное", en: "Added to favorites", ar: "أُضيف إلى المفضلة", tr: "Favorilere eklendi" }));
  };
  return (
    <Screen className="reader-screen" nav={false}>
      <TopBar title={locale === "ar" ? "الفاتحة" : locale === "ru" ? "Аль-Фатиха" : "Al-Faatiha"} subtitle={`${l(locale, { ru: "Сура 1", en: "Surah 1", ar: "السورة ١", tr: "Sure 1" })} · ${number(locale, 7)} ${l(locale, { ru: "аятов", en: "ayahs", ar: "آيات", tr: "ayet" })}`} back action={<IconButton label="Reader settings" onClick={() => setState((current) => ({ ...current, modal: "reader-settings" }))}><Icon name="settings" /></IconButton>} />
      <div className="reader-calm-bar"><span><Icon name="refresh" size={15} />{l(locale, { ru: "Место сохраняется автоматически", en: "Your position saves automatically", ar: "يُحفظ موضعك تلقائيًا", tr: "Konumunuz otomatik kaydedilir" })}</span><button onClick={() => navigate("mushaf")}><Icon name="book" />{l(locale, { ru: "Мусхаф", en: "Mushaf", ar: "المصحف", tr: "Mushaf" })}</button></div>
      <article className="reader-intro"><span className="ornament-line"/><h1 lang="ar" dir="rtl">الفاتحة</h1><p>{l(locale, { ru: "Открывающая · Мекканская", en: "The Opening · Meccan", ar: "الفاتحة · مكية", tr: "Açılış · Mekkî" })}</p><span className="ornament-line"/></article>
      <section className="ayah-list">
        {alFatihaAyahs.map((text, index) => {
          const ayah = index + 1;
          const bookmarked = state.quranBookmarks.includes(`1:${ayah}`);
          const selected = state.selectedAyah === ayah;
          return (
            <article key={text} className={`ayah-card ${selected ? "is-selected" : ""}`} onClick={() => setState((current) => ({ ...current, selectedAyah: ayah, lastPosition: { surah: 1, ayah, page: 1 } }))}>
              <header><span className="ayah-index">1:{number(locale, ayah)}</span><div className="ayah-actions"><IconButton label="Play ayah" onClick={() => setState((current) => ({ ...current, player: { ...current.player, active: true, playing: true, ayah, surah: 1, reciterId: current.selectedReciter } }))}><Icon name="play" filled /></IconButton><IconButton label="Bookmark" className={bookmarked ? "is-active" : ""} onClick={() => toggleBookmark(ayah)}><Icon name="bookmark" filled={bookmarked} /></IconButton></div></header>
              <p className="ayah-arabic" lang="ar" dir="rtl">{text}<span className="ayah-end">{number("ar", ayah)}</span></p>
              {showTranslation ? <div className="translation-placeholder"><span>{l(locale, { ru: "Перевод · Э. Кулиев", en: "Translation · selected edition", ar: "الترجمة · النسخة المختارة", tr: "Meal · seçili kaynak" })}</span><p>{l(locale, { ru: "Текст перевода загружается из выбранной опубликованной редакции API и намеренно не дублируется в mock-данных.", en: "Translation text is loaded from the selected published API edition and is intentionally not duplicated in mock data.", ar: "يُحمَّل نص الترجمة من النسخة المنشورة المختارة عبر الواجهة البرمجية، ولا يُكرر عمدًا في البيانات التجريبية.", tr: "Meal metni seçili yayımlanmış API kaynağından yüklenir ve mock veride bilerek çoğaltılmaz." })}</p><details><summary>{l(locale, { ru: "Сноски", en: "Footnotes", ar: "الحواشي", tr: "Dipnotlar" })}</summary><small>{l(locale, { ru: "Для этого mock-ответа массив сносок пуст.", en: "The footnote array is empty for this mock response.", ar: "مصفوفة الحواشي فارغة في هذه الاستجابة التجريبية.", tr: "Bu mock yanıt için dipnot dizisi boştur." })}</small></details></div> : null}
              {showTafsir ? <details className="tafsir" open={selected}><summary>{l(locale, { ru: "Тафсир ас-Са’ди", en: "Tafsir · selected edition", ar: "التفسير · النسخة المختارة", tr: "Tefsir · seçili kaynak" })}</summary><p>{l(locale, { ru: "Тафсир загружается по запросу из отдельного versioned API. Контент не включён в прототип без editorial sign-off.", en: "Tafsir loads on demand from its separate versioned API. Content is not bundled without editorial sign-off.", ar: "يُحمّل التفسير عند الطلب من واجهة مستقلة ذات إصدارات، ولا يُضمّن المحتوى دون اعتماد تحريري.", tr: "Tefsir ayrı sürümlü API'den istek üzerine yüklenir; içerik editoryal onay olmadan eklenmez." })}</p></details> : null}
            </article>
          );
        })}
      </section>
      <div className="reader-footer-space" />
      {state.player.active ? <div className="reader-mini"><button onClick={() => navigate("player")}><span className="reciter-avatar tiny">{activeReciter.initials}</span><span><strong>{locale === "ar" ? "الفاتحة" : "Аль-Фатиха"} · {state.player.ayah}</strong><small>{activeReciter[locale]}</small></span></button><IconButton label={state.player.playing ? "Pause" : "Play"} onClick={() => setState((current) => ({ ...current, player: { ...current.player, playing: !current.player.playing } }))}><Icon name={state.player.playing ? "pause" : "play"} filled /></IconButton></div> : null}
      {state.modal === "reader-settings" ? <div className="sheet-backdrop" onClick={() => setState((current) => ({ ...current, modal: "" }))}><section className="bottom-sheet reader-settings" onClick={(event) => event.stopPropagation()}><div className="sheet-handle"/><div className="sheet-title"><h2>{l(locale, { ru: "Настройки чтения", en: "Reading settings", ar: "إعدادات القراءة", tr: "Okuma ayarları" })}</h2><IconButton label="Close" onClick={() => setState((current) => ({ ...current, modal: "" }))}><Icon name="close" /></IconButton></div><label className="setting-line"><span><strong>{l(locale, { ru: "Перевод", en: "Translation", ar: "الترجمة", tr: "Meal" })}</strong><small>{l(locale, { ru: "Выбранная редакция", en: "Selected edition", ar: "النسخة المختارة", tr: "Seçili kaynak" })}</small></span><input type="checkbox" checked={showTranslation} onChange={() => setShowTranslation((value) => !value)} /></label><label className="setting-line"><span><strong>{l(locale, { ru: "Тафсир", en: "Tafsir", ar: "التفسير", tr: "Tefsir" })}</strong><small>{l(locale, { ru: "Загружать по запросу", en: "Load on demand", ar: "التحميل عند الطلب", tr: "İstek üzerine yükle" })}</small></span><input type="checkbox" checked={showTafsir} onChange={() => setShowTafsir((value) => !value)} /></label><label className="field"><span>{l(locale, { ru: "Чтец", en: "Reciter", ar: "القارئ", tr: "Kâri" })}</span><select value={state.selectedReciter} onChange={(event) => setState((current) => ({ ...current, selectedReciter: event.target.value }))}>{reciters.map((reciter) => <option key={reciter.id} value={reciter.id}>{reciter[locale]}</option>)}</select></label><div className="font-size-preview"><span>A</span><input type="range" min="1" max="3" defaultValue="2"/><strong>A</strong></div></section></div> : null}
    </Screen>
  );
}

export function MushafScreen() {
  const { state, setState, navigate } = usePrototype();
  const locale = state.locale;
  return (
    <Screen className="mushaf-screen" nav={false}>
      <TopBar title={l(locale, { ru: "Страница 1", en: "Page 1", ar: "الصفحة ١", tr: "Sayfa 1" })} subtitle={l(locale, { ru: "Джуз 1 · Аль-Фатиха", en: "Juz 1 · Al-Faatiha", ar: "الجزء ١ · الفاتحة", tr: "Cüz 1 · Fâtiha" })} back action={<IconButton label="Open text reader" onClick={() => navigate("reader")}><Icon name="list" /></IconButton>} />
      <div className="mushaf-controls"><button onClick={() => setState((current) => ({ ...current, mushafZoom: Math.max(.82, current.mushafZoom - .08) }))} aria-label="Zoom out">−</button><input type="range" min="82" max="132" value={Math.round(state.mushafZoom * 100)} onChange={(event) => setState((current) => ({ ...current, mushafZoom: Number(event.target.value) / 100 }))}/><button onClick={() => setState((current) => ({ ...current, mushafZoom: Math.min(1.32, current.mushafZoom + .08) }))} aria-label="Zoom in">+</button><span>{Math.round(state.mushafZoom * 100)}%</span></div>
      <div className="mushaf-viewport">
        <article className="mushaf-paper" style={{ transform: `scale(${state.mushafZoom})` }} aria-label="Mushaf page 1">
          <div className="mushaf-border"><div className="mushaf-title" lang="ar" dir="rtl">سُورَةُ الفَاتِحَة</div><div className="mushaf-basmala" lang="ar" dir="rtl">{alFatihaAyahs[0]}</div><div className="mushaf-lines" lang="ar" dir="rtl">{alFatihaAyahs.slice(1).map((ayah, index) => <button key={ayah} className={state.selectedAyah === index + 2 ? "is-highlighted" : ""} onClick={() => setState((current) => ({ ...current, selectedAyah: index + 2, lastPosition: { surah: 1, ayah: index + 2, page: 1 } }))}>{ayah}<span>{number("ar", index + 2)}</span></button>)}</div><div className="mushaf-page-number">١</div></div>
        </article>
      </div>
      <div className="swipe-hint"><Icon name="arrow"/><span>{l(locale, { ru: "Смахните для перехода между страницами", en: "Swipe between pages", ar: "اسحب للتنقل بين الصفحات", tr: "Sayfalar arasında kaydırın" })}</span><Icon name="chevron"/></div>
      <div className="mushaf-bottom"><button onClick={() => setState((current) => ({ ...current, player: { ...current.player, active: true, playing: !current.player.playing, ayah: current.selectedAyah, reciterId: current.selectedReciter } }))}><Icon name={state.player.playing ? "pause" : "play"} filled /><span><strong>{locale === "ar" ? "الفاتحة" : "Аль-Фатиха"} · {number(locale, state.selectedAyah)}</strong><small>{l(locale, { ru: "Нажмите аят, чтобы выбрать", en: "Tap an ayah to select", ar: "اضغط على آية لتحديدها", tr: "Seçmek için ayete dokunun" })}</small></span></button><IconButton label="Quick jump" onClick={() => setState((current) => ({ ...current, previousRoute: "mushaf", route: "quran", modal: "quick-jump" }))}><Icon name="layers" /></IconButton></div>
    </Screen>
  );
}
