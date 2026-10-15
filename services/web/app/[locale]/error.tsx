"use client";

import Link from "next/link";
import { useEffect } from "react";
import { useI18n } from "@/lib/i18n-context";
import { localizedPath } from "@/lib/routing";

export default function ErrorPage({
  error,
  retry,
}: {
  error: Error & { digest?: string };
  retry: () => void;
}) {
  const { locale, t } = useI18n();

  useEffect(() => {
    console.error(error);
  }, [error]);

  return (
    <section className="surface system-state" aria-labelledby="error-title">
      <span className="system-state-code" aria-hidden="true">!</span>
      <div>
        <h1 id="error-title">{t("errorPage.unexpectedTitle")}</h1>
        <p>{t("errorPage.unexpectedDescription")}</p>
        {error.digest && <p className="system-state-reference">ID: {error.digest}</p>}
      </div>
      <div className="system-state-actions">
        <button type="button" className="btn btn-primary" onClick={() => retry()}>
          {t("errorPage.retry")}
        </button>
        <Link href={localizedPath(locale, "/")} className="btn btn-secondary">
          {t("errorPage.home")}
        </Link>
      </div>
    </section>
  );
}
