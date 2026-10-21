import type { Metadata } from "next";
import { notFound } from "next/navigation";

import { DuaChapterBanner, DuaTopBar } from "@/components/DuaChrome";
import { DuaFeed } from "@/components/DuaFeed";
import { duaDisplayTitle, duaShareTitle } from "@/lib/dua-share";
import { isLocale, translate, type Locale } from "@/lib/i18n";
import {
  getPublishedDuaEntryByReference,
  isDuaCollectionSlug,
  PublicContentNotFoundError,
} from "@/lib/public-content";
import { createContentMetadata } from "@/lib/seo";

export const revalidate = 3_600;

// Published content is not prerendered at build time; each path is rendered on
// its first request and then served through ISR.
export function generateStaticParams() {
  return [];
}

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
    title: duaShareTitle(entry, route.locale),
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
  const title = duaDisplayTitle(entry.category.title, route.locale);

  // The app's du'a screen: «Ду’а» with the way back to the chapter, the
  // chapter's title as a ribbon and the du'a as a card.
  return (
    <div className="dua-page">
      <DuaTopBar
        locale={route.locale}
        title={translate(route.locale, "dua.title")}
        backHref={`/dua/${entry.collection}/categories/${entry.category.slug}`}
        titleIsHeading={false}
      />
      <DuaChapterBanner title={title} heading />
      <DuaFeed entries={[entry]} />
    </div>
  );
}
