import type { Metadata } from "next";
import { notFound } from "next/navigation";
import MemorizationPage from "../../memorization/page";
import { isLocale } from "../../../lib/i18n";
import { createPageMetadata } from "../../../lib/seo";

type Props = { params: Promise<{ locale: string }> };

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { locale } = await params;
  if (!isLocale(locale)) return {};
  return createPageMetadata(locale, {
    titleKey: "memorization.metaTitle",
    descriptionKey: "memorization.metaDescription",
    path: "/memorization",
    index: false,
  });
}

export default async function LocalizedMemorizationPage({ params }: Props) {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  return <MemorizationPage />;
}
