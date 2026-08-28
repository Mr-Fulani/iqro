import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { recitationLabel, reciterName } from "@/lib/audio-content";
import { isLocale, type Locale } from "@/lib/i18n";
import { legalConfig } from "@/lib/legal-config";
import { legalCopy } from "@/lib/legal-content";
import { getPublishedEditions, getPublishedRecitations } from "@/lib/public-content";
import { createContentMetadata } from "@/lib/seo";

export const revalidate = 3_600;

type RouteParams = { locale: string };

const DUA_SOURCE_URLS: Record<Locale, string> = {
  ar: "https://islamhouse.com/ar/books/2522",
  en: "https://islamhouse.com/en/books/39062",
  ru: "https://islamhouse.com/ru/books/888254",
  tr: "https://islamhouse.com/tr/books/861",
};

function localeParam(value: string): Locale {
  if (!isLocale(value)) notFound();
  return value;
}

export async function generateMetadata({ params }: { params: Promise<RouteParams> }): Promise<Metadata> {
  const locale = localeParam((await params).locale);
  const copy = legalCopy(locale, legalConfig()).sources;
  return createContentMetadata(locale, { title: copy.title, description: copy.description, path: "/sources" });
}

export default async function SourcesPage({ params }: { params: Promise<RouteParams> }) {
  const locale = localeParam((await params).locale);
  const copy = legalCopy(locale, legalConfig()).sources;
  const [editions, recitations] = await Promise.all([
    getPublishedEditions(),
    getPublishedRecitations(),
  ]);
  return (
    <article className="seo-quran-page legal-document">
      <header className="surface seo-quran-hero">
        <div><p className="eyebrow">Quran Platform</p><h1>{copy.title}</h1><p>{copy.description}</p></div>
      </header>
      <section className="surface legal-section">
        <h2 className="surface-title">{copy.quranTitle}</h2>
        {editions.length ? <div className="legal-license-list">{editions.map((edition) => (
          <article key={edition.id}>
            <h3>{edition.name_en} · {edition.riwayah}</h3>
            <dl>
              <div><dt>{copy.version}</dt><dd>{edition.active_version?.version}</dd></div>
              <div><dt>{copy.source}</dt><dd>{edition.source_url ? <a href={edition.source_url} target="_blank" rel="noreferrer">{edition.source_name}</a> : edition.source_name}</dd></div>
              <div><dt>{copy.license}</dt><dd>{edition.license_url ? <a href={edition.license_url} target="_blank" rel="noreferrer">{edition.license_name}</a> : edition.license_name}</dd></div>
            </dl>
          </article>
        ))}</div> : <p>{copy.noQuran}</p>}
      </section>
      <section className="surface legal-section">
        <h2 className="surface-title">{copy.audioTitle}</h2>
        {recitations.length ? <div className="legal-license-list">{recitations.map((recitation) => (
          <article key={recitation.id}>
            <h3>{reciterName(recitation.reciter, locale)} · {recitationLabel(recitation)}</h3>
            <dl>
              <div><dt>{copy.version}</dt><dd>{recitation.version}</dd></div>
              <div><dt>{copy.source}</dt><dd>{recitation.source.url ? <a href={recitation.source.url} target="_blank" rel="noreferrer">{recitation.source.name}</a> : recitation.source.name}</dd></div>
              <div><dt>{copy.license}</dt><dd>{recitation.license.url ? <a href={recitation.license.url} target="_blank" rel="noreferrer">{recitation.license.name}</a> : recitation.license.name}</dd></div>
              <div><dt>{copy.rightsHolder}</dt><dd>{recitation.license.rights_holder}</dd></div>
              {recitation.license.attribution && <div><dt>{copy.attribution}</dt><dd>{recitation.license.attribution}</dd></div>}
            </dl>
          </article>
        ))}</div> : <p>{copy.noAudio}</p>}
      </section>
      <section className="surface legal-section">
        <h2 className="surface-title">{copy.duaTitle}</h2>
        <p>{copy.duaBody}</p>
        <div className="legal-license-list">
          <article>
            <h3>Hisn al-Muslim · IslamHouse</h3>
            <dl>
              <div><dt>{copy.version}</dt><dd>hisn-full-2026-08-28</dd></div>
              <div><dt>{copy.source}</dt><dd><a href={DUA_SOURCE_URLS[locale]} target="_blank" rel="noreferrer">IslamHouse</a></dd></div>
              <div><dt>{copy.license}</dt><dd><a href="https://d1.islamhouse.com/html/faq.htm" target="_blank" rel="noreferrer">IslamHouse FAQ</a></dd></div>
            </dl>
            <p>{copy.duaRights}</p>
            <p>{copy.duaVerification}</p>
          </article>
        </div>
      </section>
      <aside className="surface legal-section"><h2 className="surface-title">{copy.noticeTitle}</h2><p>{copy.noticeBody}</p></aside>
    </article>
  );
}
