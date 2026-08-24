import type { Metadata } from "next";
import { notFound } from "next/navigation";
import QuranPage from "../../quran/page";
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
    titleKey: "quran.title",
    descriptionKey: "quran.description",
    path: "/quran",
  });
}

export default QuranPage;
