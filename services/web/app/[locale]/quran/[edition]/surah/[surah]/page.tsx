import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { isLocale, localeTag, translate, type Locale } from "@/lib/i18n";
import {
  getPublishedAyahs,
  getPublishedEdition,
  getPublishedSurah,
  isEditionCode,
  PublicContentNotFoundError,
} from "@/lib/public-content";
import { editionName, quranAyahPath, quranSurahPath, surahName } from "@/lib/quran-content";
import { localizedPath } from "@/lib/routing";
import { absoluteSiteUrl, createContentMetadata } from "@/lib/seo";

export const revalidate = 3_600;

type RouteParams = {
  locale: string;
  edition: string;
  surah: string;
};

function parseParams(params: RouteParams): { locale: Locale; edition: string; surah: number } {
  const surah = Number(params.surah);
  if (
    !isLocale(params.locale) ||
    !isEditionCode(params.edition) ||
    !Number.isInteger(surah) ||
    surah < 1 ||
    surah > 114
  ) {
    notFound();
  }
  return { locale: params.locale, edition: params.edition, surah };
}

async function publishedSurah(edition: string, surah: number) {
  try {
    return await Promise.all([
      getPublishedEdition(edition),
      getPublishedSurah(edition, surah),
      getPublishedAyahs(edition, surah),
    ]);
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
  const [edition, surah] = await publishedSurah(route.edition, route.surah);
  const name = surahName(surah, route.locale);
  const publishedEditionName = editionName(edition, route.locale);

  return createContentMetadata(route.locale, {
    title: translate(route.locale, "quran.deep.surahTitle", {
      surah: route.surah,
      name,
    }),
    description: translate(route.locale, "quran.deep.surahDescription", {
      surah: route.surah,
      name,
      count: surah.ayah_count,
      edition: publishedEditionName,
    }),
    path: quranSurahPath(route.edition, route.surah),
  });
}

export default async function PublishedSurahPage({
  params,
}: {
  params: Promise<RouteParams>;
}) {
  const route = parseParams(await params);
  const [edition, surah, ayahs] = await publishedSurah(route.edition, route.surah);
  const name = surahName(surah, route.locale);
  const contentPath = quranSurahPath(route.edition, route.surah);
  const localizedContentPath = localizedPath(route.locale, contentPath);
  const numberFormatter = new Intl.NumberFormat(localeTag(route.locale));
  const title = translate(route.locale, "quran.deep.surahTitle", {
    surah: numberFormatter.format(route.surah),
    name,
  });
  const description = translate(route.locale, "quran.deep.surahDescription", {
    surah: numberFormatter.format(route.surah),
    name,
    count: numberFormatter.format(surah.ayah_count),
    edition: editionName(edition, route.locale),
  });
  const breadcrumbJson = JSON.stringify({
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: [
      {
        "@type": "ListItem",
        position: 1,
        name: translate(route.locale, "nav.home"),
        item: absoluteSiteUrl(localizedPath(route.locale, "/")),
      },
      {
        "@type": "ListItem",
        position: 2,
        name: translate(route.locale, "nav.quran"),
        item: absoluteSiteUrl(localizedPath(route.locale, "/quran")),
      },
      {
        "@type": "ListItem",
        position: 3,
        name: title,
        item: absoluteSiteUrl(localizedContentPath),
      },
    ],
  }).replace(/</g, "\\u003c");

  return (
    <div className="seo-quran-page">
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: breadcrumbJson }} />
      <nav className="breadcrumbs" aria-label={translate(route.locale, "quran.deep.breadcrumbs")}>
        <ol>
          <li><Link href={localizedPath(route.locale, "/")}>{translate(route.locale, "nav.home")}</Link></li>
          <li><Link href={localizedPath(route.locale, "/quran")}>{translate(route.locale, "nav.quran")}</Link></li>
          <li aria-current="page">{name}</li>
        </ol>
      </nav>

      <header className="surface seo-quran-hero">
        <div>
          <p className="eyebrow">{surah.name_ar}</p>
          <h1>{title}</h1>
          <p>{description}</p>
          <p className="seo-content-version">
            {translate(route.locale, "quran.deep.editionVersion", {
              edition: editionName(edition, route.locale),
              version: edition.active_version?.version || "—",
            })}
          </p>
        </div>
        <Link
          href={localizedPath(route.locale, `/quran?surah=${route.surah}`)}
          className="btn btn-primary"
        >
          {translate(route.locale, "quran.deep.openReader")}
        </Link>
      </header>

      <section className="seo-ayah-section" aria-labelledby="surah-ayahs-title">
        <div className="surface-head">
          <h2 id="surah-ayahs-title" className="surface-title">
            {translate(route.locale, "quran.deep.allAyahs")}
          </h2>
          <span className="status-chip">
            {translate(route.locale, "quran.ayahsShort", {
              count: numberFormatter.format(ayahs.length),
            })}
          </span>
        </div>
        <div className="seo-ayah-list">
          {ayahs.map((ayah) => (
            <article className="ayah-card" id={`ayah-${ayah.number}`} key={ayah.id}>
              <div className="ayah-header">
                <Link
                  className="seo-ayah-reference"
                  href={localizedPath(
                    route.locale,
                    quranAyahPath(route.edition, route.surah, ayah.number),
                  )}
                >
                  {translate(route.locale, "common.ayah", {
                    ayah: numberFormatter.format(ayah.number),
                  })}
                </Link>
                <span className="surface-subtitle">
                  {translate(route.locale, "quran.ayahMeta", {
                    ayah: numberFormatter.format(ayah.number),
                    juz: numberFormatter.format(ayah.juz_number),
                  })}
                </span>
              </div>
              <p className="quran-arabic-text" lang="ar" dir="rtl">{ayah.text_uthmani}</p>
            </article>
          ))}
        </div>
      </section>
    </div>
  );
}
