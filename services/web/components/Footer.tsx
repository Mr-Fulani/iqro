"use client";

import Link from "next/link";
import { useI18n } from "../lib/i18n-context";

export function Footer() {
  const { t } = useI18n();
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
            <Link href="/quran">{t("footer.quran")}</Link>
            <Link href="/audio">{t("footer.reciters")}</Link>
            <Link href="/prayer">{t("footer.prayer")}</Link>
            <Link href="/profile">{t("footer.sync")}</Link>
          </div>

          <div className="footer-column">
            <h4>{t("footer.developers")}</h4>
            <a href="http://localhost:8000/api/docs" target="_blank" rel="noreferrer">
              Swagger UI
            </a>
            <a href="http://localhost:8000/api/schema" target="_blank" rel="noreferrer">
              OpenAPI Schema
            </a>
            <Link href="/login">{t("footer.session")}</Link>
          </div>
        </div>
      </div>

      <div className="footer-bottom">
        <p>{t("footer.copyright")}</p>
      </div>
    </footer>
  );
}
