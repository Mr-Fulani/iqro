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
  const response = await backendRequest("/api/v1/auth/logout-all", {
    method: "POST",
    headers: { Authorization: authorization },
  });
  if (response.status === 401) {
    return clearRefreshCookie(
      new NextResponse(null, {
        status: 204,
        headers: { "Cache-Control": "private, no-store" },
      }),
    );
  }
  if (!response.ok) return forwardBackendResponse(response);
  return clearRefreshCookie(
    new NextResponse(null, {
      status: 204,
      headers: { "Cache-Control": "private, no-store" },
    }),
  );
}
