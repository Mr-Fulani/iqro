import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { NewsFeed } from "../../../components/announcements/NewsFeed";
import type { AnnouncementFeedPage } from "../../../lib/announcements";
import { isLocale, translate } from "../../../lib/i18n";
import { getPublishedAnnouncementFeed } from "../../../lib/public-content";
import { createPageMetadata } from "../../../lib/seo";

export async function generateMetadata({ params }: { params: Promise<{ locale: string }> }): Promise<Metadata> {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  return createPageMetadata(locale, { titleKey: "news.title", descriptionKey: "news.description", path: "/news" });
}

export default async function NewsPage({ params }: { params: Promise<{ locale: string }> }) {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  let initialPage: AnnouncementFeedPage = { next_cursor: null, results: [] };
  try {
    initialPage = await getPublishedAnnouncementFeed(locale);
  } catch (error) {
    console.error("The announcement feed is temporarily unavailable", error);
  }
  return (
    <div className="news-page">
      <section className="surface news-hero">
        <p className="eyebrow">{translate(locale, "news.eyebrow")}</p>
        <h1 className="news-title">{translate(locale, "news.title")}</h1>
        <p className="surface-subtitle">{translate(locale, "news.description")}</p>
      </section>
      <NewsFeed initialPage={initialPage} />
    </div>
  );
}
