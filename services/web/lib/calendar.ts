import type { Locale } from "./i18n";

export type CalendarEvent = {
  code: string;
  kind: "occasion" | "voluntary_fast" | "no_fast";
  month: number;
  day_start: number;
  day_end: number;
  titles: Record<Locale, string>;
  descriptions: Record<Locale, string>;
  source: { label: string; url: string };
};
export type CalendarDay = { day: number; civil_date: string; events: string[] };
export type CalendarMonth = {
  method: "ummalqura-hijri-3.0.1";
  year: number;
  month: number;
  selected_day: number | null;
  adjustment: number;
  first_weekday: number;
  days: CalendarDay[];
  catalog: { version: string; events: CalendarEvent[]; min_year: number; max_year: number };
};

export const WEEKLY_FAST_EVENT: CalendarEvent = {
  code: "monday_thursday_fast",
  kind: "voluntary_fast",
  month: 0,
  day_start: 1,
  day_end: 30,
  titles: {
    ru: "Пост в понедельник и четверг",
    en: "Monday and Thursday fasting",
    ar: "صيام الاثنين والخميس",
    tr: "Pazartesi ve perşembe orucu",
  },
  descriptions: {
    ru: "Посланник Аллаха ﷺ сообщил, что дела представляются в понедельник и четверг, и он любил, чтобы его дела представлялись, когда он постится.",
    en: "The Messenger of Allah ﷺ said that deeds are presented on Monday and Thursday, and he loved for his deeds to be presented while he was fasting.",
    ar: "أخبر رسول الله ﷺ أن الأعمال تُعرض يوم الاثنين والخميس، وكان يحب أن يُعرض عمله وهو صائم.",
    tr: "Resûlullah ﷺ amellerin pazartesi ve perşembe günleri arz edildiğini ve amelinin oruçluyken arz edilmesini sevdiğini bildirmiştir.",
  },
  source: {
    label: "Jami‘ at-Tirmidhi 747",
    url: "https://sunnah.com/tirmidhi:747",
  },
};

export function calendarEventsForDay(data: CalendarMonth, day: CalendarDay): CalendarEvent[] {
  const events = data.catalog.events.filter((event) => day.events.includes(event.code));
  const weekday = new Date(`${day.civil_date}T12:00:00Z`).getUTCDay();
  const isWeeklyFast = weekday === 1 || weekday === 4;
  const isBuiltInNoFastDay =
    (data.month === 10 && day.day === 1) ||
    (data.month === 12 && day.day >= 10 && day.day <= 13);
  const isNoFastDay = isBuiltInNoFastDay || events.some((event) => event.kind === "no_fast");

  if (isWeeklyFast && data.month !== 9 && !isNoFastDay) events.push(WEEKLY_FAST_EVENT);
  return events;
}

export function civilToday(now = new Date()): string {
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;
}

export function sourceHref(value: string): string | undefined {
  try {
    const url = new URL(value);
    return url.protocol === "https:" && !url.username && !url.password ? url.href : undefined;
  } catch { return undefined; }
}

