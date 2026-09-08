"use client";

import Link from "next/link";
import type { SocialProfile } from "../lib/api";
import { useI18n } from "../lib/i18n-context";
import { localizedPath } from "../lib/routing";
import { SocialLinks } from "./social/SocialLinks";

type FooterProps = {
  socialProfiles?: SocialProfile[];
};

export function Footer({ socialProfiles = [] }: FooterProps) {
  const { locale, t } = useI18n();
  return (
    <footer className="app-footer">
      <div className="footer-content">
        <div className="footer-brand">
          <span className="brand-mark sm">Q</span>
          <p>
            <strong>IQRO</strong> — {t("brand.subtitle")}. {t("footer.description")}
          </p>
        </div>

        <div className="footer-links">
          <nav className="footer-column" aria-label={t("footer.sections")}>
            <p className="footer-column-title">{t("footer.sections")}</p>
            <Link href={localizedPath(locale, "/quran")}>{t("footer.quran")}</Link>
            <Link href={localizedPath(locale, "/memorization")}>{t("nav.memorization")}</Link>
            <Link href={localizedPath(locale, "/planner")}>{t("nav.planner")}</Link>
            <Link href={localizedPath(locale, "/dua")}>{t("nav.dua")}</Link>
            <Link href={localizedPath(locale, "/calendar")}>{t("calendar.title")}</Link>
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
            <Link href={localizedPath(locale, "/legal")}>{t("footer.legalHub")}</Link>
            <Link href={localizedPath(locale, "/privacy")}>{t("footer.privacy")}</Link>
            <Link href={localizedPath(locale, "/terms")}>{t("footer.terms")}</Link>
            <Link href={localizedPath(locale, "/cookies")}>{t("footer.cookies")}</Link>
            <Link href={localizedPath(locale, "/data-rights")}>{t("footer.dataRights")}</Link>
            <Link href={localizedPath(locale, "/providers")}>{t("footer.providers")}</Link>
            <Link href={localizedPath(locale, "/security")}>{t("footer.security")}</Link>
            <Link href={localizedPath(locale, "/sources")}>{t("footer.sources")}</Link>
            <Link href={localizedPath(locale, "/contacts")}>{t("footer.contacts")}</Link>
          </nav>
        </div>

        {socialProfiles.length > 0 ? (
          <section className="footer-social" aria-labelledby="footer-social-title">
            <div className="footer-social-copy">
              <p className="footer-column-title" id="footer-social-title">{t("footer.socialTitle")}</p>
              <p>{t("footer.socialDescription")}</p>
            </div>
            <SocialLinks
              profiles={socialProfiles}
              ariaLabel={t("footer.socialAria")}
              className="footer-social-links"
            />
          </section>
        ) : null}
      </div>

      <div className="footer-bottom">
        <p>{t("footer.copyright")}</p>
      </div>
    </footer>
  );
}
