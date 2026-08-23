import { NextRequest } from "next/server";
import { backendRequest, forwardBackendResponse } from "../../../../../lib/server-auth";

export async function POST(request: NextRequest) {
  const authorization = request.headers.get("Authorization");
  if (!authorization) {
    return new Response(null, {
      status: 401,
      headers: { "Cache-Control": "private, no-store" },
    });
  }
  const response = await backendRequest("/api/v1/auth/email/start", {
    method: "POST",
    headers: {
      Authorization: authorization,
      "Content-Type": "application/json",
    },
    body: await request.text(),
  });
  return forwardBackendResponse(response);
}
