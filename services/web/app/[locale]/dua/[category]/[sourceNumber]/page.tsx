import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

import { DuaEntryList } from "@/components/DuaEntryList";
import { isLocale, translate, type Locale } from "@/lib/i18n";
import {
  getPublishedDuaEntryByReference,
  isDuaCollectionSlug,
  PublicContentNotFoundError,
} from "@/lib/public-content";
import { localizedPath } from "@/lib/routing";
import { createContentMetadata } from "@/lib/seo";

export const revalidate = 3_600;

type RouteParams = {
  locale: string;
  category: string;
  sourceNumber: string;
};

function parseParams(params: RouteParams): {
  locale: Locale;
  collection: string;
  sourceNumber: number;
} {
  const sourceNumber = Number(params.sourceNumber);
  if (
    !isLocale(params.locale) ||
    !isDuaCollectionSlug(params.category) ||
    !Number.isSafeInteger(sourceNumber) ||
    sourceNumber < 1 ||
    sourceNumber > 32_767
  ) {
    notFound();
  }
  return {
    locale: params.locale,
    collection: params.category,
    sourceNumber,
  };
}

async function publishedEntry(route: ReturnType<typeof parseParams>) {
  try {
    return await getPublishedDuaEntryByReference(
      route.locale,
      route.collection,
      route.sourceNumber,
    );
  } catch (error) {
    if (error instanceof PublicContentNotFoundError) notFound();
    throw error;
  }
}

export async function generateMetadata({
  params,
}: {
  params: Promise<RouteParams>;
}): Promise<Metadata> {
  const route = parseParams(await params);
  const entry = await publishedEntry(route);
  const meaning = entry.translation?.meaning_text.trim();
  return createContentMetadata(route.locale, {
    title: `${entry.category.title} · #${entry.source_number}`,
    description: meaning || entry.arabic_text,
    path: `/dua/${entry.collection}/${entry.source_number}`,
  });
}

export default async function LocalizedDuaEntryPage({
  params,
}: {
  params: Promise<RouteParams>;
}) {
  const route = parseParams(await params);
  const entry = await publishedEntry(route);

  return (
    <div className="dua-page dua-topic-page">
      <nav className="breadcrumbs" aria-label={translate(route.locale, "dua.topicBreadcrumbs")}>
        <ol>
          <li>
            <Link href={localizedPath(route.locale, "/dua")}>
              {translate(route.locale, "dua.allCategories")}
            </Link>
          </li>
          <li>
            <Link
              href={localizedPath(
                route.locale,
                `/dua/${entry.collection}/categories/${entry.category.slug}`,
              )}
            >
              {entry.category.title}
            </Link>
          </li>
          <li aria-current="page">#{entry.source_number}</li>
        </ol>
      </nav>

      <header className="surface dua-topic-hero">
        <div className="dua-topic-copy">
          <p className="eyebrow">{translate(route.locale, "dua.eyebrow")}</p>
          <h1>{entry.category.title}</h1>
          <p>#{entry.source_number}</p>
        </div>
        <Link
          href={localizedPath(
            route.locale,
            `/dua/${entry.collection}/categories/${entry.category.slug}`,
          )}
          className="btn btn-secondary dua-topic-back"
        >
          <span aria-hidden="true">←</span> {translate(route.locale, "dua.backToTopics")}
        </Link>
      </header>

      <section className="surface dua-topic-content">
        <DuaEntryList entries={[entry]} headingLevel={2} />
      </section>
    </div>
  );
}
