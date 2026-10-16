import type { Metadata } from "next";
import { notFound } from "next/navigation";
import AudioPage from "../../../components/AudioPage";
import { isLocale } from "../../../lib/i18n";
import { getPublishedAudioInitialData } from "../../../lib/public-content";
import { createPageMetadata } from "../../../lib/seo";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  return createPageMetadata(locale, {
    titleKey: "audio.title",
    descriptionKey: "audio.description",
    path: "/audio",
  });
}

export default async function LocalizedAudioPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  let initialData;
  try {
    initialData = await getPublishedAudioInitialData();
  } catch (error) {
    console.error("Audio catalog server rendering is temporarily unavailable", error);
  }
  return <AudioPage initialData={initialData} />;
}
