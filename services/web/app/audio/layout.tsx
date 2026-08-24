import type { Metadata } from "next";
import { createPageMetadata } from "../../lib/seo";
import { requestLocale } from "../../lib/server-locale";

export async function generateMetadata(): Promise<Metadata> {
  return createPageMetadata(await requestLocale(), {
    titleKey: "audio.title",
    descriptionKey: "audio.description",
    path: "/audio",
  });
}

export default function AudioLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return children;
}
