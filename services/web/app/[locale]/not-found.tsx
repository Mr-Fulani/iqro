import Link from "next/link";
import { locale as rootLocale } from "next/root-params";
import { DEFAULT_LOCALE, isLocale } from "@/lib/i18n";
import { translate } from "@/lib/translate";
import { localizedPath } from "@/lib/routing";

export default async function NotFound() {
  const routedLocale = await rootLocale();
  const locale = isLocale(routedLocale) ? routedLocale : DEFAULT_LOCALE;
  return (
    <section className="surface system-state" aria-labelledby="not-found-title">
      <span className="system-state-code" aria-hidden="true">404</span>
      <div>
        <h1 id="not-found-title">{translate(locale, "errorPage.notFoundTitle")}</h1>
        <p>{translate(locale, "errorPage.notFoundDescription")}</p>
      </div>
      <Link href={localizedPath(locale, "/")} className="btn btn-primary">
        {translate(locale, "errorPage.home")}
      </Link>
    </section>
  );
}
