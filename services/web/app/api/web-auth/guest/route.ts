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
  const identity = validInstallationIdentity(storedIdentity)
    ? storedIdentity
    : newInstallationIdentity();
  const response = await backendRequest("/api/v1/auth/guest", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      ...identity,
      platform: "web",
      locale: input.locale || "ru",
      app_version: input.app_version || "1.0.0",
    }),
  });
  if (!response.ok) {
    return setInstallationCookies(await forwardBackendResponse(response), identity);
  }
  return setInstallationCookies(
    authenticatedResponse(await parseBackendTokens(response)),
    identity,
  );
}
