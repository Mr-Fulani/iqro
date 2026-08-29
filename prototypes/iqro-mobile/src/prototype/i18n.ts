import type { Locale } from "./types";

export type Localized = Record<Locale, string>;

export function l(locale: Locale, value: Localized): string {
  return value[locale] || value.ru;
}

export const ui = {
  nav: {
    home: { ru: "Главная", en: "Home", ar: "الرئيسية", tr: "Ana sayfa" },
    quran: { ru: "Коран", en: "Quran", ar: "القرآن", tr: "Kur'an" },
    plan: { ru: "План", en: "Plan", ar: "الخطة", tr: "Plan" },
    audio: { ru: "Аудио", en: "Audio", ar: "الصوت", tr: "Ses" },
    more: { ru: "Ещё", en: "More", ar: "المزيد", tr: "Daha" },
  },
  common: {
    back: { ru: "Назад", en: "Back", ar: "رجوع", tr: "Geri" },
    continue: { ru: "Продолжить", en: "Continue", ar: "متابعة", tr: "Devam" },
    save: { ru: "Сохранить", en: "Save", ar: "حفظ", tr: "Kaydet" },
    cancel: { ru: "Отмена", en: "Cancel", ar: "إلغاء", tr: "İptal" },
    soon: { ru: "Скоро", en: "Soon", ar: "قريبًا", tr: "Yakında" },
    today: { ru: "Сегодня", en: "Today", ar: "اليوم", tr: "Bugün" },
    ayah: { ru: "аят", en: "ayah", ar: "آية", tr: "ayet" },
    ayahs: { ru: "аятов", en: "ayahs", ar: "آيات", tr: "ayet" },
    pages: { ru: "страниц", en: "pages", ar: "صفحات", tr: "sayfa" },
    minutes: { ru: "минут", en: "minutes", ar: "دقائق", tr: "dakika" },
    guest: { ru: "Гость", en: "Guest", ar: "ضيف", tr: "Misafir" },
  },
} satisfies Record<string, Record<string, Localized>>;

export function number(locale: Locale, value: number): string {
  return new Intl.NumberFormat(locale === "ar" ? "ar" : locale).format(value);
}
