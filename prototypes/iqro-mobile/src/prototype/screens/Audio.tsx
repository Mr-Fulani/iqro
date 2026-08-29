"use client";

import { useState } from "react";
import { IconButton, Screen, TopBar } from "../components";
import { reciters, surahs } from "../data";
import { Icon } from "../icons";
import { l, number } from "../i18n";
import { usePrototype } from "../store";

export function AudioScreen() {
  const { state, setState, navigate, notify } = usePrototype();
  const locale = state.locale;
  const currentReciter = reciters.find((item) => item.id === state.selectedReciter) || reciters[0];
  const selectReciter = (id: string) => {
    const changed = id !== state.selectedReciter;
    setState((current) => ({ ...current, selectedReciter: id, player: { ...current.player, reciterId: id, playing: changed ? false : current.player.playing } }));
    if (changed && state.player.active) notify(l(locale, { ru: "Чтец изменён. Нажмите Play, чтобы начать новое исполнение.", en: "Reciter changed. Press Play to start the new recitation.", ar: "تم تغيير القارئ. اضغط تشغيل لبدء التلاوة الجديدة.", tr: "Kâri değişti. Yeni tilaveti başlatmak için Oynat'a basın." }));
  };
  const playSurah = (surah: number) => {
    setState((current) => ({ ...current, player: { ...current.player, active: true, playing: true, surah, ayah: 1, reciterId: current.selectedReciter, progress: 4 } }));
  };
  return (
    <Screen className="audio-screen">
      <TopBar title={l(locale, { ru: "Слушать Коран", en: "Listen to Quran", ar: "استمع إلى القرآن", tr: "Kur'an dinle" })} subtitle={l(locale, { ru: "Проверенные публикации", en: "Verified releases", ar: "إصدارات موثقة", tr: "Doğrulanmış yayınlar" })} action={<IconButton label="Open player" onClick={() => navigate("player")}><Icon name="headphones" /></IconButton>} />
      <section className="audio-featured">
        <div className="audio-wave-art" aria-hidden="true"><i/><i/><i/><i/><i/><i/><i/></div>
        <span className="eyebrow light">{l(locale, { ru: "Выбранный чтец", en: "Selected reciter", ar: "القارئ المختار", tr: "Seçili kâri" })}</span>
        <div className="featured-reciter"><span className="reciter-avatar">{currentReciter.initials}</span><span><h1>{currentReciter[locale]}</h1><p>{currentReciter.ar}</p></span></div>
        <button className="button inverse" onClick={() => {
          playSurah(1);
          navigate("player");
        }}><Icon name="play" filled />{l(locale, { ru: "Слушать Аль-Фатиху", en: "Play Al-Faatiha", ar: "تشغيل الفاتحة", tr: "Fâtiha'yı dinle" })}</button>
      </section>

      <section className="section-block">
        <div className="section-heading"><div><span className="eyebrow">{l(locale, { ru: "Голоса", en: "Voices", ar: "القراء", tr: "Kâriler" })}</span><h2>{l(locale, { ru: "Чтецы", en: "Reciters", ar: "القراء", tr: "Kâriler" })}</h2></div><span className="count-chip">{number(locale, 18)}</span></div>
        <div className="reciter-scroller">
          {reciters.map((reciter) => <button key={reciter.id} className={`reciter-tile ${state.selectedReciter === reciter.id ? "is-selected" : ""}`} onClick={() => selectReciter(reciter.id)}><span className="reciter-avatar">{reciter.initials}</span><strong>{reciter[locale]}</strong><small>{state.selectedReciter === reciter.id ? l(locale, { ru: "Выбран", en: "Selected", ar: "مختار", tr: "Seçili" }) : reciter.ar}</small>{state.selectedReciter === reciter.id ? <span className="selected-dot"><Icon name="check" size={14} /></span> : null}</button>)}
        </div>
      </section>

      <section className="section-block tracks-block">
        <div className="section-heading"><div><span className="eyebrow">{l(locale, { ru: "Суры", en: "Surahs", ar: "السور", tr: "Sureler" })}</span><h2>{l(locale, { ru: "Дорожки", en: "Tracks", ar: "المقاطع", tr: "Parçalar" })}</h2></div><button className="text-button"><Icon name="download" size={18}/>{l(locale, { ru: "Офлайн", en: "Offline", ar: "دون اتصال", tr: "Çevrimdışı" })}</button></div>
        <div className="track-list">
          {surahs.slice(0, 6).map((surah, index) => {
            const isCurrent = state.player.active && state.player.surah === surah.number;
            return <button className={`track-row ${isCurrent ? "is-current" : ""}`} key={surah.number} onClick={() => playSurah(surah.number)}><span className="track-number">{number(locale, surah.number)}</span><span className="track-copy"><strong>{surah[locale]}</strong><small>{surah.ar} · {index === 0 ? "01:34" : `${3 + index}:2${index}`}</small></span><span className="track-play"><Icon name={isCurrent && state.player.playing ? "pause" : "play"} filled /></span></button>;
          })}
        </div>
      </section>
    </Screen>
  );
}

