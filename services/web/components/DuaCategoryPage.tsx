import { DuaChapterBanner, DuaTopBar } from "@/components/DuaChrome";
import { DuaFeed } from "@/components/DuaFeed";
import { duaDisplayTitle } from "@/lib/dua-share";
import { duaTopics, topicCategories } from "@/lib/dua-topics";
import { type Locale } from "@/lib/i18n";
import { translate, translatorFor } from "@/lib/translate";
import { getPublishedDuaInitialData, type PublishedDuaCategoryData } from "@/lib/public-content";
import { localizedPath } from "@/lib/routing";
import { absoluteSiteUrl } from "@/lib/seo";

/**
 * A chapter as the app shows it: «Глава N» over the collection, the chapter's
 * title as a ribbon and all its du'a as cards. «Back» leads to the topic that
 * lists this chapter, or to the catalog.
 */
export async function DuaCategoryPage({
  locale,
  published,
}: {
  locale: Locale;
  published: PublishedDuaCategoryData;
}) {
  const { category } = published;
  const title = duaDisplayTitle(category.title, locale);
  const chapterPath = `/dua/${category.collection}/categories/${category.slug}`;
  const catalog = await getPublishedDuaInitialData(locale);
  const parent = duaTopics.find((topic) => !topic.entry_numbers
    && topicCategories(topic, [category]).length > 0
    && topicCategories(topic, catalog.categories).length > 1);
  const breadcrumbJson = JSON.stringify({
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: [
      {
        "@type": "ListItem",
        position: 1,
        name: translate(locale, "dua.title"),
        item: absoluteSiteUrl(localizedPath(locale, "/dua")),
      },
      {
        "@type": "ListItem",
        position: 2,
        name: title,
        item: absoluteSiteUrl(localizedPath(locale, chapterPath)),
      },
    ],
  }).replace(/</g, "\\u003c");

  return (
    <div className="dua-page">
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: breadcrumbJson }} />
      <DuaTopBar
        locale={locale}
        t={translatorFor(locale)}
        title={translate(locale, "dua.chapterNumber", { number: category.source_number })}
        subtitle={category.collection_title || category.collection}
        backHref={parent ? `/dua/topics/${parent.id}` : "/dua"}
        titleIsHeading={false}
      />
      <DuaChapterBanner title={title} heading />
      <DuaFeed entries={published.entries} showPositions sideList />
    </div>
  );
}
