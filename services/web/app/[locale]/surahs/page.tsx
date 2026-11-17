import type { Metadata } from "next";
import { notFound } from "next/navigation";
import QuranTabPage from "../../../components/QuranTabPage";
import type { Surah } from "../../../lib/api";
import { isLocale } from "../../../lib/i18n";
import { getPublishedEditions, getPublishedSurahs } from "../../../lib/public-content";
import { createPageMetadata } from "../../../lib/seo";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  return createPageMetadata(locale, {
    titleKey: "nav.quran",
    descriptionKey: "surahs.subtitle",
    path: "/surahs",
    index: false,
  });
}

export default async function LocalizedQuranTabPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  let edition = "madani-hafs";
  let surahs: Surah[] = [];
  try {
    const editions = await getPublishedEditions();
    if (editions[0]) edition = editions[0].code;
    surahs = await getPublishedSurahs(edition);
  } catch (error) {
    console.error("The surah list server rendering is temporarily unavailable", error);
  }
  return <QuranTabPage edition={edition} initialSurahs={surahs} />;
}
