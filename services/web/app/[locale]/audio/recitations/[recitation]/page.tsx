import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import {
  formatTrackDuration,
  recitationLabel,
  recitationPath,
  reciterName,
  reciterPath,
} from "@/lib/audio-content";
import { isLocale, localeTag, translate, type Locale } from "@/lib/i18n";
import {
  getPublishedRecitation,
  getPublishedSurahTracks,
  isUuid,
  PublicContentNotFoundError,
} from "@/lib/public-content";
import { localizedPath } from "@/lib/routing";
import { absoluteSiteUrl, createContentMetadata } from "@/lib/seo";
import { serializeJsonLd } from "@/lib/json-ld";

export const revalidate = 3_600;

export function generateStaticParams() {
  return [];
}

type RouteParams = { locale: string; recitation: string };

function parseParams(params: RouteParams): { locale: Locale; recitation: string } {
  if (!isLocale(params.locale) || !isUuid(params.recitation)) notFound();
  return { locale: params.locale, recitation: params.recitation };
}

async function publishedRecitation(recitation: string) {
  try {
    return await Promise.all([
      getPublishedRecitation(recitation),
      getPublishedSurahTracks(recitation),
    ]);
  } catch (error) {
    if (error instanceof PublicContentNotFoundError) notFound();
    throw error;
  }
}

export async function generateMetadata({ params }: { params: Promise<RouteParams> }): Promise<Metadata> {
  const route = parseParams(await params);
  const [recitation] = await publishedRecitation(route.recitation);
  const name = reciterName(recitation.reciter, route.locale);
  const label = recitationLabel(recitation);
  return createContentMetadata(route.locale, {
    title: translate(route.locale, "audio.deep.recitationTitle", { name, recitation: label }),
    description: translate(route.locale, "audio.deep.recitationDescription", {
      name,
      recitation: label,
      count: recitation.coverage.surah_count,
    }),
    path: recitationPath(route.recitation),
  });
}

export default async function RecitationPage({ params }: { params: Promise<RouteParams> }) {
  const route = parseParams(await params);
  const [recitation, tracks] = await publishedRecitation(route.recitation);
  const name = reciterName(recitation.reciter, route.locale);
  const label = recitationLabel(recitation);
  const numbers = new Intl.NumberFormat(localeTag(route.locale));
  const date = new Intl.DateTimeFormat(localeTag(route.locale), { dateStyle: "long" }).format(
    new Date(recitation.published_at),
  );
  const currentPath = recitationPath(route.recitation);
  const pageUrl = absoluteSiteUrl(localizedPath(route.locale, currentPath));
  const totalDurationSeconds = Math.round(
    tracks.reduce((total, track) => total + track.duration_ms, 0) / 1_000,
  );
  const structuredDataJson = serializeJsonLd({
    "@context": "https://schema.org",
    "@graph": [
      {
        "@type": "BreadcrumbList",
        itemListElement: [
          {
            "@type": "ListItem",
            position: 1,
            name,
            item: absoluteSiteUrl(localizedPath(route.locale, reciterPath(recitation.reciter.id))),
          },
          {
            "@type": "ListItem",
            position: 2,
            name: label,
            item: pageUrl,
          },
        ],
      },
      {
        "@type": "AudioObject",
        "@id": `${pageUrl}#audio`,
        name: translate(route.locale, "audio.deep.recitationTitle", { name, recitation: label }),
        url: pageUrl,
        inLanguage: "ar",
        encodingFormat: [...new Set(tracks.map((track) => track.asset.content_type))],
        duration: `PT${totalDurationSeconds}S`,
        uploadDate: recitation.published_at,
        creator: { "@type": "Person", name },
        copyrightHolder: { "@type": "Organization", name: recitation.license.rights_holder },
        license: recitation.license.url || recitation.license.name,
        isAccessibleForFree: true,
      },
    ],
  });

  return (
    <div className="seo-quran-page">
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: structuredDataJson }} />
      <nav className="breadcrumbs" aria-label={translate(route.locale, "audio.deep.breadcrumbs")}>
        <ol>
          <li><Link href={localizedPath(route.locale, reciterPath(recitation.reciter.id))}>{name}</Link></li>
          <li aria-current="page">{label}</li>
        </ol>
      </nav>
      <header className="surface seo-quran-hero">
        <div>
          <p className="eyebrow">{recitation.quran_edition.riwayah}</p>
          <h1>{translate(route.locale, "audio.deep.recitationTitle", { name, recitation: label })}</h1>
          <p>{translate(route.locale, "audio.deep.recitationDescription", {
            name,
            recitation: label,
            count: numbers.format(recitation.coverage.surah_count),
          })}</p>
          <p className="seo-content-version">
            {translate(route.locale, "audio.deep.publishedVersion", {
              version: recitation.version,
              date,
            })}
          </p>
        </div>
        <Link
          href={localizedPath(route.locale, `/audio?reciter=${encodeURIComponent(recitation.reciter.id)}`)}
          className="btn btn-primary"
        >
          {translate(route.locale, "audio.deep.openPlayer")}
        </Link>
      </header>
      <section className="surface">
        <div className="surface-head">
          <h2 className="surface-title">{translate(route.locale, "audio.deep.sourceLicense")}</h2>
        </div>
        <div className="seo-license-grid">
          <div>
            <strong>{recitation.source.name}</strong>
            <p className="surface-subtitle">{recitation.source.version}</p>
            {recitation.source.url && <a href={recitation.source.url} target="_blank" rel="noreferrer">{recitation.source.url}</a>}
          </div>
          <div>
            <strong>{recitation.license.name}</strong>
            <p className="surface-subtitle">{recitation.license.attribution || recitation.license.rights_holder}</p>
            {recitation.license.url && <a href={recitation.license.url} target="_blank" rel="noreferrer">{recitation.license.url}</a>}
          </div>
        </div>
      </section>
      <section className="surface">
        <div className="surface-head">
          <h2 className="surface-title">{translate(route.locale, "audio.trackList")}</h2>
          <span className="status-chip ok">{translate(route.locale, "audio.foundTracks", { count: numbers.format(tracks.length) })}</span>
        </div>
        <div className="seo-ayah-list">
          {tracks.map((track) => (
            <div className="track-row" key={track.id}>
              <span className="ayah-badge">{track.surah_number || "♪"}</span>
              <span className="seo-catalog-copy">
                <strong>{translate(route.locale, "common.surah", { surah: track.surah_number || "—" })}</strong>
                <span>
                  {track.asset.codec.toUpperCase()} · {translate(route.locale, "audio.bitrate", {
                    value: numbers.format(track.asset.bitrate_kbps),
                  })} · {formatTrackDuration(track.duration_ms, route.locale)}
                </span>
              </span>
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}
