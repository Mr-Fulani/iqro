import { defineConfig, devices } from "@playwright/test";

const externalBaseUrl = process.env.PLAYWRIGHT_BASE_URL;
const baseURL = externalBaseUrl || "http://127.0.0.1:3100";
const mockPublicApiUrl = "http://127.0.0.1:3199";

export default defineConfig({
  testDir: "./e2e",
  fullyParallel: true,
  forbidOnly: Boolean(process.env.CI),
  retries: process.env.CI ? 1 : 0,
  workers: process.env.CI ? 1 : undefined,
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
          command: "npm run dev -- --hostname 127.0.0.1 --port 3100",
          url: baseURL,
          env: {
            SITE_URL: baseURL,
            BACKEND_INTERNAL_URL: mockPublicApiUrl,
            WEB_CONTENT_REVALIDATION_SECRET: "test-only-content-revalidation-secret-0001",
          },
          reuseExistingServer: !process.env.CI,
          timeout: 120_000,
          stdout: "ignore",
          stderr: "pipe",
        },
      ],
});
