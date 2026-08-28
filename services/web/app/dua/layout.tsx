import type { Metadata } from "next";
import { createPageMetadata } from "../../lib/seo";
import { requestLocale } from "../../lib/server-locale";

export async function generateMetadata(): Promise<Metadata> {
  return createPageMetadata(await requestLocale(), {
    titleKey: "dua.title",
    descriptionKey: "dua.description",
    path: "/dua",
    index: true,
  });
}

export default function DuaLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return children;
}
