import { NextResponse } from "next/server";
import { randomBytes, randomUUID } from "node:crypto";

export const REFRESH_COOKIE_NAME = "quran_refresh_v1";
export const INSTALLATION_ID_COOKIE_NAME = "quran_installation_id_v1";
export const INSTALLATION_CREDENTIAL_COOKIE_NAME = "quran_installation_credential_v1";

export type ServerInstallationIdentity = {
  installation_id: string;
  installation_credential: string;
};

type BackendTokenPayload = {
  token_type: string;
  access_token: string;
  expires_in: number;
  access_expires_at: string;
  refresh_token: string;
  refresh_expires_in: number;
  refresh_expires_at: string;
  user?: unknown;
  device?: unknown;
  merged_guest?: boolean;
  replayed?: boolean;
};

function backendBase(): string {
  return (
    process.env.BACKEND_INTERNAL_URL ||
    process.env.NEXT_PUBLIC_API_BASE_URL ||
    "http://127.0.0.1:8000"
  ).replace(/\/$/, "");
}

export async function backendRequest(path: string, init: RequestInit): Promise<Response> {
  return fetch(`${backendBase()}${path}`, {
    ...init,
    cache: "no-store",
  });
}

export async function forwardBackendResponse(response: Response): Promise<NextResponse> {
  const body = await response.text();
  return new NextResponse(body || null, {
    status: response.status,
    headers: {
      "Cache-Control": "private, no-store",
      "Content-Type": response.headers.get("Content-Type") || "application/json",
    },
  });
}

export function authenticatedResponse(payload: BackendTokenPayload): NextResponse {
  const response = NextResponse.json(
    {
      token_type: payload.token_type,
      access_token: payload.access_token,
      expires_in: payload.expires_in,
      access_expires_at: payload.access_expires_at,
      user: payload.user,
      device: payload.device,
      ...(payload.merged_guest === undefined
        ? {}
        : { merged_guest: payload.merged_guest }),
      ...(payload.replayed === undefined ? {} : { replayed: payload.replayed }),
    },
    { headers: { "Cache-Control": "private, no-store" } },
  );
  response.cookies.set(REFRESH_COOKIE_NAME, payload.refresh_token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/api/web-auth",
    expires: new Date(payload.refresh_expires_at),
  });
  return response;
}

export function clearRefreshCookie(response: NextResponse): NextResponse {
  response.cookies.set(REFRESH_COOKIE_NAME, "", {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax",
    path: "/api/web-auth",
    maxAge: 0,
  });
  return response;
}

export function newInstallationIdentity(): ServerInstallationIdentity {
  return {
    installation_id: randomUUID(),
    installation_credential: randomBytes(32).toString("base64url"),
  };
}

export function setInstallationCookies(
  response: NextResponse,
  identity: ServerInstallationIdentity,
): NextResponse {
  const options = {
    httpOnly: true,
    secure: process.env.NODE_ENV === "production",
    sameSite: "lax" as const,
    path: "/api/web-auth",
    maxAge: 400 * 24 * 60 * 60,
  };
  response.cookies.set(INSTALLATION_ID_COOKIE_NAME, identity.installation_id, options);
  response.cookies.set(
    INSTALLATION_CREDENTIAL_COOKIE_NAME,
    identity.installation_credential,
    options,
  );
  return response;
}

export function validInstallationIdentity(value: unknown): value is ServerInstallationIdentity {
  if (!value || typeof value !== "object") return false;
  const candidate = value as Record<string, unknown>;
  return (
    typeof candidate.installation_id === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      candidate.installation_id,
    ) &&
    typeof candidate.installation_credential === "string" &&
    /^[A-Za-z0-9_-]{43,128}$/.test(candidate.installation_credential)
  );
}

export async function parseBackendTokens(response: Response): Promise<BackendTokenPayload> {
  return (await response.json()) as BackendTokenPayload;
}
