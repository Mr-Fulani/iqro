import type { Instrumentation } from "next";

// Server-side error reporting (Sentry, EU region); off without a DSN.
const dsn = process.env.NEXT_PUBLIC_SENTRY_DSN;

export async function register(): Promise<void> {
  if (!dsn || process.env.NEXT_RUNTIME !== "nodejs") return;
  const [Sentry, { sentryOptions }] = await Promise.all([
    import("@sentry/nextjs"),
    import("./lib/sentry-options"),
  ]);
  Sentry.init(sentryOptions(dsn, process.env.SENTRY_TRACES_SAMPLE_RATE));
}

export const onRequestError: Instrumentation.onRequestError = async (...args) => {
  if (!dsn || process.env.NEXT_RUNTIME !== "nodejs") return;
  const { captureRequestError } = await import("@sentry/nextjs");
  captureRequestError(...args);
};
