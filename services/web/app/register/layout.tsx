import type { Metadata } from "next";
import { createPageMetadata } from "../../lib/seo";
import { requestLocale } from "../../lib/server-locale";

export async function generateMetadata(): Promise<Metadata> {
  return createPageMetadata(await requestLocale(), {
    titleKey: "authForm.registerTitle",
    descriptionKey: "authForm.description",
    path: "/register",
    index: false,
  });
}

export default function RegisterLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return children;
}
