import type { Metadata } from "next";
import { createPageMetadata } from "../../lib/seo";
import { requestLocale } from "../../lib/server-locale";

export async function generateMetadata(): Promise<Metadata> {
  return createPageMetadata(await requestLocale(), {
    titleKey: "authForm.loginTitle",
    descriptionKey: "authForm.description",
    path: "/login",
    index: false,
  });
}

export default function LoginLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return children;
}
