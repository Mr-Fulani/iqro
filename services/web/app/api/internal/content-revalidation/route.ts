import { createHash, timingSafeEqual } from "node:crypto";
import { parseContentChange, revalidateContentChange } from "@/lib/content-revalidation";

export const runtime = "nodejs";
const MAX_EVENT_BYTES = 4_096;

function digest(value: string): Buffer {
  return createHash("sha256").update(value, "utf8").digest();
}

function authorized(request: Request, secret: string): boolean {
  const authorization = request.headers.get("authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return false;
  return timingSafeEqual(digest(authorization.slice(7)), digest(secret));
}

function unavailable(): Response {
  return Response.json({ detail: "Not found." }, { status: 404 });
}

export async function POST(request: Request): Promise<Response> {
  const secret = process.env.WEB_CONTENT_REVALIDATION_SECRET?.trim() ?? "";
  if (secret.length < 32 || !authorized(request, secret)) return unavailable();

  const declaredLength = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(declaredLength) && declaredLength > MAX_EVENT_BYTES) {
    return Response.json({ detail: "Request body is too large." }, { status: 413 });
  }

  let rawBody: string;
  try {
    rawBody = await request.text();
  } catch {
    return Response.json({ detail: "Invalid JSON body." }, { status: 400 });
  }
  if (Buffer.byteLength(rawBody, "utf8") > MAX_EVENT_BYTES) {
    return Response.json({ detail: "Request body is too large." }, { status: 413 });
  }

  let payload: unknown;
  try {
    payload = JSON.parse(rawBody);
  } catch {
    return Response.json({ detail: "Invalid JSON body." }, { status: 400 });
  }

  const change = parseContentChange(payload);
  if (!change) {
    return Response.json({ detail: "Invalid content change event." }, { status: 422 });
  }

  revalidateContentChange(change);
  return Response.json({ accepted: true, type: change.type });
}
