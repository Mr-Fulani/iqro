import type { Metadata } from "next";
import "./globals.css";
import { AuthProvider } from "../lib/auth-context";
import { I18nProvider } from "../lib/i18n-context";
import { directionFor } from "../lib/i18n";
import { Header } from "../components/Header";
import { Footer } from "../components/Footer";
import { AudioPlayerProvider } from "../lib/audio-player-context";
import { requestLocale } from "../lib/server-locale";
import { absoluteSiteUrl, createRootMetadata, SITE_NAME } from "../lib/seo";
import { serializeJsonLd } from "../lib/json-ld";
import { getPublishedSocialProfilesOrEmpty } from "../lib/public-content";

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
    <html lang={locale} dir={directionFor(locale)} suppressHydrationWarning>
      <head>
        <link rel="preconnect" href="https://fonts.googleapis.com" />
        <link rel="preconnect" href="https://fonts.gstatic.com" crossOrigin="anonymous" />
      </head>
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
              </div>
            </AudioPlayerProvider>
          </AuthProvider>
        </I18nProvider>
      </body>
    </html>
  );
}
