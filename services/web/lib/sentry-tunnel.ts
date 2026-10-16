// Browser error reports reach Sentry through this site's /monitoring route, so
// they need no CSP exception and are not dropped by content blockers. The route
// forwards only envelopes addressed to the project this deployment is
// configured for; anything else is rejected, so it cannot act as an open proxy.

type ParsedDsn = { host: string; projectId: string; publicKey: string };

function parseDsn(dsn: string): ParsedDsn | null {
  try {
    const url = new URL(dsn);
    const projectId = url.pathname.replace(/^\/+|\/+$/g, "");
    if (url.protocol !== "https:" || !url.username || !/^\d+$/.test(projectId)) return null;
    return { host: url.host, projectId, publicKey: url.username };
  } catch {
    return null;
  }
}

/** Sentry ingest URL for an envelope, or null when it is not for our project. */
export function sentryEnvelopeTarget(envelope: string, configuredDsn: string | undefined): string | null {
  const configured = configuredDsn ? parseDsn(configuredDsn) : null;
  if (!configured) return null;
  const headerLine = envelope.slice(0, envelope.indexOf("\n") === -1 ? undefined : envelope.indexOf("\n"));
  let header: unknown;
  try {
    header = JSON.parse(headerLine);
  } catch {
    return null;
  }
  const dsn = typeof header === "object" && header !== null ? (header as { dsn?: unknown }).dsn : undefined;
  const requested = typeof dsn === "string" ? parseDsn(dsn) : null;
  if (
    !requested ||
    requested.host !== configured.host ||
    requested.projectId !== configured.projectId ||
    requested.publicKey !== configured.publicKey
  ) {
    return null;
  }
  return `https://${configured.host}/api/${configured.projectId}/envelope/`;
}
