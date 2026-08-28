import type { Metadata } from "next";
import { notFound } from "next/navigation";
import DuaPage from "../../dua/page";
import { isLocale } from "../../../lib/i18n";
import { getPublishedDuaInitialData } from "../../../lib/public-content";
import { createPageMetadata } from "../../../lib/seo";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  return createPageMetadata(locale, {
    titleKey: "dua.title",
    descriptionKey: "dua.description",
    path: "/dua",
    index: true,
  });
}

export default async function LocalizedDuaPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  let initialData;
  try {
    initialData = await getPublishedDuaInitialData(locale);
  } catch (error) {
    console.error("Dua catalog server rendering is temporarily unavailable", error);
  }
  return <DuaPage initialData={initialData} />;
}
