import type { NextRequest } from "next/server";
import { NextResponse } from "next/server";

const LOCALE_VALUES = ["ru", "en", "ar", "tr"] as const;
const LOCALES = new Set<string>(LOCALE_VALUES);
const LOCALE_COOKIE_NAME = "quran_locale_v1";

function preferredLocale(request: NextRequest): string {
  const storedLocale = request.cookies.get(LOCALE_COOKIE_NAME)?.value;
  if (storedLocale && LOCALES.has(storedLocale)) return storedLocale;

  const acceptLanguage = request.headers.get("accept-language") || "";
  for (const item of acceptLanguage.split(",")) {
    const language = item.trim().split(";")[0]?.toLowerCase().split("-")[0];
    if (language && LOCALES.has(language)) return language;
  }
  return "ru";
}

export function proxy(request: NextRequest) {
  const locale = request.nextUrl.pathname.split("/")[1];
  if (!LOCALES.has(locale)) {
    const redirectUrl = request.nextUrl.clone();
    const selectedLocale = preferredLocale(request);
    redirectUrl.pathname = request.nextUrl.pathname === "/"
      ? `/${selectedLocale}`
      : `/${selectedLocale}${request.nextUrl.pathname}`;
    return NextResponse.redirect(redirectUrl, 307);
  }

  const requestHeaders = new Headers(request.headers);
  requestHeaders.set("x-quran-locale", locale);

  const response = NextResponse.next({
    request: { headers: requestHeaders },
  });
  response.cookies.set(LOCALE_COOKIE_NAME, locale, {
    path: "/",
    maxAge: 31_536_000,
    sameSite: "lax",
  });
  return response;
}

export const config = {
  matcher: [
    "/",
    "/quran/:path*",
    "/audio/:path*",
    "/prayer/:path*",
    "/profile/:path*",
    "/login/:path*",
    "/register/:path*",
    "/ru/:path*",
    "/en/:path*",
    "/ar/:path*",
    "/tr/:path*",
  ],
};
