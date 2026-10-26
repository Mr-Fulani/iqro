import { NextRequest } from "next/server";
import {
  authenticatedResponse,
  backendRequest,
  forwardBackendResponse,
  parseBackendTokens,
} from "../../../../lib/server-auth";

export async function POST(request: NextRequest) {
  const authorization = request.headers.get("Authorization");
  if (!authorization) {
    return new Response(null, {
      status: 401,
      headers: { "Cache-Control": "private, no-store" },
    });
  }
  const response = await backendRequest("/api/v1/auth/google", {
    method: "POST",
    headers: {
      Authorization: authorization,
      "Content-Type": "application/json",
    },
    body: await request.text(),
  });
  if (!response.ok) return forwardBackendResponse(response);
  return authenticatedResponse(await parseBackendTokens(response));
}
