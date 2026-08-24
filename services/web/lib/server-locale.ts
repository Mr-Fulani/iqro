import "server-only";

import { cookies, headers } from "next/headers";
import {
  isLocale,
  LOCALE_COOKIE_NAME,
  localeFromAcceptLanguage,
  type Locale,
} from "./i18n";

export async function requestLocale(): Promise<Locale> {
  const requestHeaders = await headers();
  const routedLocale = requestHeaders.get("x-quran-locale");
  if (isLocale(routedLocale)) return routedLocale;

  const storedLocale = (await cookies()).get(LOCALE_COOKIE_NAME)?.value;
  if (isLocale(storedLocale)) return storedLocale;

  return localeFromAcceptLanguage(requestHeaders.get("accept-language"));
}
