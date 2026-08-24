import { defineConfig, devices } from "@playwright/test";

const externalBaseUrl = process.env.PLAYWRIGHT_BASE_URL;
const productionMode = process.env.PLAYWRIGHT_PRODUCTION === "1";
const baseURL = externalBaseUrl || `http://127.0.0.1:${productionMode ? 3101 : 3100}`;
const mockPublicApiUrl = "http://127.0.0.1:3199";

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
    video: "retain-on-failure",
  },
  projects: [
    {
      name: "chromium",
      use: { ...devices["Desktop Chrome"] },
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
            : "npm run dev -- --hostname 127.0.0.1 --port 3100",
          url: baseURL,
          env: {
            SITE_URL: baseURL,
            BACKEND_INTERNAL_URL: mockPublicApiUrl,
            HOSTNAME: "127.0.0.1",
            PORT: productionMode ? "3101" : "3100",
            WEB_CONTENT_REVALIDATION_SECRET: "test-only-content-revalidation-secret-0001",
          },
          reuseExistingServer: !productionMode && !process.env.CI,
          timeout: productionMode ? 180_000 : 120_000,
          stdout: "ignore",
          stderr: "pipe",
        },
      ],
});
