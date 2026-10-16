import { sentryEnvelopeTarget } from "@/lib/sentry-tunnel";

export const runtime = "nodejs";
// Sentry caps envelopes at 1 MB compressed; browser events are far smaller.
const MAX_ENVELOPE_BYTES = 1_000_000;

export async function POST(request: Request): Promise<Response> {
  const declaredLength = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(declaredLength) && declaredLength > MAX_ENVELOPE_BYTES) {
    return new Response(null, { status: 413 });
  }
  let envelope: string;
  try {
    envelope = await request.text();
  } catch {
    return new Response(null, { status: 400 });
  }
  if (Buffer.byteLength(envelope, "utf8") > MAX_ENVELOPE_BYTES) {
    return new Response(null, { status: 413 });
  }

  const target = sentryEnvelopeTarget(envelope, process.env.NEXT_PUBLIC_SENTRY_DSN);
  if (!target) return new Response(null, { status: 404 });
  try {
    const upstream = await fetch(target, {
      method: "POST",
      body: envelope,
      headers: { "Content-Type": "application/x-sentry-envelope" },
      signal: AbortSignal.timeout(5_000),
    });
    return new Response(null, { status: upstream.ok ? 200 : 502 });
  } catch {
    return new Response(null, { status: 502 });
  }
}
