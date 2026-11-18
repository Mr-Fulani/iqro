import type { Metadata } from "next";
import { notFound } from "next/navigation";
import SettingsPage from "../../../components/SettingsPage";
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
    titleKey: "home.settings",
    descriptionKey: "settings.privacyHint",
    path: "/settings",
    index: false,
  });
}

export default SettingsPage;
