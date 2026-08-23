import { NextRequest, NextResponse } from "next/server";
import {
  setInstallationCookies,
  validInstallationIdentity,
} from "../../../../lib/server-auth";

export async function POST(request: NextRequest) {
  const origin = request.headers.get("Origin");
  if (origin && origin !== request.nextUrl.origin) {
    return NextResponse.json(
      { code: "cross_origin_request", detail: "Cross-origin request rejected." },
      { status: 403, headers: { "Cache-Control": "private, no-store" } },
    );
  }
  const input: unknown = await request.json();
  if (!validInstallationIdentity(input)) {
    return NextResponse.json(
      { code: "invalid_installation_identity", detail: "Invalid installation identity." },
      { status: 400, headers: { "Cache-Control": "private, no-store" } },
    );
  }
  return setInstallationCookies(
    new NextResponse(null, {
      status: 204,
      headers: { "Cache-Control": "private, no-store" },
    }),
    input,
  );
}
