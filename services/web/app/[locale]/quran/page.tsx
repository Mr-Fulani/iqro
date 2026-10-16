import type { Metadata } from "next";
import { notFound } from "next/navigation";
import QuranPage from "../../../components/QuranPage";
import { isLocale } from "../../../lib/i18n";
import { getPublishedQuranReaderPreview } from "../../../lib/public-content";
import { createPageMetadata } from "../../../lib/seo";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  return createPageMetadata(locale, {
    titleKey: "quran.title",
    descriptionKey: "quran.description",
    path: "/quran",
  });
}

export default async function LocalizedQuranPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  let preview;
  try {
    preview = await getPublishedQuranReaderPreview();
  } catch (error) {
    console.error("Quran reader preview server rendering is temporarily unavailable", error);
  }
  return <QuranPage preview={preview} />;
}
