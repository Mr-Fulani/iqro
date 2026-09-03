import type { Metadata } from "next";
import { notFound } from "next/navigation";

import { DuaCategoryPage } from "@/components/DuaCategoryPage";
import { isLocale, translate, type Locale } from "@/lib/i18n";
import {
  getPublishedDuaCategoryData,
  isDuaCategorySlug,
  isDuaCollectionSlug,
  PublicContentNotFoundError,
} from "@/lib/public-content";
import { createContentMetadata } from "@/lib/seo";

export const revalidate = 3_600;

type RouteParams = { locale: string; category: string; topic: string };

function parseParams(params: RouteParams): {
  locale: Locale;
  collection: string;
  category: string;
} {
  if (
    !isLocale(params.locale) ||
    !isDuaCollectionSlug(params.category) ||
    !isDuaCategorySlug(params.topic)
  ) {
    notFound();
  }
  return {
    locale: params.locale,
    collection: params.category,
    category: params.topic,
  };
}

async function publishedCategory(route: ReturnType<typeof parseParams>) {
  try {
    return await getPublishedDuaCategoryData(
      route.locale,
      route.category,
      route.collection,
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
  const published = await publishedCategory(route);
  return createContentMetadata(route.locale, {
    title: published.category.title,
    description: translate(route.locale, "dua.topicPageDescription", {
      topic: published.category.title,
      count: published.category.entry_count,
    }),
    path:
      `/dua/${published.category.collection}/categories/${published.category.slug}`,
  });
}

export default async function LocalizedDuaCategoryPage({
  params,
}: {
  params: Promise<RouteParams>;
}) {
  const route = parseParams(await params);
  const published = await publishedCategory(route);
  return <DuaCategoryPage locale={route.locale} published={published} />;
}
