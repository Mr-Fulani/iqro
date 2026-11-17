import type { Metadata } from "next";
import { notFound } from "next/navigation";
import MorePage from "../../../components/MorePage";
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
    titleKey: "nav.more",
    descriptionKey: "more.subtitle",
    path: "/more",
    index: false,
  });
}

export default MorePage;
