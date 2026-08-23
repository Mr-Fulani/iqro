import { NextRequest, NextResponse } from "next/server";
import {
  backendRequest,
  clearRefreshCookie,
  forwardBackendResponse,
} from "../../../../lib/server-auth";

export async function POST(request: NextRequest) {
  const authorization = request.headers.get("Authorization");
  if (!authorization) {
    return clearRefreshCookie(
      new NextResponse(null, {
        status: 204,
        headers: { "Cache-Control": "private, no-store" },
      }),
    );
  }
  const response = await backendRequest("/api/v1/auth/logout", {
    method: "POST",
    headers: { Authorization: authorization },
  });
  if (!response.ok && response.status !== 401) {
    return clearRefreshCookie(await forwardBackendResponse(response));
  }
  return clearRefreshCookie(
    new NextResponse(null, {
      status: 204,
      headers: { "Cache-Control": "private, no-store" },
    }),
  );
}
