// Shared by the browser and server Sentry clients. Reports carry no personal
// data (no IP, cookies or user ids) and session replay is not used.
export function sentryOptions(dsn: string, tracesSampleRate: string | undefined) {
  const rate = Number(tracesSampleRate ?? "0");
  return {
    dsn,
    environment: process.env.NEXT_PUBLIC_SENTRY_ENVIRONMENT || "production",
    release: process.env.NEXT_PUBLIC_APP_VERSION ? `quran-platform-web@${process.env.NEXT_PUBLIC_APP_VERSION}` : undefined,
    sendDefaultPii: false,
    tracesSampleRate: Number.isFinite(rate) && rate >= 0 && rate <= 1 ? rate : 0,
  };
}
