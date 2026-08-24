import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { isLocale, type Locale } from "@/lib/i18n";
import { legalConfig } from "@/lib/legal-config";
import { legalCopy } from "@/lib/legal-content";
import { localizedPath } from "@/lib/routing";
import { createContentMetadata } from "@/lib/seo";

export const dynamic = "force-dynamic";

type RouteParams = { locale: string };

function localeParam(value: string): Locale {
  if (!isLocale(value)) notFound();
  return value;
}

export async function generateMetadata({ params }: { params: Promise<RouteParams> }): Promise<Metadata> {
  const locale = localeParam((await params).locale);
  const copy = legalCopy(locale, legalConfig()).contacts;
  return createContentMetadata(locale, { title: copy.title, description: copy.description, path: "/contacts" });
}

export default async function ContactsPage({ params }: { params: Promise<RouteParams> }) {
  const locale = localeParam((await params).locale);
  const config = legalConfig();
  const copy = legalCopy(locale, config).contacts;
  return (
    <article className="seo-quran-page legal-document">
      <header className="surface seo-quran-hero">
        <div>
          <p className="eyebrow">Quran Platform</p>
          <h1>{copy.title}</h1>
          <p>{copy.description}</p>
        </div>
      </header>
      <section className="surface legal-contact-grid">
        <div><strong>{copy.operator}</strong><p>{config.entityName}</p></div>
        <div><strong>{copy.general}</strong><p><a href={`mailto:${config.contactEmail}`}>{config.contactEmail}</a></p></div>
        <div><strong>{copy.privacy}</strong><p><a href={`mailto:${config.contactEmail}`}>{config.contactEmail}</a></p></div>
        <div><strong>{copy.security}</strong><p><a href={`mailto:${config.securityEmail}`}>{config.securityEmail}</a></p></div>
        <div><strong>{copy.address}</strong><p>{config.postalAddress}</p></div>
      </section>
      <section className="surface legal-section">
        <h2 className="surface-title">{copy.feedbackTitle}</h2>
        <p>{copy.feedbackBody}</p>
        <Link className="btn btn-primary" href={localizedPath(locale, "/profile#feedback")}>{copy.feedbackAction}</Link>
      </section>
      <aside className="surface legal-section"><p>{copy.urgent}</p></aside>
    </article>
  );
}
