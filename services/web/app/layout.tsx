import type { Metadata } from "next";
import { cookies, headers } from "next/headers";
import "./globals.css";
import { AuthProvider } from "../lib/auth-context";
import { I18nProvider } from "../lib/i18n-context";
import {
  directionFor,
  isLocale,
  LOCALE_COOKIE_NAME,
  localeFromAcceptLanguage,
  translate,
} from "../lib/i18n";
import { Header } from "../components/Header";
import { Footer } from "../components/Footer";
import { AudioPlayerProvider } from "../lib/audio-player-context";

async function requestLocale() {
  const stored = (await cookies()).get(LOCALE_COOKIE_NAME)?.value;
  if (isLocale(stored)) return stored;
  return localeFromAcceptLanguage((await headers()).get("accept-language"));
}

export async function generateMetadata(): Promise<Metadata> {
  const locale = await requestLocale();
  return {
    title: translate(locale, "meta.title"),
    description: translate(locale, "meta.description"),
  };
}

export default async function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const locale = await requestLocale();
  return (
    <html lang={locale} dir={directionFor(locale)} suppressHydrationWarning>
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
      </head>
      <body>
        <I18nProvider initialLocale={locale}>
          <AuthProvider>
            <AudioPlayerProvider>
              <div className="app-container">
                <Header />
                <main>{children}</main>
                <Footer />
              </div>
            </AudioPlayerProvider>
          </AuthProvider>
        </I18nProvider>
      </body>
    </html>
  );
}
