import type { Metadata } from "next";
import { createPageMetadata } from "../../lib/seo";
import { requestLocale } from "../../lib/server-locale";

export async function generateMetadata(): Promise<Metadata> {
  return createPageMetadata(await requestLocale(), {
    titleKey: "quran.title",
    descriptionKey: "quran.description",
    path: "/quran",
  });
}

export default function QuranLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return children;
}
