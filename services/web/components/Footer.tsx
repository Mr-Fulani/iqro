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
          <div className="footer-column">
            <h4>{t("footer.sections")}</h4>
            <Link href={localizedPath(locale, "/quran")}>{t("footer.quran")}</Link>
            <Link href={localizedPath(locale, "/audio/reciters")}>{t("footer.reciters")}</Link>
            <Link href={localizedPath(locale, "/prayer")}>{t("footer.prayer")}</Link>
            <Link href={localizedPath(locale, "/profile")}>{t("footer.sync")}</Link>
          </div>

          <div className="footer-column">
            <h4>{t("footer.account")}</h4>
            <Link href={localizedPath(locale, "/login")}>{t("footer.session")}</Link>
            <Link href={localizedPath(locale, "/profile")}>{t("nav.profile")}</Link>
          </div>

          <div className="footer-column">
            <h4>{t("footer.legal")}</h4>
            <Link href={localizedPath(locale, "/privacy")}>{t("footer.privacy")}</Link>
            <Link href={localizedPath(locale, "/terms")}>{t("footer.terms")}</Link>
            <Link href={localizedPath(locale, "/sources")}>{t("footer.sources")}</Link>
            <Link href={localizedPath(locale, "/contacts")}>{t("footer.contacts")}</Link>
          </div>
        </div>
      </div>

      <div className="footer-bottom">
        <p>{t("footer.copyright")}</p>
      </div>
    </footer>
  );
}
