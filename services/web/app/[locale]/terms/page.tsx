import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { LegalDocument } from "@/components/LegalDocument";
import { isLocale, type Locale } from "@/lib/i18n";
import { legalConfig } from "@/lib/legal-config";
import { legalCopy } from "@/lib/legal-content";
import { createContentMetadata } from "@/lib/seo";

export const dynamic = "force-dynamic";

type RouteParams = { locale: string };

function localeParam(value: string): Locale {
  if (!isLocale(value)) notFound();
  return value;
}

export async function generateMetadata({ params }: { params: Promise<RouteParams> }): Promise<Metadata> {
  const locale = localeParam((await params).locale);
  const copy = legalCopy(locale, legalConfig()).terms;
  return createContentMetadata(locale, { title: copy.title, description: copy.description, path: "/terms" });
}

export default async function TermsPage({ params }: { params: Promise<RouteParams> }) {
  const locale = localeParam((await params).locale);
  const copy = legalCopy(locale, legalConfig()).terms;
  return <LegalDocument {...copy} />;
}
