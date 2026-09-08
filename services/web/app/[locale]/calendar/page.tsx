import type { Metadata } from "next";
import { notFound } from "next/navigation";
import CalendarPage from "../../calendar/page";
import { isLocale } from "../../../lib/i18n";
import { createPageMetadata } from "../../../lib/seo";

export async function generateMetadata({ params }: { params: Promise<{ locale: string }> }): Promise<Metadata> {
  const { locale } = await params;
  if (!isLocale(locale)) notFound();
  return createPageMetadata(locale, {titleKey: "calendar.title", descriptionKey: "calendar.description", path: "/calendar"});
}

export default CalendarPage;
