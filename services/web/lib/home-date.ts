import { type Locale, localeTag } from "./i18n";

// The same device-only preference as on the calendar page.
const ADJUSTMENT_KEY = "iqro_hijri_adjustment_v1";

function hijriAdjustment(): number {
  try {
    const stored = Number(localStorage.getItem(ADJUSTMENT_KEY) ?? 0);
    return Number.isInteger(stored) && stored >= -2 && stored <= 2 ? stored : 0;
  } catch {
    return 0;
  }
}

/**
 * Today's date for the phone's home top bar, as in the app: the weekday and
 * civil date, then the Hijri date (Umm al-Qura, like the calendar page,
 * without a shift after sunset). Browser only: it reads the visitor's clock.
 */
export function homeDateLine(locale: Locale, hijriMonths: string[], hijriSuffix: string, now = new Date()): string {
  const tag = localeTag(locale);
  const civil = new Intl.DateTimeFormat(tag, { weekday: "long", day: "numeric", month: "long" }).format(now);
  const shifted = new Date(now);
  shifted.setDate(shifted.getDate() + hijriAdjustment());
  const parts = Object.fromEntries(
    new Intl.DateTimeFormat("en-u-ca-islamic-umalqura-nu-latn", { day: "numeric", month: "numeric", year: "numeric" })
      .formatToParts(shifted)
      .map((part) => [part.type, Number(part.value)]),
  );
  const month = hijriMonths[parts.month - 1];
  const number = (value: number) => new Intl.NumberFormat(tag, { useGrouping: false }).format(value);
  const hijri = month ? ` · ${number(parts.day)} ${month} ${number(parts.year)} ${hijriSuffix}` : "";
  return `${civil.charAt(0).toLocaleUpperCase(tag)}${civil.slice(1)}${hijri}`;
}
