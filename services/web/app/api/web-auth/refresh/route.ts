import { NextRequest } from "next/server";
import {
  authenticatedResponse,
  backendRequest,
  clearRefreshCookie,
  forwardBackendResponse,
  parseBackendTokens,
  REFRESH_COOKIE_NAME,
} from "../../../../lib/server-auth";

export async function POST(request: NextRequest) {
  const refreshToken = request.cookies.get(REFRESH_COOKIE_NAME)?.value;
  if (!refreshToken) {
    return new Response(null, {
      status: 401,
      headers: { "Cache-Control": "private, no-store" },
    });
  }
  const tokenResponse = await backendRequest("/api/v1/auth/token/refresh", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ refresh_token: refreshToken }),
  });
  if (!tokenResponse.ok) {
    return clearRefreshCookie(await forwardBackendResponse(tokenResponse));
  }
  const tokens = await parseBackendTokens(tokenResponse);
  const meResponse = await backendRequest("/api/v1/me", {
    method: "GET",
    headers: { Authorization: `Bearer ${tokens.access_token}` },
  });
  if (!meResponse.ok) {
    return clearRefreshCookie(await forwardBackendResponse(meResponse));
  }
  const current = (await meResponse.json()) as { user: unknown; device: unknown };
  return authenticatedResponse({ ...tokens, ...current });
}
