"use client";

import Link from "next/link";
import { useI18n } from "../lib/i18n-context";
import { localizedPath } from "../lib/routing";

export function Footer() {
  const { locale, t } = useI18n();
  return (
    <footer className="app-footer">
      <div className="footer-content">
        <div className="footer-brand">
          <span className="brand-mark sm">Q</span>
          <p>
            <strong>Quran Platform</strong> — {t("footer.description")}
          </p>
        </div>

        <div className="footer-links">
          <nav className="footer-column" aria-label={t("footer.sections")}>
            <p className="footer-column-title">{t("footer.sections")}</p>
            <Link href={localizedPath(locale, "/quran")}>{t("footer.quran")}</Link>
            <Link href={localizedPath(locale, "/audio/reciters")}>{t("footer.reciters")}</Link>
            <Link href={localizedPath(locale, "/prayer")}>{t("footer.prayer")}</Link>
            <Link href={localizedPath(locale, "/profile")}>{t("footer.sync")}</Link>
          </nav>

          <nav className="footer-column" aria-label={t("footer.account")}>
            <p className="footer-column-title">{t("footer.account")}</p>
            <Link href={localizedPath(locale, "/login")}>{t("footer.session")}</Link>
            <Link href={localizedPath(locale, "/profile")}>{t("nav.profile")}</Link>
          </nav>

          <nav className="footer-column" aria-label={t("footer.legal")}>
            <p className="footer-column-title">{t("footer.legal")}</p>
            <Link href={localizedPath(locale, "/privacy")}>{t("footer.privacy")}</Link>
            <Link href={localizedPath(locale, "/terms")}>{t("footer.terms")}</Link>
            <Link href={localizedPath(locale, "/sources")}>{t("footer.sources")}</Link>
            <Link href={localizedPath(locale, "/contacts")}>{t("footer.contacts")}</Link>
          </nav>
        </div>
      </div>

      <div className="footer-bottom">
        <p>{t("footer.copyright")}</p>
      </div>
    </footer>
  );
}