export function PlayerScreen() {
  const { state, setState, goBack, notify } = usePrototype();
  const locale = state.locale;
  const [showQueue, setShowQueue] = useState(false);
  const [sleepTimer, setSleepTimer] = useState("");
  const reciter = reciters.find((item) => item.id === state.player.reciterId) || reciters[0];
  const changeReciter = (id: string) => {
    if (id === state.player.reciterId) return;
    setState((current) => ({ ...current, selectedReciter: id, player: { ...current.player, reciterId: id, playing: false, progress: 0 } }));
    notify(l(locale, { ru: "Старое воспроизведение остановлено", en: "Previous playback stopped", ar: "تم إيقاف التشغيل السابق", tr: "Önceki oynatma durduruldu" }));
  };
  const cycleRepeat = () => {
    const order = ["off", "ayah", "range", "surah"] as const;
    const next = order[(order.indexOf(state.player.repeat) + 1) % order.length];
    setState((current) => ({ ...current, player: { ...current.player, repeat: next } }));
  };
  return (
    <Screen className="player-screen" nav={false}>
      <header className="player-top"><IconButton label="Back" onClick={goBack}><Icon name="arrow" /></IconButton><span><strong>{l(locale, { ru: "Сейчас играет", en: "Now playing", ar: "يُشغل الآن", tr: "Şimdi çalıyor" })}</strong><small>{l(locale, { ru: "Мадинский Мусхаф · Хафс", en: "Madani Mushaf · Hafs", ar: "مصحف المدينة · حفص", tr: "Medine Mushafı · Hafs" })}</small></span><IconButton label="Queue" onClick={() => setShowQueue((value) => !value)}><Icon name="list" /></IconButton></header>
      <div className="player-art"><div className={`sound-orbit ${state.player.playing ? "is-playing" : ""}`}><span className="orbit-ring ring-one"/><span className="orbit-ring ring-two"/><span className="orbit-ring ring-three"/><div className="player-monogram">{reciter.initials}</div></div></div>
      <div className="player-title"><span className="eyebrow">{l(locale, { ru: `Сура 1 · Аят ${state.player.ayah}`, en: `Surah 1 · Ayah ${state.player.ayah}`, ar: `السورة ١ · الآية ${number(locale, state.player.ayah)}`, tr: `Sure 1 · Ayet ${state.player.ayah}` })}</span><h1>{locale === "ar" ? "الفاتحة" : locale === "ru" ? "Аль-Фатиха" : locale === "tr" ? "Fâtiha" : "Al-Faatiha"}</h1><button onClick={() => setShowQueue(true)}>{reciter[locale]}<Icon name="chevron" size={17}/></button></div>
      <div className="player-progress"><input type="range" min="0" max="100" value={state.player.progress} onChange={(event) => setState((current) => ({ ...current, player: { ...current.player, progress: Number(event.target.value) } }))}/><div><span>00:18</span><span>01:34</span></div></div>
      <div className="player-controls"><IconButton label="Repeat" className={state.player.repeat !== "off" ? "is-active" : ""} onClick={cycleRepeat}><Icon name="repeat" /></IconButton><IconButton label="Previous"><Icon name="skipBack" size={28}/></IconButton><button className="main-play" aria-label={state.player.playing ? "Pause" : "Play"} onClick={() => setState((current) => ({ ...current, player: { ...current.player, active: true, playing: !current.player.playing } }))}><Icon name={state.player.playing ? "pause" : "play"} filled size={32}/></button><IconButton label="Next"><Icon name="skipForward" size={28}/></IconButton><IconButton label="Sleep timer" className={sleepTimer ? "is-active" : ""} onClick={() => setSleepTimer((current) => current ? "" : "15 min")}><Icon name="timer" /></IconButton></div>
      <div className="repeat-label">{state.player.repeat === "off" ? l(locale, { ru: "Повтор выключен", en: "Repeat off", ar: "التكرار متوقف", tr: "Tekrar kapalı" }) : state.player.repeat === "ayah" ? l(locale, { ru: "Повтор аята", en: "Repeat ayah", ar: "تكرار الآية", tr: "Ayeti tekrarla" }) : state.player.repeat === "range" ? l(locale, { ru: "Диапазон 1–3", en: "Range 1–3", ar: "النطاق ١–٣", tr: "Aralık 1–3" }) : l(locale, { ru: "Повтор суры", en: "Repeat surah", ar: "تكرار السورة", tr: "Sureyi tekrarla" })}</div>
      <section className="player-settings-grid">
        <label><span><Icon name="clock"/><small>{l(locale, { ru: "Скорость", en: "Speed", ar: "السرعة", tr: "Hız" })}</small></span><select value={state.player.speed} onChange={(event) => setState((current) => ({ ...current, player: { ...current.player, speed: Number(event.target.value) } }))}><option value="0.75">0.75×</option><option value="1">1×</option><option value="1.25">1.25×</option><option value="1.5">1.5×</option></select></label>
        <label><span><Icon name="timer"/><small>{l(locale, { ru: "Пауза", en: "Pause", ar: "الفاصل", tr: "Ara" })}</small></span><select value={state.player.pauseSeconds} onChange={(event) => setState((current) => ({ ...current, player: { ...current.player, pauseSeconds: Number(event.target.value) } }))}><option value="0">0 s</option><option value="1">1 s</option><option value="2">2 s</option><option value="5">5 s</option></select></label>
        <button onClick={() => setState((current) => ({ ...current, player: { ...current.player, repeat: "range" } }))}><span><Icon name="layers"/><small>{l(locale, { ru: "Диапазон", en: "Range", ar: "النطاق", tr: "Aralık" })}</small></span><strong>1–3</strong></button>
        <button onClick={() => setSleepTimer((current) => current ? "" : "15 min")}><span><Icon name="moon"/><small>{l(locale, { ru: "Таймер", en: "Timer", ar: "المؤقت", tr: "Zamanlayıcı" })}</small></span><strong>{sleepTimer || "Off"}</strong></button>
      </section>
      <section className="native-media-note"><Icon name="device"/><span><strong>{l(locale, { ru: "Media Session и экран блокировки", en: "Media Session & lock screen", ar: "جلسة الوسائط وشاشة القفل", tr: "Medya oturumu ve kilit ekranı" })}</strong><small>{l(locale, { ru: "Модель готова для native audio service во Flutter", en: "Ready to map to a native Flutter audio service", ar: "جاهز للربط بخدمة صوت أصلية في Flutter", tr: "Flutter yerel ses hizmetine hazır" })}</small></span><Icon name="check"/></section>
      <section className="nature-sounds"><div><Icon name="volume"/><span><strong>{l(locale, { ru: "Звуки природы", en: "Nature sounds", ar: "أصوات الطبيعة", tr: "Doğa sesleri" })}</strong><small>{l(locale, { ru: "Отдельная громкость", en: "Independent volume", ar: "مستوى صوت مستقل", tr: "Bağımsız ses" })}</small></span></div><span className="soon-badge">{l(locale, { ru: "Скоро", en: "Soon", ar: "قريبًا", tr: "Yakında" })}</span></section>
      {showQueue ? <div className="sheet-backdrop" onClick={() => setShowQueue(false)}><section className="bottom-sheet queue-sheet" onClick={(event) => event.stopPropagation()}><div className="sheet-handle"/><div className="sheet-title"><div><span className="eyebrow">{l(locale, { ru: "Воспроизведение", en: "Playback", ar: "التشغيل", tr: "Oynatma" })}</span><h2>{l(locale, { ru: "Выберите чтеца", en: "Choose reciter", ar: "اختر القارئ", tr: "Kâri seçin" })}</h2></div><IconButton label="Close" onClick={() => setShowQueue(false)}><Icon name="close"/></IconButton></div><div className="queue-reciter-list">{reciters.map((item) => <button key={item.id} className={state.player.reciterId === item.id ? "is-selected" : ""} onClick={() => changeReciter(item.id)}><span className="reciter-avatar small">{item.initials}</span><span><strong>{item[locale]}</strong><small>{item.ar}</small></span>{state.player.reciterId === item.id ? <Icon name="check"/> : null}</button>)}</div><p className="calm-caption">{l(locale, { ru: "При смене чтеца текущее воспроизведение останавливается. Следующий Play запускает нового чтеца.", en: "Changing reciter stops current playback. The next Play starts the new recitation.", ar: "عند تغيير القارئ يتوقف التشغيل الحالي، ويبدأ زر التشغيل التالي التلاوة الجديدة.", tr: "Kâri değişince mevcut oynatma durur. Sonraki Oynat yeni tilaveti başlatır." })}</p></section></div> : null}
    </Screen>
  );
}
