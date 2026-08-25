import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ReciterAvatar } from "@/components/ReciterAvatar";
import {
  recitationLabel,
  recitationPath,
  reciterBiography,
  reciterName,
  reciterPath,
} from "@/lib/audio-content";
import { isLocale, localeTag, translate, type Locale } from "@/lib/i18n";
import {
  getPublishedRecitations,
  getPublishedReciter,
  isUuid,
  PublicContentNotFoundError,
} from "@/lib/public-content";
import { reciterPortraitUrl } from "@/lib/reciter-portraits";
import { localizedPath } from "@/lib/routing";
import { absoluteSiteUrl, createContentMetadata } from "@/lib/seo";

export const revalidate = 3_600;

type RouteParams = { locale: string; reciter: string };

function parseParams(params: RouteParams): { locale: Locale; reciter: string } {
  if (!isLocale(params.locale) || !isUuid(params.reciter)) notFound();
  return { locale: params.locale, reciter: params.reciter };
}

async function publishedReciter(reciter: string) {
  try {
    return await Promise.all([
      getPublishedReciter(reciter),
      getPublishedRecitations(reciter),
    ]);
  } catch (error) {
    if (error instanceof PublicContentNotFoundError) notFound();
    throw error;
  }
}

export async function generateMetadata({ params }: { params: Promise<RouteParams> }): Promise<Metadata> {
  const route = parseParams(await params);
  const [reciter, recitations] = await publishedReciter(route.reciter);
  const name = reciterName(reciter, route.locale);
  return createContentMetadata(route.locale, {
    title: translate(route.locale, "audio.deep.reciterTitle", { name }),
    description: translate(route.locale, "audio.deep.reciterDescription", {
      name,
      count: recitations.length,
    }),
    path: reciterPath(route.reciter),
  });
}

export default async function ReciterPage({ params }: { params: Promise<RouteParams> }) {
  const route = parseParams(await params);
  const [reciter, recitations] = await publishedReciter(route.reciter);
  const name = reciterName(reciter, route.locale);
  const biography = reciterBiography(reciter, route.locale) || translate(route.locale, "audio.deep.noBiography");
  const numbers = new Intl.NumberFormat(localeTag(route.locale));
  const currentPath = reciterPath(route.reciter);
  const breadcrumbJson = JSON.stringify({
    "@context": "https://schema.org",
    "@type": "BreadcrumbList",
    itemListElement: [
      {
        "@type": "ListItem",
        position: 1,
        name: translate(route.locale, "audio.deep.reciterCatalogTitle"),
        item: absoluteSiteUrl(localizedPath(route.locale, "/audio/reciters")),
      },
      {
        "@type": "ListItem",
        position: 2,
        name,
        item: absoluteSiteUrl(localizedPath(route.locale, currentPath)),
      },
    ],
  }).replace(/</g, "\\u003c");

  return (
    <div className="seo-quran-page">
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: breadcrumbJson }} />
      <nav className="breadcrumbs" aria-label={translate(route.locale, "audio.deep.breadcrumbs")}>
        <ol>
          <li><Link href={localizedPath(route.locale, "/audio/reciters")}>{translate(route.locale, "audio.deep.reciterCatalogTitle")}</Link></li>
          <li aria-current="page">{name}</li>
        </ol>
      </nav>
      <header className="surface seo-reciter-hero">
        <ReciterAvatar name={name} portraitUrl={reciterPortraitUrl(reciter)} tone={0} />
        <div className="seo-reciter-copy">
          <p className="eyebrow" lang="ar" dir="rtl">{reciter.name_ar}</p>
          <h1>{translate(route.locale, "audio.deep.reciterTitle", { name })}</h1>
          <p>{biography}</p>
          <p className="seo-content-version">
            {translate(route.locale, "audio.codeCountry", {
              code: reciter.slug,
              country: reciter.country_code,
            })}
          </p>
        </div>
        <Link
          href={localizedPath(route.locale, `/audio?reciter=${encodeURIComponent(reciter.id)}`)}
          className="btn btn-primary"
        >
          {translate(route.locale, "audio.deep.openPlayer")}
        </Link>
      </header>
      <section className="surface">
        <div className="surface-head">
          <h2 className="surface-title">{translate(route.locale, "audio.deep.publishedRecitations")}</h2>
          <span className="status-chip ok">{numbers.format(recitations.length)}</span>
        </div>
        <div className="seo-ayah-list">
          {recitations.map((recitation) => (
            <Link
              key={recitation.id}
              href={localizedPath(route.locale, recitationPath(recitation.id))}
              className="track-row seo-catalog-card"
            >
              <span className="seo-catalog-copy">
                <strong>{recitationLabel(recitation)}</strong>
                <span>{translate(route.locale, "audio.surahCoverage", {
                  count: numbers.format(recitation.coverage.surah_count),
                })}</span>
              </span>
              <span className="status-chip ok">
                {recitation.rights.stream ? translate(route.locale, "common.available") : "—"}
              </span>
            </Link>
          ))}
        </div>
      </section>
    </div>
  );
}
