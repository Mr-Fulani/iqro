import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { isLocale, localeTag, translate, type Locale } from "@/lib/i18n";
import {
  getPublishedEdition,
  getPublishedSurahs,
  isEditionCode,
  PublicContentNotFoundError,
} from "@/lib/public-content";
import { editionName, quranEditionPath, quranSurahPath, surahName } from "@/lib/quran-content";
import { localizedPath } from "@/lib/routing";
import { createContentMetadata } from "@/lib/seo";

export const revalidate = 3_600;

export function generateStaticParams() {
  return [];
}

type RouteParams = { locale: string; edition: string };

function parseParams(params: RouteParams): { locale: Locale; edition: string } {
  if (!isLocale(params.locale) || !isEditionCode(params.edition)) notFound();
  return { locale: params.locale, edition: params.edition };
}

async function publishedCatalog(edition: string) {
  try {
    return await Promise.all([
      getPublishedEdition(edition),
      getPublishedSurahs(edition),
    ]);
  } catch (error) {
    if (error instanceof PublicContentNotFoundError) notFound();
    throw error;
  }
}

export async function generateMetadata({ params }: { params: Promise<RouteParams> }): Promise<Metadata> {
  const route = parseParams(await params);
  const [edition, surahs] = await publishedCatalog(route.edition);
  const name = editionName(edition, route.locale);
  return createContentMetadata(route.locale, {
    title: translate(route.locale, "quran.deep.editionTitle", { edition: name }),
    description: translate(route.locale, "quran.deep.editionDescription", {
      edition: name,
      count: surahs.length,
    }),
    path: quranEditionPath(route.edition),
  });
}

export default async function QuranEditionPage({ params }: { params: Promise<RouteParams> }) {
  const route = parseParams(await params);
  const [edition, surahs] = await publishedCatalog(route.edition);
  const name = editionName(edition, route.locale);
  const numbers = new Intl.NumberFormat(localeTag(route.locale));

  return (
    <div className="seo-quran-page">
      <nav className="breadcrumbs" aria-label={translate(route.locale, "quran.deep.breadcrumbs")}>
        <ol>
          <li><Link href={localizedPath(route.locale, "/quran")}>{translate(route.locale, "nav.quran")}</Link></li>
          <li aria-current="page">{name}</li>
        </ol>
      </nav>
      <header className="surface seo-quran-hero">
        <div>
          <p className="eyebrow">{edition.name_ar}</p>
          <h1>{translate(route.locale, "quran.deep.editionTitle", { edition: name })}</h1>
          <p>{translate(route.locale, "quran.deep.editionDescription", {
            edition: name,
            count: numbers.format(surahs.length),
          })}</p>
          <p className="seo-content-version">
            {translate(route.locale, "quran.deep.editionVersion", {
              edition: name,
              version: edition.active_version?.version || "—",
            })}
          </p>
        </div>
      </header>
      <section className="seo-catalog-grid" aria-label={translate(route.locale, "home.surahCatalog")}>
        {surahs.map((surah) => (
          <Link
            key={surah.id}
            href={localizedPath(route.locale, quranSurahPath(route.edition, surah.number))}
            className="track-row seo-catalog-card"
          >
            <span className="ayah-badge">{numbers.format(surah.number)}</span>
            <span className="seo-catalog-copy">
              <strong>{surahName(surah, route.locale)}</strong>
              <span>{translate(route.locale, "quran.ayahsShort", {
                count: numbers.format(surah.ayah_count),
              })}</span>
            </span>
            <span className="seo-catalog-arabic" lang="ar" dir="rtl">{surah.name_ar}</span>
          </Link>
        ))}
      </section>
    </div>
  );
}
