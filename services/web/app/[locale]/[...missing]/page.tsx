import { notFound } from "next/navigation";

// Unknown paths under a locale render the localized not-found page inside the
// root layout. Without generateStaticParams this route stays dynamic, so
// arbitrary URLs never create ISR cache entries.
export default function MissingPage() {
  notFound();
}
