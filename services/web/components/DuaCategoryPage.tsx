import Link from "next/link";

import { DuaEntryList } from "@/components/DuaEntryList";
import { DuaTopicIcon } from "@/components/DuaTopicIcon";
import { localeTag, translate, type Locale } from "@/lib/i18n";
import type { PublishedDuaCategoryData } from "@/lib/public-content";
import { localizedPath } from "@/lib/routing";
import { absoluteSiteUrl } from "@/lib/seo";

export function DuaCategoryPage({
  locale,
  published,
}: {
  locale: Locale;
  published: PublishedDuaCategoryData;
}) {
  const numbers = new Intl.NumberFormat(localeTag(locale));
  const topicPath =
    `/dua/${published.category.collection}/categories/${published.category.slug}`;
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
        name: published.category.title,
        item: absoluteSiteUrl(localizedPath(locale, topicPath)),
      },
    ],
  }).replace(/</g, "\\u003c");

  return (
    <div className="dua-page dua-topic-page">
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: breadcrumbJson }} />
      <nav className="breadcrumbs" aria-label={translate(locale, "dua.topicBreadcrumbs")}>
        <ol>
          <li>
            <Link href={localizedPath(locale, "/dua")}>
              {translate(locale, "dua.allCategories")}
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
          <p className="eyebrow">{translate(locale, "dua.topicEyebrow")}</p>
          <h1>{published.category.title}</h1>
          <p>
            {translate(locale, "dua.topicPageDescription", {
              topic: published.category.title,
              count: numbers.format(published.category.entry_count),
            })}
          </p>
        </div>
        <Link href={localizedPath(locale, "/dua")} className="btn btn-secondary dua-topic-back">
          <span aria-hidden="true">←</span> {translate(locale, "dua.backToTopics")}
        </Link>
      </header>

      <section className="surface dua-topic-content">
        <div className="surface-head">
          <div>
            <p className="eyebrow">{translate(locale, "dua.eyebrow")}</p>
            <h2 className="surface-title">{translate(locale, "dua.topicEntriesTitle")}</h2>
          </div>
          <span className="status-chip ok">
            {translate(locale, "dua.categoryEntryCount", {
              count: numbers.format(published.entries.length),
            })}
          </span>
        </div>
        <DuaEntryList entries={published.entries} headingLevel={3} />
        {published.collection?.source ? (
          <p className="dua-source-lead">
            {translate(locale, "dua.sourceEdition")}: {published.collection.source.title}.{" "}
            <a href={published.collection.source.source_url} target="_blank" rel="noreferrer">
              {translate(locale, "dua.openSource")} ↗
            </a>
          </p>
        ) : null}
      </section>
    </div>
  );
}
