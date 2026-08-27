import { NextRequest } from "next/server";
import {
  authenticatedResponse,
  backendRequest,
  forwardBackendResponse,
  INSTALLATION_CREDENTIAL_COOKIE_NAME,
  INSTALLATION_ID_COOKIE_NAME,
  newInstallationIdentity,
  parseBackendTokens,
  setInstallationCookies,
  validInstallationIdentity,
} from "../../../../lib/server-auth";

export async function POST(request: NextRequest) {
  const input = (await request.json()) as { locale?: string; app_version?: string };
  const storedId = request.cookies.get(INSTALLATION_ID_COOKIE_NAME)?.value;
  const storedCredential = request.cookies.get(INSTALLATION_CREDENTIAL_COOKIE_NAME)?.value;
  const storedIdentity = {
    installation_id: storedId,
    installation_credential: storedCredential,
  };
  let identity = validInstallationIdentity(storedIdentity)
    ? storedIdentity
    : newInstallationIdentity();
  let response = await bootstrapGuest(identity, input);
  if (await guestBootstrapUnavailable(response)) {
    identity = newInstallationIdentity();
    response = await bootstrapGuest(identity, input);
  }
  if (!response.ok) {
    return setInstallationCookies(await forwardBackendResponse(response), identity);
  }
  return setInstallationCookies(
    authenticatedResponse(await parseBackendTokens(response)),
    identity,
  );
}

function bootstrapGuest(
  identity: { installation_id: string; installation_credential: string },
  input: { locale?: string; app_version?: string },
): Promise<Response> {
  return backendRequest("/api/v1/auth/guest", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      ...identity,
      platform: "web",
      locale: input.locale || "ru",
      app_version: input.app_version || "1.0.0",
    }),
  });
}

async function guestBootstrapUnavailable(response: Response): Promise<boolean> {
  if (response.status !== 403) return false;
  try {
    const payload = (await response.clone().json()) as { code?: unknown };
    return payload.code === "guest_bootstrap_unavailable";
  } catch {
    return false;
  }
}
