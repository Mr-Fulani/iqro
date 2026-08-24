import type { Metadata } from "next";
import { createPageMetadata } from "../../lib/seo";
import { requestLocale } from "../../lib/server-locale";

export async function generateMetadata(): Promise<Metadata> {
  return createPageMetadata(await requestLocale(), {
    titleKey: "profile.title",
    descriptionKey: "profile.loginDescription",
    path: "/profile",
    index: false,
  });
}

export default function ProfileLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return children;
}
