import { NextRequest } from "next/server";
import {
  authenticatedResponse,
  backendRequest,
  forwardBackendResponse,
  INSTALLATION_CREDENTIAL_COOKIE_NAME,
  parseBackendTokens,
} from "../../../../../lib/server-auth";

export async function POST(request: NextRequest) {
  const installationCredential = request.cookies.get(
    INSTALLATION_CREDENTIAL_COOKIE_NAME,
  )?.value;
  if (!installationCredential) {
    return Response.json(
      { code: "installation_identity_missing", detail: "Installation identity is missing." },
      { status: 400, headers: { "Cache-Control": "private, no-store" } },
    );
  }
  const input = (await request.json()) as Record<string, unknown>;
  const response = await backendRequest("/api/v1/auth/email/verify", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      ...input,
      installation_credential: installationCredential,
    }),
  });
  if (!response.ok) return forwardBackendResponse(response);
  return authenticatedResponse(await parseBackendTokens(response));
}
