import type { Metadata } from "next";
import HomePage from "../../components/HomePage";
import { isLocale } from "../../lib/i18n";
import { getPublishedHomeInitialData } from "../../lib/public-content";
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

export default async function LocalizedHomePage({
  params,
}: {
  params: Promise<{ locale: string }>;
}) {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  let initialData;
  try {
    initialData = await getPublishedHomeInitialData();
  } catch (error) {
    console.error("Home catalog server rendering is temporarily unavailable", error);
  }
  return <HomePage initialData={initialData} />;
}
