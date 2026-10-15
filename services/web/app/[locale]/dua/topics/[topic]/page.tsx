import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

import { DuaEntrySummaryList } from "@/components/DuaEntrySummaryList";
import { DuaTopicSelector } from "@/components/DuaTopicSelector";
import { DuaTopicIcon } from "@/components/DuaTopicIcon";
import { isLocale, translate, type Locale } from "@/lib/i18n";
import { duaTopics, topicCategories, topicEntries, type DuaTopic } from "@/lib/dua-topics";
import { getPublishedDuaCategoryData, getPublishedDuaInitialData } from "@/lib/public-content";
import { localizedPath } from "@/lib/routing";
import { createContentMetadata } from "@/lib/seo";

export const revalidate = 3_600;

// Published content is not prerendered at build time; each path is rendered on
// its first request and then served through ISR.
export function generateStaticParams() {
  return [];
}
type Params = { locale: string; topic: string };

function resolve(params: Params): { locale: Locale; topic: DuaTopic } {
  if (!isLocale(params.locale)) notFound();
  const topic = duaTopics.find((item) => item.id === params.topic);
  if (!topic) notFound();
  return { locale: params.locale, topic };
}

export async function generateMetadata({ params }: { params: Promise<Params> }): Promise<Metadata> {
  const { locale, topic } = resolve(await params);
  return createContentMetadata(locale, {
    title: topic.title[locale],
    description: topic.description[locale],
    path: `/dua/topics/${topic.id}`,
  });
}

export default async function DuaThematicPage({ params }: { params: Promise<Params> }) {
  const { locale, topic } = resolve(await params);
  const catalog = await getPublishedDuaInitialData(locale);
  const categories = topicCategories(topic, catalog.categories);
  if (!categories.length) notFound();
  // Daily adhkar shortcuts open the full source chapter before filtering. This
  // fetcher follows every cursor page, so none of its 24 records are truncated.
  const published = await Promise.all(categories
    .sort((left, right) => left.source_number - right.source_number)
    .map((category) => getPublishedDuaCategoryData(locale, category.slug, topic.collection)));
  const entries = topicEntries(topic, published.flatMap((chapter) => chapter.entries));
  return (
    <div className="dua-page dua-topic-page">
      <nav className="breadcrumbs" aria-label={translate(locale, "dua.topicBreadcrumbs")}>
        <ol>
          <li><Link href={localizedPath(locale, "/dua")}>{translate(locale, "dua.allCategories")}</Link></li>
          <li aria-current="page">{topic.title[locale]}</li>
        </ol>
      </nav>
      <header className="surface dua-topic-hero">
        <DuaTopicIcon sourceNumber={topic.chapter_numbers[0] || 0} slug={topic.id} />
        <div className="dua-topic-copy">
          <h1>{topic.title[locale]}</h1>
          <p>{topic.description[locale]}</p>
        </div>
        <Link href={localizedPath(locale, "/dua")} className="btn btn-secondary dua-topic-back">
          {translate(locale, "dua.backToTopics")}
        </Link>
      </header>
      <section className="surface dua-topic-content">
        <DuaTopicSelector value={topic.id} />
        <DuaEntrySummaryList entries={entries} locale={locale} />
      </section>
    </div>
  );
}
