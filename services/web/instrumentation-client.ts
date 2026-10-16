// Error reporting and Web Vitals (Sentry, EU region). The DSN is inlined at
// build time; without it nothing is loaded. With it, the SDK chunk loads only
// after the page has finished loading, so it never competes with LCP.
const dsn = process.env.NEXT_PUBLIC_SENTRY_DSN;

if (dsn) {
  const start = () => {
    void import("./lib/sentry-browser").then(({ startBrowserErrorReporting }) => startBrowserErrorReporting(dsn));
  };
  if (document.readyState === "complete") start();
  else window.addEventListener("load", start, { once: true });
}
