import type { Metadata, Viewport } from "next";
import { Amiri, Inter } from "next/font/google";
import "./globals.css";
import "./mobile.css";
import "./mushaf-reader.css";
import { AuthProvider } from "../lib/auth-context";
import { I18nProvider } from "../lib/i18n-context";
import { directionFor } from "../lib/i18n";
import { Header } from "../components/Header";
import { MobileNavigation } from "../components/MobileNavigation";
import { Footer } from "../components/Footer";
import { AudioPlayerProvider } from "../lib/audio-player-context";
import { requestLocale } from "../lib/server-locale";
import { absoluteSiteUrl, createRootMetadata, SITE_NAME } from "../lib/seo";
import { serializeJsonLd } from "../lib/json-ld";
import { getPublishedSocialProfilesOrEmpty } from "../lib/public-content";

// Only Latin is preloaded; the Cyrillic, Latin Extended and other faces load
// on demand through unicode-range on the locales that need them.
const inter = Inter({
  subsets: ["latin"],
  display: "swap",
  variable: "--font-inter",
});

// Not preloaded: most routes render no Arabic, and unicode-range lets the
// browser fetch only the Amiri faces a page actually uses.
const amiri = Amiri({
  weight: ["400", "700"],
  subsets: ["arabic", "latin"],
  display: "swap",
  preload: false,
  variable: "--font-amiri",
});

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
};

export async function generateMetadata(): Promise<Metadata> {
  const locale = await requestLocale();
  return createRootMetadata(locale);
}

export default async function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const locale = await requestLocale();
  const socialProfiles = await getPublishedSocialProfilesOrEmpty();
  const organizationId = absoluteSiteUrl("/#organization");
  const websiteJson = serializeJsonLd({
    "@context": "https://schema.org",
    "@type": "WebSite",
    "@id": absoluteSiteUrl("/#website"),
    name: SITE_NAME,
    url: absoluteSiteUrl("/"),
    inLanguage: ["ru", "en", "ar", "tr"],
    publisher: { "@id": organizationId },
  });
  const organizationJson = serializeJsonLd({
    "@context": "https://schema.org",
    "@type": "Organization",
    "@id": organizationId,
    name: "IQRO",
    alternateName: "IQRO — Islamic forum",
    url: absoluteSiteUrl("/"),
    ...(socialProfiles.some((profile) => profile.include_in_seo)
      ? { sameAs: socialProfiles.filter((profile) => profile.include_in_seo).map((profile) => profile.url) }
      : {}),
  });
  return (
    <html
      lang={locale}
      dir={directionFor(locale)}
      className={`${inter.variable} ${amiri.variable}`}
      suppressHydrationWarning
    >
      <body>
        <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: websiteJson }} />
        <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: organizationJson }} />
        <I18nProvider initialLocale={locale}>
          <AuthProvider>
            <AudioPlayerProvider>
              <div className="app-container">
                <Header />
                <main>{children}</main>
                <Footer socialProfiles={socialProfiles} />
                <MobileNavigation />
              </div>
            </AudioPlayerProvider>
          </AuthProvider>
        </I18nProvider>
      </body>
    </html>
  );
}
