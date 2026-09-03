import type { Metadata } from "next";
import { notFound } from "next/navigation";

import { DuaCategoryPage } from "@/components/DuaCategoryPage";
import { isLocale, translate, type Locale } from "@/lib/i18n";
import {
  getPublishedDuaCategoryData,
  isDuaCategorySlug,
  PublicContentNotFoundError,
} from "@/lib/public-content";
import { createContentMetadata } from "@/lib/seo";

export const revalidate = 3_600;

type RouteParams = { locale: string; category: string };

function parseParams(params: RouteParams): { locale: Locale; category: string } {
  if (!isLocale(params.locale) || !isDuaCategorySlug(params.category)) notFound();
  return { locale: params.locale, category: params.category };
}

async function publishedCategory(locale: Locale, category: string) {
  try {
    return await getPublishedDuaCategoryData(locale, category);
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
  const published = await publishedCategory(route.locale, route.category);
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

export default async function LegacyLocalizedDuaCategoryPage({
  params,
}: {
  params: Promise<RouteParams>;
}) {
  const route = parseParams(await params);
  const published = await publishedCategory(route.locale, route.category);
  return <DuaCategoryPage locale={route.locale} published={published} />;
}
