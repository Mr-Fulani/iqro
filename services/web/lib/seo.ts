import type { Metadata } from "next";
import {
  type Locale,
  type MessageKey,
  SUPPORTED_LOCALES,
  translate,
} from "./i18n";
import { localizedAlternates, localizedPath } from "./routing";

export const SITE_NAME = "Quran Platform";
export const LOCAL_SITE_URL = "http://localhost:3000";
export const PUBLIC_INDEXABLE_PATHS = [
  "/",
  "/quran",
  "/audio",
  "/prayer",
  "/legal",
  "/privacy",
  "/terms",
  "/cookies",
  "/data-rights",
  "/providers",
  "/security",
  "/contacts",
  "/sources",
] as const;

const OPEN_GRAPH_LOCALES: Record<Locale, string> = {
  ru: "ru_RU",
  en: "en_US",
  ar: "ar",
  tr: "tr_TR",
};

type PageMetadataOptions = {
  titleKey: MessageKey;
  descriptionKey: MessageKey;
  path: string;
  index?: boolean;
};

type ContentMetadataOptions = {
  title: string;
  description: string;
  path: string;
  index?: boolean;
};

export function siteUrl(): URL {
  const configuredUrl = process.env.SITE_URL?.trim() || LOCAL_SITE_URL;
  const url = new URL(configuredUrl);

  if (!(["http:", "https:"] as const).includes(url.protocol as "http:" | "https:")) {
    throw new Error("SITE_URL must use http or https");
  }
  if (url.username || url.password || url.search || url.hash || url.pathname !== "/") {
    throw new Error("SITE_URL must be an absolute origin without credentials, path, query, or hash");
  }

  return url;
}

export function absoluteSiteUrl(path = "/"): string {
  return new URL(path, siteUrl()).toString();
}

export function createRootMetadata(locale: Locale): Metadata {
  const title = translate(locale, "meta.title");
  const description = translate(locale, "meta.description");
  const canonical = localizedPath(locale, "/");

  return {
    metadataBase: siteUrl(),
    applicationName: SITE_NAME,
    title: {
      default: title,
      template: `%s | ${SITE_NAME}`,
    },
    description,
    alternates: {
      canonical,
      languages: localizedAlternates("/"),
    },
    openGraph: {
      type: "website",
      url: canonical,
      siteName: SITE_NAME,
      title,
      description,
      locale: OPEN_GRAPH_LOCALES[locale],
      alternateLocale: SUPPORTED_LOCALES
        .filter((item) => item !== locale)
        .map((item) => OPEN_GRAPH_LOCALES[item]),
      images: [
        {
          url: "/opengraph-image",
          width: 1200,
          height: 630,
          alt: SITE_NAME,
        },
      ],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
      images: ["/opengraph-image"],
    },
    manifest: "/manifest.webmanifest",
    formatDetection: {
      email: false,
      address: false,
      telephone: false,
    },
    category: "religion",
  };
}

export function createPageMetadata(
  locale: Locale,
  { titleKey, descriptionKey, path, index = true }: PageMetadataOptions,
): Metadata {
  return createContentMetadata(locale, {
    title: translate(locale, titleKey),
    description: translate(locale, descriptionKey),
    path,
    index,
  });
}

export function createContentMetadata(
  locale: Locale,
  { title, description, path, index = true }: ContentMetadataOptions,
): Metadata {
  const canonical = localizedPath(locale, path);

  return {
    title,
    description,
    alternates: {
      canonical,
      languages: localizedAlternates(path),
    },
    robots: index
      ? { index: true, follow: true }
      : {
          index: false,
          follow: false,
          noarchive: true,
          nosnippet: true,
          noimageindex: true,
          googleBot: {
            index: false,
            follow: false,
            noimageindex: true,
          },
        },
    openGraph: index
      ? {
          type: "website",
          url: canonical,
          siteName: SITE_NAME,
          title,
          description,
          locale: OPEN_GRAPH_LOCALES[locale],
          alternateLocale: SUPPORTED_LOCALES
            .filter((item) => item !== locale)
            .map((item) => OPEN_GRAPH_LOCALES[item]),
          images: [
            {
              url: "/opengraph-image",
              width: 1200,
              height: 630,
              alt: SITE_NAME,
            },
          ],
        }
      : undefined,
    twitter: index
      ? {
          card: "summary_large_image",
          title,
          description,
          images: ["/opengraph-image"],
        }
      : undefined,
  };
}
