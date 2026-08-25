import type { Metadata } from "next";
import { LegalDocument } from "@/components/LegalDocument";
import { additionalLegalDocument } from "@/lib/legal-route";
import { createContentMetadata } from "@/lib/seo";

export const dynamic = "force-dynamic";

type RouteParams = { locale: string };

export async function generateMetadata({ params }: { params: Promise<RouteParams> }): Promise<Metadata> {
  const { locale, document } = additionalLegalDocument((await params).locale, "security");
  return createContentMetadata(locale, { title: document.title, description: document.description, path: "/security" });
}

export default async function SecurityPage({ params }: { params: Promise<RouteParams> }) {
  const { document } = additionalLegalDocument((await params).locale, "security");
  return <LegalDocument {...document} />;
}
