import type { Metadata } from "next";
import { createPageMetadata } from "../../lib/seo";
import { requestLocale } from "../../lib/server-locale";

export async function generateMetadata(): Promise<Metadata> {
  return createPageMetadata(await requestLocale(), {
    titleKey: "prayer.title",
    descriptionKey: "prayer.description",
    path: "/prayer",
  });
}

export default function PrayerLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return children;
}
