import type { Metadata } from "next";
import { notFound } from "next/navigation";
import RegisterPage from "../../register/page";
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
    titleKey: "authForm.registerTitle",
    descriptionKey: "authForm.description",
    path: "/register",
    index: false,
  });
}

export default RegisterPage;
