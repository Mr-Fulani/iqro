import type { Metadata, Viewport } from "next";
import { notFound } from "next/navigation";
import { Amiri, Inter } from "next/font/google";
import localFont from "next/font/local";
import "../globals.css";
import "../mobile.css";
import "../mushaf-reader.css";
import { AuthProvider } from "../../lib/auth-context";
import { I18nProvider } from "../../lib/i18n-context";
import { directionFor, isLocale, SUPPORTED_LOCALES } from "../../lib/i18n";
import { Header } from "../../components/Header";
import { MobileNavigation } from "../../components/MobileNavigation";
import { Footer } from "../../components/Footer";
import { AudioPlayerProvider } from "../../lib/audio-player-context";
import { absoluteSiteUrl, createRootMetadata, SITE_NAME } from "../../lib/seo";
import { serializeJsonLd } from "../../lib/json-ld";
import { getPublishedSocialProfilesOrEmpty } from "../../lib/public-content";

// Only Latin is preloaded; the Cyrillic, Latin Extended and other faces load
// on demand through unicode-range on the locales that need them.
const inter = Inter({
  subsets: ["latin"],
  display: "swap",
  variable: "--font-inter",
});

// Ğ ğ İ Ş ş are the only Turkish letters outside Inter's Latin face. This
// 3 KB cut of the same Inter (wght 100-900) covers them, so Turkish pages do
// not download the 85 KB Latin Extended face for five glyphs.
const interTurkish = localFont({
  src: "../fonts/inter-turkish.woff2",
  weight: "100 900",
  display: "swap",
  preload: false,
  adjustFontFallback: false,
  variable: "--font-inter-turkish",
  declarations: [{ prop: "unicode-range", value: "U+011E-011F, U+0130, U+015E-015F" }],
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

type Props = Readonly<{
  children: React.ReactNode;
  params: Promise<{ locale: string }>;
}>;

// The locale comes from the URL rather than request headers or cookies, so every
// page under this root layout can be prerendered and served through ISR.
export function generateStaticParams() {
  return SUPPORTED_LOCALES.map((locale) => ({ locale }));
}

export async function generateMetadata({ params }: Omit<Props, "children">): Promise<Metadata> {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  return createRootMetadata(locale);
}

export default async function RootLayout({ children, params }: Props) {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
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
      className={`${interTurkish.variable} ${inter.variable} ${amiri.variable}`}
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
