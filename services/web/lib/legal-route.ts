import { notFound } from "next/navigation";
import { additionalLegalCopy, type AdditionalLegalCopy } from "./legal-additional-content";
import { legalConfig } from "./legal-config";
import { isLocale, type Locale } from "./i18n";

export type AdditionalLegalPage = keyof AdditionalLegalCopy;

export function additionalLegalDocument(
  rawLocale: string,
  page: AdditionalLegalPage,
): { locale: Locale; document: AdditionalLegalCopy[AdditionalLegalPage] } {
  if (!isLocale(rawLocale)) notFound();
  return {
    locale: rawLocale,
    document: additionalLegalCopy(rawLocale, legalConfig())[page],
  };
}
