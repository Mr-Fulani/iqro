"use client";

import Link from "next/link";
import Image from "next/image";
import type { SocialProfile } from "../lib/api";
import { useI18n } from "../lib/i18n-context";
import { localizedPath } from "../lib/routing";
import { SocialLinks } from "./social/SocialLinks";
import { MobileDisclosure } from "./MobileDisclosure";

type FooterProps = {
  socialProfiles?: SocialProfile[];
};

export function Footer({ socialProfiles = [] }: FooterProps) {
  const { locale, t } = useI18n();
  const appDownloadUrl = process.env.NEXT_PUBLIC_ANDROID_APP_DOWNLOAD_URL?.trim();
  const appStoreUrl = process.env.NEXT_PUBLIC_IOS_APP_STORE_URL?.trim();
  const playStoreUrl = process.env.NEXT_PUBLIC_ANDROID_PLAY_STORE_URL?.trim();
  const stores = [
    { name: "App Store", url: appStoreUrl, soon: t("footer.iosSoon") },
    { name: "Google Play", url: playStoreUrl, soon: t("footer.androidSoon") },
  ];
  return (
    <footer className="app-footer">
      <MobileDisclosure title={t("footer.aboutLinks")} className="mobile-footer-details">
        <div className="footer-content">
          <div className="footer-brand">
            <Image src="/iqro-wax-seal.png" alt="" width={40} height={40} sizes="40px" className="brand-logo brand-logo-sm" />
            <p>
              <strong>IQRO</strong> — {t("footer.description")}
            </p>
            <section className="footer-mobile-app" aria-labelledby="footer-mobile-app-title">
              <h2 id="footer-mobile-app-title" className="sr-only">{t("footer.mobileAppTitle")}</h2>
              <div className="footer-app-stores">
                {stores.map((store) => store.url ? (
                  <a key={store.name} className="footer-store-badge" href={store.url}>
                    <span>{t("footer.storeDownload")}</span>
                    <strong>{store.name}</strong>
                  </a>
                ) : (
                  <div key={store.name} className="footer-store-badge">
                    <span>{store.soon}</span>
                    <strong>{store.name}</strong>
                  </div>
                ))}
              </div>
              {appDownloadUrl && !playStoreUrl ? (
                <a className="btn btn-primary footer-app-download" href={appDownloadUrl}>
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
                    <path d="M12 3v12m-5-5 5 5 5-5M5 16v5h14v-5" />
                  </svg>
                  {t("footer.mobileAppDownload")}
                </a>
              ) : null}
            </section>
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
              <Link href={localizedPath(locale, "/salah")}>{t("nav.salah")}</Link>
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

      </MobileDisclosure>

      <div className="footer-bottom">
        <p>{t("footer.copyright")}</p>
      </div>
    </footer>
  );
}
