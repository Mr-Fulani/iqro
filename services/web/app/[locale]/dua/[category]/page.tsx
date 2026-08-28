import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { DuaEntryList } from "@/components/DuaEntryList";
import { DuaTopicIcon } from "@/components/DuaTopicIcon";
import { isLocale, localeTag, translate, type Locale } from "@/lib/i18n";
import {
  getPublishedDuaCategoryData,
  isDuaCategorySlug,
  PublicContentNotFoundError,
} from "@/lib/public-content";
import { localizedPath } from "@/lib/routing";
import { absoluteSiteUrl, createContentMetadata } from "@/lib/seo";

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
    path: `/dua/${published.category.slug}`,
  });
}

export default async function LocalizedDuaCategoryPage({
  params,
}: {
  params: Promise<RouteParams>;
}) {
  const route = parseParams(await params);
  const published = await publishedCategory(route.locale, route.category);
  const numbers = new Intl.NumberFormat(localeTag(route.locale));
  const topicPath = `/dua/${published.category.slug}`;
  const breadcrumbJson = JSON.stringify({
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: [
      {
        "@type": "ListItem",
        position: 1,
        name: translate(route.locale, "dua.title"),
        item: absoluteSiteUrl(localizedPath(route.locale, "/dua")),
      },
      {
        "@type": "ListItem",
        position: 2,
        name: published.category.title,
        item: absoluteSiteUrl(localizedPath(route.locale, topicPath)),
      },
    ],
  }).replace(/</g, "\\u003c");

  return (
    <div className="dua-page dua-topic-page">
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: breadcrumbJson }} />
      <nav className="breadcrumbs" aria-label={translate(route.locale, "dua.topicBreadcrumbs")}>
        <ol>
          <li>
            <Link href={localizedPath(route.locale, "/dua")}>
              {translate(route.locale, "dua.allCategories")}
            </Link>
          </li>
          <li aria-current="page">{published.category.title}</li>
        </ol>
      </nav>

      <header className="surface dua-topic-hero">
        <DuaTopicIcon
          sourceNumber={published.category.source_number}
          slug={published.category.slug}
        />
        <div className="dua-topic-copy">
          <p className="eyebrow">{translate(route.locale, "dua.topicEyebrow")}</p>
          <h1>{published.category.title}</h1>
          <p>
            {translate(route.locale, "dua.topicPageDescription", {
              topic: published.category.title,
              count: numbers.format(published.category.entry_count),
            })}
          </p>
        </div>
        <Link href={localizedPath(route.locale, "/dua")} className="btn btn-secondary dua-topic-back">
          <span aria-hidden="true">←</span> {translate(route.locale, "dua.backToTopics")}
        </Link>
      </header>

      <section className="surface dua-topic-content">
        <div className="surface-head">
          <div>
            <p className="eyebrow">{translate(route.locale, "dua.eyebrow")}</p>
            <h2 className="surface-title">{translate(route.locale, "dua.topicEntriesTitle")}</h2>
          </div>
          <span className="status-chip ok">
            {translate(route.locale, "dua.categoryEntryCount", {
              count: numbers.format(published.entries.length),
            })}
          </span>
        </div>
        <DuaEntryList entries={published.entries} headingLevel={3} />
        {published.collection?.source ? (
          <p className="dua-source-lead">
            {translate(route.locale, "dua.sourceEdition")}: {published.collection.source.title}.{" "}
            <a href={published.collection.source.source_url} target="_blank" rel="noreferrer">
              {translate(route.locale, "dua.openSource")} ↗
            </a>
          </p>
        ) : null}
      </section>
    </div>
  );
}
