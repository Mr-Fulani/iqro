import type { Metadata } from "next";
import HomePage from "../page";
import { isLocale } from "../../lib/i18n";
import { createRootMetadata } from "../../lib/seo";
import { notFound } from "next/navigation";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  return createRootMetadata(locale);
}

export default HomePage;
