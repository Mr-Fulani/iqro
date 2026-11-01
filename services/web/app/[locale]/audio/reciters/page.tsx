import type { Metadata } from "next";
import Link from "next/link";
import { connection } from "next/server";
import { ReciterAvatar, ReciterFullBadge } from "@/components/ReciterAvatar";
import { reciterName, reciterPath } from "@/lib/audio-content";
import { isLocale } from "@/lib/i18n";
import { translate } from "@/lib/translate";
import { getPublishedReciters } from "@/lib/public-content";
import { groupRecitersByPerson, recitersWithPortraitsFirst } from "@/lib/reciter-catalog";
import { reciterPortraitUrl } from "@/lib/reciter-portraits";
import { localizedPath } from "@/lib/routing";
import { createPageMetadata } from "@/lib/seo";
import { notFound } from "next/navigation";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  return createPageMetadata(locale, {
    titleKey: "audio.deep.reciterCatalogTitle",
    descriptionKey: "audio.deep.reciterCatalogDescription",
    path: "/audio/reciters",
  });
}

export default async function ReciterCatalogPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  await connection();
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  const reciters = recitersWithPortraitsFirst(groupRecitersByPerson(await getPublishedReciters()));

  return (
    <div className="seo-quran-page">
      <nav className="breadcrumbs" aria-label={translate(locale, "audio.deep.breadcrumbs")}>
        <ol>
          <li><Link href={localizedPath(locale, "/audio")}>{translate(locale, "nav.audio")}</Link></li>
          <li aria-current="page">{translate(locale, "audio.deep.reciterCatalogTitle")}</li>
        </ol>
      </nav>
      <header className="surface seo-quran-hero">
        <div>
          <p className="eyebrow">{translate(locale, "audio.eyebrow")}</p>
          <h1>{translate(locale, "audio.deep.reciterCatalogTitle")}</h1>
          <p>{translate(locale, "audio.deep.reciterCatalogDescription")}</p>
        </div>
        <Link href={localizedPath(locale, "/audio")} className="btn btn-primary">
          {translate(locale, "audio.deep.openPlayer")}
        </Link>
      </header>
      <p className="reciter-full-hint">
        <ReciterFullBadge />
        {translate(locale, "audio.fullReciterHint")}
      </p>
      <section className="reciter-grid" aria-label={translate(locale, "audio.deep.reciterCatalogTitle")}>
        {reciters.map((reciter, index) => {
          const name = reciterName(reciter, locale);
          return (
            <Link
              key={reciter.id}
              href={localizedPath(locale, reciterPath(reciter.id))}
              className={`reciter-card${reciter.full_support ? " is-full" : ""}`}
            >
              <ReciterAvatar
                name={name}
                portraitUrl={reciterPortraitUrl(reciter)}
                tone={index}
                full={reciter.full_support}
              />
              <span className="reciter-card-copy">
                <strong>{name}</strong>
                <span lang="ar" dir="rtl">{reciter.name_ar}</span>
              </span>
            </Link>
          );
        })}
      </section>
    </div>
  );
}
