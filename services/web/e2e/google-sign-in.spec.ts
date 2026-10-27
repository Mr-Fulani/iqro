import { expect, Page, test } from "@playwright/test";

const guestSession = {
  token_type: "Bearer",
  access_token: "guest-access-token",
  expires_in: 900,
  access_expires_at: "2026-08-23T18:15:00Z",
  user: {
    id: "00000000-0000-7000-8000-000000000101",
    status: "guest",
    preferred_locale: "ru",
    email: null,
    deletion_requested_at: null,
    deletion_scheduled_for: null,
  },
  device: {
    id: "00000000-0000-7000-8000-000000000201",
    platform: "web",
    locale: "ru",
    app_version: "1.0.0",
    bootstrap_generation: 1,
  },
};

const googleSession = {
  ...guestSession,
  access_token: "google-access-token",
  user: {
    ...guestSession.user,
    id: "00000000-0000-7000-8000-000000000102",
    status: "active",
    email: "reader@gmail.com",
  },
  merged_guest: false,
  replayed: false,
};

// Stands in for https://accounts.google.com/gsi/client: the button hands back
// a credential at once, and every call is recorded for the assertions.
const FAKE_GSI = `
window.__gsi = { prompts: 0, cancels: 0, autoSelectDisabled: 0, initialized: null };
window.google = { accounts: { id: {
  initialize(options) { window.__gsi.initialized = options; },
  renderButton(parent) {
    parent.replaceChildren();
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = "Продолжить как Reader";
    button.onclick = () => window.__gsi.initialized.callback({ credential: "header.payload.signature" });
    parent.appendChild(button);
  },
  prompt() { window.__gsi.prompts += 1; },
  cancel() { window.__gsi.cancels += 1; },
  disableAutoSelect() { window.__gsi.autoSelectDisabled += 1; },
} } };
`;

async function installMocks(page: Page, { enabled, signedIn }: { enabled: boolean; signedIn: boolean }) {
  await page.route("https://accounts.google.com/gsi/client", (route) =>
    route.fulfill({ contentType: "text/javascript", body: FAKE_GSI }),
  );
  await page.route("**/api/web-auth/refresh", (route) =>
    signedIn ? route.fulfill({ json: googleSession }) : route.fulfill({ status: 401 }),
  );
  await page.route("**/api/web-auth/guest", (route) => route.fulfill({ json: guestSession }));
  await page.route("**/api/web-auth/logout", (route) => route.fulfill({ status: 204 }));
  await page.route("**/api/web-auth/google", (route) => route.fulfill({ json: googleSession }));
  await page.route("**/api/v1/**", async (route) => {
    const path = new URL(route.request().url()).pathname;
    if (path === "/api/v1/auth/google/config") {
      await route.fulfill({
        json: enabled
          ? { enabled: true, client_id: "1234-web.apps.googleusercontent.com" }
          : { enabled: false, client_id: null },
      });
    } else if (path.endsWith("/bookmarks")) {
      await route.fulfill({ json: { next: null, previous: null, results: [] } });
    } else if (path.endsWith("/me/devices") || path.endsWith("/feedback/tickets")) {
      await route.fulfill({ json: [] });
    } else {
      await route.fulfill({ status: 404, json: { detail: `Unhandled ${path}` } });
    }
  });
}

test("Google button and One Tap sign the guest in with the ID token", async ({ page }) => {
  await installMocks(page, { enabled: true, signedIn: false });
  await page.goto("/login");

  const googleButton = page.getByRole("button", { name: "Продолжить как Reader" });
  await expect(googleButton).toBeVisible();
  await expect(page.getByText("или по коду на почту")).toBeVisible();
  // The email code stays available as the fallback.
  await expect(page.getByLabel("Email")).toBeVisible();
  const gsi = await page.evaluate(() => (window as unknown as { __gsi: { prompts: number; initialized: { client_id: string; auto_select: boolean } } }).__gsi);
  expect(gsi.prompts).toBe(1);
  expect(gsi.initialized.client_id).toBe("1234-web.apps.googleusercontent.com");
  expect(gsi.initialized.auto_select).toBe(false);

  const signIn = page.waitForRequest("**/api/web-auth/google");
  await googleButton.click();
  const request = await signIn;
  expect(request.postDataJSON()).toEqual({ id_token: "header.payload.signature" });
  expect(request.headers().authorization).toBe("Bearer guest-access-token");

  // Opened directly, the sign-in page returns to the profile, as with an email code.
  await expect(page).toHaveURL(/\/profile$/);
  await expect(page.getByText("reader@gmail.com").first()).toBeVisible();
  const storageDump = await page.evaluate(() => JSON.stringify({ ...localStorage }));
  expect(storageDump).not.toContain("google-access-token");
  expect(storageDump).not.toContain("header.payload.signature");
});

test("without configured client IDs the page shows only the email code", async ({ page }) => {
  let gsiRequested = false;
  await installMocks(page, { enabled: false, signedIn: false });
  page.on("request", (request) => {
    if (request.url().startsWith("https://accounts.google.com/")) gsiRequested = true;
  });
  await page.goto("/login");

  await expect(page.getByLabel("Email")).toBeVisible();
  await expect(page.getByText("или по коду на почту")).toHaveCount(0);
  expect(gsiRequested).toBe(false);
});

test("switching account signs out and reopens the Google account chooser", async ({ page }) => {
  await installMocks(page, { enabled: true, signedIn: true });
  await page.goto("/profile");
  await expect(page.getByText("reader@gmail.com").first()).toBeVisible();

  // The profile never loads GIS itself; record the call the login page makes.
  const logout = page.waitForRequest("**/api/web-auth/logout");
  await page.getByRole("button", { name: "Сменить аккаунт" }).click();
  await logout;

  await expect(page).toHaveURL(/\/login$/);
  await expect(page.getByRole("button", { name: "Продолжить как Reader" })).toBeVisible();
  await expect.poll(() => page.evaluate(() => (window as unknown as { __gsi: { prompts: number } }).__gsi.prompts)).toBe(1);
});