export const calendarCopy = {
  ru: {
    title: "Мусульманский календарь", subtitle: "Ритм года по Хиджре", method: "Умм аль-Кура",
    today: "Сегодня", previous: "Предыдущий месяц", next: "Следующий месяц", civil: "Григорианская дата",
    adjustment: "Поправка к дате", adjustmentHint: "Согласуйте дату с календарём своей общины. Поправка действует только на этом устройстве.",
    noEvents: "На этот день нет особых отметок.", source: "Источник", retry: "Обновить", loading: "Загружаем календарь…",
    error: "Не удалось обновить календарь. Проверьте соединение и повторите.", suffix: "г. х.",
    legend: "Обозначения календаря", occasion: "Значимая дата", voluntaryFast: "Желательный пост", noFast: "Праздник или день без поста",
    markerHint: "Наведите на значок или выберите дату, чтобы увидеть пояснение и источник.",
    disclaimer: "Расчётные даты могут отличаться от местного наблюдения луны. Начало Рамадана и праздников уточняйте в своей общине. Исламский день начинается с заходом солнца предыдущего гражданского дня. Здесь указано соответствие гражданских дат без автоматического сдвига после заката.",
    hint: "Справочные отметки, не персональная фетва. Для паломников действуют отдельные положения.",
    months: ["Мухаррам", "Сафар", "Раби аль-авваль", "Раби ас-сани", "Джумада аль-уля", "Джумада ас-сания", "Раджаб", "Шаабан", "Рамадан", "Шавваль", "Зуль-каада", "Зуль-хиджа"],
  },
  en: {
    title: "Hijri calendar", subtitle: "The rhythm of the Hijri year", method: "Umm al-Qura",
    today: "Today", previous: "Previous month", next: "Next month", civil: "Gregorian date",
    adjustment: "Date adjustment", adjustmentHint: "Match your local community's calendar. This adjustment applies only on this device.",
    noEvents: "No special markers for this day.", source: "Source", retry: "Refresh", loading: "Loading calendar…",
    error: "Could not refresh the calendar. Check your connection and try again.", suffix: "AH",
    legend: "Calendar markers", occasion: "Notable date", voluntaryFast: "Recommended fast", noFast: "Feast or no-fast day",
    markerHint: "Hover over an icon or select a date to see its explanation and source.",
    disclaimer: "Calculated dates may differ from local moon sighting. Confirm Ramadan and Eid with your local community. The Islamic day begins at sunset on the preceding civil day. This calendar maps civil dates without automatically shifting after sunset.",
    hint: "Reference markers, not a personal religious ruling. Pilgrims have separate guidance.",
    months: ["Muharram", "Safar", "Rabi al-Awwal", "Rabi al-Thani", "Jumada al-Ula", "Jumada al-Thani", "Rajab", "Shaban", "Ramadan", "Shawwal", "Dhul-Qadah", "Dhul-Hijjah"],
  },
  ar: {
    title: "التقويم الهجري", subtitle: "إيقاع السنة الهجرية", method: "أم القرى",
    today: "اليوم", previous: "الشهر السابق", next: "الشهر التالي", civil: "التاريخ الميلادي",
    adjustment: "تعديل التاريخ", adjustmentHint: "وافق التاريخ مع تقويم الجهات المحلية. يُطبّق التعديل على هذا الجهاز فقط.",
    noEvents: "لا توجد علامات خاصة لهذا اليوم.", source: "المصدر", retry: "تحديث", loading: "جارٍ تحميل التقويم…",
    error: "تعذّر تحديث التقويم. تحقّق من الاتصال وحاول مرة أخرى.", suffix: "هـ",
    legend: "دليل الرموز", occasion: "مناسبة مهمة", voluntaryFast: "صيام مستحب", noFast: "عيد أو يوم بلا صيام",
    markerHint: "مرّر المؤشر فوق الرمز أو اختر التاريخ لعرض الشرح والمصدر.",
    disclaimer: "قد تختلف التواريخ الحسابية عن رؤية الهلال المحلية. تحقّق من بداية رمضان والعيدين لدى الجهات المعتمدة. يبدأ اليوم الهجري عند غروب شمس اليوم المدني السابق. يعرض هذا التقويم مقابلة التواريخ المدنية دون تغيير تلقائي بعد الغروب.",
    hint: "علامات مرجعية وليست فتوى شخصية. للحجاج أحكام خاصة.",
    months: ["محرم", "صفر", "ربيع الأول", "ربيع الآخر", "جمادى الأولى", "جمادى الآخرة", "رجب", "شعبان", "رمضان", "شوال", "ذو القعدة", "ذو الحجة"],
  },
  tr: {
    title: "Hicri takvim", subtitle: "Hicri yılın ritmi", method: "Ümmü'l-Kurâ",
    today: "Bugün", previous: "Önceki ay", next: "Sonraki ay", civil: "Miladi tarih",
    adjustment: "Tarih düzeltmesi", adjustmentHint: "Tarihi yerel takviminizle eşleştirin. Düzeltme yalnızca bu cihazda geçerlidir.",
    noEvents: "Bu gün için özel bir işaret yok.", source: "Kaynak", retry: "Yenile", loading: "Takvim yükleniyor…",
    error: "Takvim güncellenemedi. Bağlantınızı kontrol edip tekrar deneyin.", suffix: "H",
    legend: "Takvim işaretleri", occasion: "Önemli tarih", voluntaryFast: "Müstehap oruç", noFast: "Bayram veya oruç tutulmayan gün",
    markerHint: "Açıklamayı ve kaynağı görmek için simgenin üzerine gelin veya tarihi seçin.",
    disclaimer: "Hesaplanan tarihler yerel hilal gözleminden farklı olabilir. Ramazan ve bayram başlangıçlarını yerel yetkililerden doğrulayın. Hicri gün, önceki miladi günün gün batımında başlar. Burada miladi tarihler gösterilir; gün batımında otomatik değişiklik yapılmaz.",
    hint: "Kaynak işaretleridir, kişisel fetva değildir. Hacılar için ayrı hükümler geçerlidir.",
    months: ["Muharrem", "Safer", "Rebiülevvel", "Rebiülahir", "Cemaziyelevvel", "Cemaziyelahir", "Recep", "Şaban", "Ramazan", "Şevval", "Zilkade", "Zilhicce"],
  },
} satisfies Record<Locale, object>;
