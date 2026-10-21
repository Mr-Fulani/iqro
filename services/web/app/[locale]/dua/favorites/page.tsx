import type { Metadata } from "next";
import { notFound } from "next/navigation";

import { DuaFavoritesPage } from "@/components/DuaFavoritesPage";
import { isLocale } from "@/lib/i18n";
import { createPageMetadata } from "@/lib/seo";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  // Personal: the page is the same empty frame for every crawler.
  return createPageMetadata(locale, {
    titleKey: "dua.favorites",
    descriptionKey: "dua.favoritesSubtitle",
    path: "/dua/favorites",
    index: false,
  });
}

export default async function LocalizedDuaFavoritesPage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  return <DuaFavoritesPage />;
}
