import type { Metadata } from "next";
import { notFound } from "next/navigation";
import ProfilePage from "../../profile/page";
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
    titleKey: "profile.title",
    descriptionKey: "profile.loginDescription",
    path: "/profile",
    index: false,
  });
}

export default ProfilePage;
