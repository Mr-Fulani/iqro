"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState, useSyncExternalStore } from "react";
import {
  ANALYTICS_CONSENT_EVENT,
  ANALYTICS_CONSENT_KEY,
  analyticsConfig,
  hasAnalytics,
  readConsent,
  removeAnalyticsData,
  startAnalytics,
  trackPageView,
  writeConsent,
  type AnalyticsConsent as Consent,
} from "../lib/analytics";
import { useI18n } from "../lib/i18n-context";
import { localizedPath } from "../lib/routing";

const config = analyticsConfig();

function subscribe(onChange: () => void) {
  const onStorage = (event: StorageEvent) => {
    if (event.key === ANALYTICS_CONSENT_KEY) onChange();
  };
  window.addEventListener(ANALYTICS_CONSENT_EVENT, onChange);
  window.addEventListener("storage", onStorage);
  return () => {
    window.removeEventListener(ANALYTICS_CONSENT_EVENT, onChange);
    window.removeEventListener("storage", onStorage);
  };
}

/**
 * True after the visitor's first scroll, tap or key press. The browser stops
 * measuring the largest contentful paint at that moment, so a banner shown
 * afterwards never becomes the page's LCP.
 */
function useFirstInteraction(): boolean {
  const [interacted, setInteracted] = useState(false);
  useEffect(() => {
    const events = ["pointerdown", "keydown", "scroll", "touchstart"] as const;
    const done = () => {
      setInteracted(true);
      events.forEach((name) => window.removeEventListener(name, done));
    };
    events.forEach((name) => window.addEventListener(name, done, { passive: true }));
    return () => events.forEach((name) => window.removeEventListener(name, done));
  }, []);
  return interacted;
}

/** The server and the first client render know nothing yet: "pending". */
function useConsent(): Consent | null | "pending" {
  return useSyncExternalStore(subscribe, readConsent, () => "pending");
}

/**
 * Starts the counters for a visitor who agreed, reports client-side page views
 * and, until the visitor decides, shows the banner after the first interaction.
 */
export function AnalyticsConsent() {
  const { locale, t } = useI18n();
  const consent = useConsent();
  const interacted = useFirstInteraction();
  const pathname = usePathname();

  useEffect(() => {
    if (consent === "granted") startAnalytics(config);
    if (consent === "denied" && hasAnalytics(config)) removeAnalyticsData();
  }, [consent]);

  useEffect(() => {
    trackPageView();
  }, [pathname]);

  if (!hasAnalytics(config) || consent !== null || !interacted) return null;
  return (
    <section className="analytics-consent" aria-label={t("analytics.bannerTitle")} data-testid="analytics-consent">
      <p>
        {t("analytics.bannerText")}{" "}
        <Link href={localizedPath(locale, "/cookies")}>{t("analytics.more")}</Link>
      </p>
      <div className="analytics-consent-actions">
        <button type="button" className="btn btn-secondary btn-sm" onClick={() => writeConsent("denied")}>
          {t("analytics.decline")}
        </button>
        <button type="button" className="btn btn-primary btn-sm" onClick={() => writeConsent("granted")}>
          {t("analytics.accept")}
        </button>
      </div>
    </section>
  );
}

/** The choice on /cookies, where it can be changed at any time. */
export function AnalyticsConsentSettings() {
  const { t } = useI18n();
  const consent = useConsent();
  if (!hasAnalytics(config) || consent === "pending") return null;

  const withdraw = () => {
    writeConsent("denied");
    // Reloading stops the counters' scripts that are already running.
    window.location.reload();
  };

  return (
    <section className="surface legal-section analytics-consent-settings" data-testid="analytics-consent-settings">
      <h2 className="surface-title">{t("analytics.settingsTitle")}</h2>
      <p>
        {consent === "granted"
          ? t("analytics.stateGranted")
          : consent === "denied"
            ? t("analytics.stateDenied")
            : t("analytics.stateUnset")}
      </p>
      {consent === "granted" ? (
        <button type="button" className="btn btn-secondary btn-sm" onClick={withdraw}>
          {t("analytics.withdraw")}
        </button>
      ) : (
        <button type="button" className="btn btn-primary btn-sm" onClick={() => writeConsent("granted")}>
          {t("analytics.allow")}
        </button>
      )}
    </section>
  );
}
