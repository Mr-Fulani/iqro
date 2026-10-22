import { defineConfig, devices } from "@playwright/test";

const externalBaseUrl = process.env.PLAYWRIGHT_BASE_URL;
const productionMode = process.env.PLAYWRIGHT_PRODUCTION === "1";
// Other checkouts on this machine may hold the default ports: override them per run.
const webPort = process.env.PLAYWRIGHT_WEB_PORT || (productionMode ? "3101" : "3100");
const baseURL = externalBaseUrl || `http://127.0.0.1:${webPort}`;
const mockPublicApiUrl = `http://127.0.0.1:${process.env.MOCK_PUBLIC_API_PORT || 3199}`;
const chromiumExecutablePath = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH;

export default defineConfig({
  testDir: "./e2e",
  fullyParallel: true,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 1 : 0,
  // Next.js 16 Turbopack can corrupt cold dynamic-route artifacts when several
  // browser workers request the same not-yet-compiled segment concurrently.
  workers: 1,
  reporter: process.env.CI ? "line" : "list",
  use: {
    baseURL,
    locale: "ru-RU",
    screenshot: "only-on-failure",
    trace: "on-first-retry",
    video: process.env.PLAYWRIGHT_DISABLE_VIDEO === "1" ? "off" : "retain-on-failure",
  },
  projects: [
    {
      name: "chromium",
      use: {
        ...devices["Desktop Chrome"],
        launchOptions: chromiumExecutablePath
          ? { executablePath: chromiumExecutablePath }
          : undefined,
      },
    },
  ],
  webServer: externalBaseUrl
    ? undefined
    : [
        {
          command: "node e2e/mock-public-api.mjs",
          url: `${mockPublicApiUrl}/api/v1/quran/editions`,
          reuseExistingServer: !process.env.CI,
          timeout: 30_000,
          stdout: "ignore",
          stderr: "pipe",
        },
        {
          command: productionMode
            ? "node scripts/production-test-server.mjs"
            : `npm run dev -- --hostname 127.0.0.1 --port ${webPort}`,
          url: baseURL,
          env: {
            IQRO_E2E: "1",
            // Like production: the server renders in UTC, visitors live elsewhere.
            TZ: "UTC",
            SITE_URL: baseURL,
            BACKEND_INTERNAL_URL: mockPublicApiUrl,
            HOSTNAME: "127.0.0.1",
            PORT: webPort,
            WEB_CONTENT_REVALIDATION_SECRET: "test-only-content-revalidation-secret-0001",
          },
          reuseExistingServer: !productionMode && !process.env.CI,
          timeout: productionMode ? 180_000 : 120_000,
          stdout: "ignore",
          stderr: "pipe",
        },
      ],
});
