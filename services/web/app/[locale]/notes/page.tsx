import type { Metadata } from "next";
import { notFound } from "next/navigation";
import NotesPage from "../../../components/NotesPage";
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
    titleKey: "notes.title",
    descriptionKey: "notes.description",
    path: "/notes",
    index: false,
  });
}

export default NotesPage;
