import * as Sentry from "@sentry/nextjs";
import { sentryOptions } from "./sentry-options";

export function startBrowserErrorReporting(dsn: string): void {
  Sentry.init({
    ...sentryOptions(dsn, process.env.NEXT_PUBLIC_SENTRY_TRACES_SAMPLE_RATE),
    tunnel: "/monitoring",
    // Page-load traces carry the Web Vitals (LCP, INP, CLS, TTFB) of sampled visits.
    integrations: [Sentry.browserTracingIntegration()],
  });
}
