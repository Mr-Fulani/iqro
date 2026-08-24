import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { isLocale, localeTag, translate, type Locale } from "@/lib/i18n";
import {
  getPublishedAyah,
  getPublishedEdition,
  getPublishedSurah,
  isEditionCode,
  PublicContentNotFoundError,
} from "@/lib/public-content";
import { editionName, quranAyahPath, quranSurahPath, surahName } from "@/lib/quran-content";
import { localizedPath } from "@/lib/routing";
import { absoluteSiteUrl, createContentMetadata } from "@/lib/seo";

export const revalidate = 3_600;

export function generateStaticParams() {
  return [];
}

type RouteParams = {
  locale: string;
  edition: string;
  surah: string;
  ayah: string;
};

function parseParams(params: RouteParams): {
  locale: Locale;
  edition: string;
  surah: number;
  ayah: number;
} {
  const surah = Number(params.surah);
  const ayah = Number(params.ayah);
  if (
    !isLocale(params.locale) ||
    !isEditionCode(params.edition) ||
    !Number.isInteger(surah) ||
    surah < 1 ||
    surah > 114 ||
    !Number.isInteger(ayah) ||
    ayah < 1 ||
    ayah > 286
  ) {
    notFound();
  }
  return { locale: params.locale, edition: params.edition, surah, ayah };
}

async function publishedAyah(edition: string, surah: number, ayah: number) {
  try {
    return await Promise.all([
      getPublishedEdition(edition),
      getPublishedSurah(edition, surah),
      getPublishedAyah(edition, surah, ayah),
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
  const [edition, surah] = await publishedAyah(route.edition, route.surah, route.ayah);
  const name = surahName(surah, route.locale);

  return createContentMetadata(route.locale, {
    title: translate(route.locale, "quran.deep.ayahTitle", {
      surah: route.surah,
      ayah: route.ayah,
      name,
    }),
    description: translate(route.locale, "quran.deep.ayahDescription", {
      surah: route.surah,
      ayah: route.ayah,
      name,
      edition: editionName(edition, route.locale),
    }),
    path: quranAyahPath(route.edition, route.surah, route.ayah),
  });
}

export default async function PublishedAyahPage({
  params,
}: {
  params: Promise<RouteParams>;
}) {
  const route = parseParams(await params);
  const [edition, surah, ayah] = await publishedAyah(
    route.edition,
    route.surah,
    route.ayah,
  );
  const name = surahName(surah, route.locale);
  const numberFormatter = new Intl.NumberFormat(localeTag(route.locale));
  const surahPath = quranSurahPath(route.edition, route.surah);
  const ayahPath = quranAyahPath(route.edition, route.surah, route.ayah);
  const title = translate(route.locale, "quran.deep.ayahTitle", {
    surah: numberFormatter.format(route.surah),
    ayah: numberFormatter.format(route.ayah),
    name,
  });
  const description = translate(route.locale, "quran.deep.ayahDescription", {
    surah: numberFormatter.format(route.surah),
    ayah: numberFormatter.format(route.ayah),
    name,
    edition: editionName(edition, route.locale),
  });
  const breadcrumbJson = JSON.stringify({
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: [
      {
        "@type": "ListItem",
        position: 1,
        name: translate(route.locale, "nav.quran"),
        item: absoluteSiteUrl(localizedPath(route.locale, "/quran")),
      },
      {
        "@type": "ListItem",
        position: 2,
        name,
        item: absoluteSiteUrl(localizedPath(route.locale, surahPath)),
      },
      {
        "@type": "ListItem",
        position: 3,
        name: title,
        item: absoluteSiteUrl(localizedPath(route.locale, ayahPath)),
      },
    ],
  }).replace(/</g, "\\u003c");

  return (
    <div className="seo-quran-page">
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: breadcrumbJson }} />
      <nav className="breadcrumbs" aria-label={translate(route.locale, "quran.deep.breadcrumbs")}>
        <ol>
          <li><Link href={localizedPath(route.locale, "/quran")}>{translate(route.locale, "nav.quran")}</Link></li>
          <li><Link href={localizedPath(route.locale, surahPath)}>{name}</Link></li>
          <li aria-current="page">
            {translate(route.locale, "common.ayah", {
              ayah: numberFormatter.format(route.ayah),
            })}
          </li>
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
              version: edition.active_version?.version || ayah.content_version,
            })}
          </p>
        </div>
        <Link href={localizedPath(route.locale, surahPath)} className="btn btn-secondary">
          {translate(route.locale, "quran.deep.allAyahs")}
        </Link>
      </header>

      <article className="ayah-card seo-single-ayah">
        <div className="ayah-header">
          <span className="ayah-badge">{numberFormatter.format(ayah.number)}</span>
          <span className="surface-subtitle">
            {translate(route.locale, "quran.ayahMeta", {
              ayah: numberFormatter.format(ayah.number),
              juz: numberFormatter.format(ayah.juz_number),
            })}
          </span>
        </div>
        <p className="quran-arabic-text" lang="ar" dir="rtl">{ayah.text_uthmani}</p>
      </article>

      <nav className="seo-ayah-pagination" aria-label={translate(route.locale, "quran.deep.breadcrumbs")}>
        {route.ayah > 1 ? (
          <Link
            className="btn btn-secondary"
            href={localizedPath(
              route.locale,
              quranAyahPath(route.edition, route.surah, route.ayah - 1),
            )}
          >
            {translate(route.locale, "quran.deep.previousAyah")}
          </Link>
        ) : <span />}
        {route.ayah < surah.ayah_count ? (
          <Link
            className="btn btn-secondary"
            href={localizedPath(
              route.locale,
              quranAyahPath(route.edition, route.surah, route.ayah + 1),
            )}
          >
            {translate(route.locale, "quran.deep.nextAyah")}
          </Link>
        ) : <span />}
      </nav>
    </div>
  );
}
