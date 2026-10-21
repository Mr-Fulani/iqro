import type { Metadata } from "next";
import { notFound } from "next/navigation";

import { DuaChapterBanner, DuaChapterRow, DuaTopBar } from "@/components/DuaChrome";
import { DuaFeed } from "@/components/DuaFeed";
import { isLocale, type Locale } from "@/lib/i18n";
import { duaDisplayTitle } from "@/lib/dua-share";
import { duaTopics, topicCategories, topicEntries, type DuaTopic } from "@/lib/dua-topics";
import { getPublishedDuaCategoryData, getPublishedDuaInitialData } from "@/lib/public-content";
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

/**
 * A topic as the app opens it: a topic made of several chapters lists them
 * first; a topic of one chapter, or a chosen part of one (morning, evening),
 * is read at once.
 */
export default async function DuaThematicPage({ params }: { params: Promise<Params> }) {
  const { locale, topic } = resolve(await params);
  const catalog = await getPublishedDuaInitialData(locale);
  const chapters = topicCategories(topic, catalog.categories)
    .sort((left, right) => left.source_number - right.source_number);
  if (!chapters.length) notFound();

  if (!topic.entry_numbers && chapters.length > 1) {
    return (
      <div className="dua-page">
        <DuaTopBar
          locale={locale}
          title={topic.title[locale]}
          subtitle={topic.description[locale]}
          backHref="/dua"
        />
        <div className="dua-chapter-list">
          {chapters.map((chapter) => <DuaChapterRow key={chapter.id} chapter={chapter} locale={locale} />)}
        </div>
      </div>
    );
  }

  // Daily adhkar shortcuts open the full source chapter before filtering. This
  // fetcher follows every cursor page, so none of its 24 records are truncated.
  const published = await Promise.all(chapters.map((category) =>
    getPublishedDuaCategoryData(locale, category.slug, topic.collection)));
  const entries = topicEntries(topic, published.flatMap((chapter) => chapter.entries));
  // One chapter: its own title, as in the book; a part of one or several
  // chapters: what the topic gathers.
  const banner = chapters.length === 1
    ? duaDisplayTitle(chapters[0].title, locale)
    : topic.description[locale];
  return (
    <div className="dua-page">
      <DuaTopBar locale={locale} title={topic.title[locale]} backHref="/dua" />
      <DuaChapterBanner title={banner} />
      <DuaFeed entries={entries} showPositions sideList />
    </div>
  );
}
