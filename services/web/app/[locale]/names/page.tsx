import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { connection } from "next/server";

import { NamesWheel } from "@/components/names/NamesWheel";
import { isLocale, type Locale } from "@/lib/i18n";
import { NAMES_COLLECTION_SLUG, type NamesDocument } from "@/lib/names";
import { getPublishedNames, PublicContentNotFoundError } from "@/lib/public-content";
import { createPageMetadata } from "@/lib/seo";
import { translate } from "@/lib/translate";
import "./names.css";

export const revalidate = 3_600;

// Published content is not prerendered at build time; each path is rendered on
// its first request and then served through ISR.
export function generateStaticParams() {
  return [];
}

type RouteParams = { locale: string };

function localeParam(value: string): Locale {
  if (!isLocale(value)) notFound();
  return value;
}

/** The published list; null until the owner publishes the first version. */
async function publishedNames(locale: Locale): Promise<NamesDocument | null> {
  try {
    return await getPublishedNames(locale, NAMES_COLLECTION_SLUG);
  } catch (error) {
    if (error instanceof PublicContentNotFoundError) return null;
    throw error;
  }
}

export async function generateMetadata({ params }: { params: Promise<RouteParams> }): Promise<Metadata> {
  const locale = localeParam((await params).locale);
  await connection();
  const published = await publishedNames(locale).catch(() => null);
  return createPageMetadata(locale, {
    titleKey: "names.title",
    descriptionKey: "names.description",
    path: "/names",
    index: published !== null,
  });
}

export default async function NamesPage({ params }: { params: Promise<RouteParams> }) {
  await connection();
  const locale = localeParam((await params).locale);
  const document = await publishedNames(locale);

  return (
    <div className="names-page">
      <header className="names-header">
        <h1>{translate(locale, "names.title")}</h1>
        {document && <p>{translate(locale, "names.intro")}</p>}
      </header>
      {document ? (
        <NamesWheel document={document} />
      ) : (
        <section className="names-soon" data-testid="names-soon">
          <h2>{translate(locale, "names.soonTitle")}</h2>
          <p>{translate(locale, "names.soonText")}</p>
        </section>
      )}
    </div>
  );
}
