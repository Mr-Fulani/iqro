import type { Metadata } from "next";
import { notFound } from "next/navigation";
import AudioPage from "../../audio/page";
import { isLocale } from "../../../lib/i18n";
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

export default AudioPage;
