import { createRequire } from "node:module";

const require = createRequire(import.meta.url);

/** @type {import('next').NextConfig} */
const backendUrl =
  process.env.BACKEND_INTERNAL_URL ||
  process.env.NEXT_PUBLIC_API_BASE_URL ||
  "http://127.0.0.1:8000";

const isDevelopment = process.env.NODE_ENV === "development";
// Visit statistics, loaded only after consent (lib/analytics.ts): GA4 and
// Yandex Metrica. Their hits go over https:, which connect-src and img-src
// already allow; only the scripts, Metrica's frame and Webvisor's socket need
// hosts. Every response carries this header, so the list stays short.
// ops/gateway/security-headers.conf repeats the same sources.
const metricaHosts = ["mc.yandex.ru", "mc.yandex.com"];
const analyticsScriptSources = [
  "https://*.googletagmanager.com",
  "https://yastatic.net",
  ...metricaHosts.map((host) => `https://${host}`),
].join(" ");
const analyticsFrameSources = metricaHosts.map((host) => `https://${host}`).join(" ");
const analyticsSocketSources = metricaHosts.map((host) => `wss://${host}`).join(" ");
// "Sign in with Google" (components/GoogleSignIn.tsx): the GIS script, its
// button stylesheet and the One Tap / button iframe. Its requests go over
// https:, which connect-src already allows.
const googleIdentitySource = "https://accounts.google.com/gsi/";
const contentSecurityPolicy = [
  "default-src 'self'",
  `script-src 'self' 'unsafe-inline'${isDevelopment ? " 'unsafe-eval'" : ""} ${analyticsScriptSources} ${googleIdentitySource}client`,
  `style-src 'self' 'unsafe-inline' ${googleIdentitySource}style`,
  "font-src 'self' data: https://verses.quran.foundation https://static-cdn.tarteel.ai",
  `img-src 'self' blob: data: https:${isDevelopment ? " http:" : ""}`,
  `media-src 'self' blob: https:${isDevelopment ? " http:" : ""}`,
  `connect-src 'self' https: ${analyticsSocketSources}${isDevelopment ? " http: ws: wss:" : ""}`,
  "worker-src 'self' blob:",
  "manifest-src 'self'",
  `frame-src ${analyticsFrameSources} ${googleIdentitySource}`,
  "object-src 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "frame-ancestors 'none'",
  ...(isDevelopment ? [] : ["upgrade-insecure-requests"]),
].join("; ");

const securityHeaders = [
  { key: "Content-Security-Policy", value: contentSecurityPolicy },
  // GIS falls back to a popup where FedCM is unavailable; it must keep its opener.
  { key: "Cross-Origin-Opener-Policy", value: "same-origin-allow-popups" },
  { key: "Permissions-Policy", value: "camera=(), microphone=(), geolocation=(self), payment=(), usb=()" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "Strict-Transport-Security", value: "max-age=31536000; includeSubDomains" },
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "X-Frame-Options", value: "DENY" },
  { key: "X-Permitted-Cross-Domain-Policies", value: "none" },
];

const nextConfig = {
  ...(process.env.IQRO_E2E === "1" ? { devIndicators: false } : {}),
  allowedDevOrigins: [
    "127.0.0.1", "10.0.2.2",
    ...(process.env.LOCAL_WEB_ALLOWED_ORIGINS || "").split(",").map((host) => host.trim()).filter(Boolean),
  ],
  output: "standalone",
  cacheHandler: require.resolve("./cache/incremental-cache-handler.cjs"),
  cacheHandlers: {
    default: require.resolve("./cache/use-cache-handler.cjs"),
    remote: require.resolve("./cache/use-cache-handler.cjs"),
  },
  cacheMaxMemorySize: 0,
  poweredByHeader: false,
  reactStrictMode: true,
  async headers() {
    return [{ source: "/:path*", headers: securityHeaders }];
  },
  async rewrites() {
    return [
      {
        source: "/api/:path*",
        destination: `${backendUrl}/api/:path*`,
      },
      {
        source: "/media/:path*",
        destination: `${backendUrl}/media/:path*`,
      },
    ];
  },
};

export default nextConfig;
