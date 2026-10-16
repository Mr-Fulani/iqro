import assert from "node:assert/strict";
import test from "node:test";

import { sentryEnvelopeTarget } from "./sentry-tunnel.ts";

const DSN = "https://publickey@o123.ingest.de.sentry.io/4567";
const envelope = (dsn: unknown) => `${JSON.stringify({ dsn, sent_at: "2026-10-16T00:00:00Z" })}\n{"type":"event"}\n{}`;

test("an envelope for the configured project is forwarded to its EU ingest endpoint", () => {
  assert.equal(sentryEnvelopeTarget(envelope(DSN), DSN), "https://o123.ingest.de.sentry.io/api/4567/envelope/");
});

test("the tunnel is closed when monitoring is not configured", () => {
  assert.equal(sentryEnvelopeTarget(envelope(DSN), undefined), null);
  assert.equal(sentryEnvelopeTarget(envelope(DSN), ""), null);
});

test("envelopes for another host, project or key are refused", () => {
  for (const other of [
    "https://publickey@evil.example/4567",
    "https://publickey@o123.ingest.de.sentry.io/9999",
    "https://otherkey@o123.ingest.de.sentry.io/4567",
    "http://publickey@o123.ingest.de.sentry.io/4567",
  ]) {
    assert.equal(sentryEnvelopeTarget(envelope(other), DSN), null, other);
  }
});

test("malformed envelopes are refused", () => {
  assert.equal(sentryEnvelopeTarget("not json\n{}", DSN), null);
  assert.equal(sentryEnvelopeTarget(envelope(42), DSN), null);
  assert.equal(sentryEnvelopeTarget("", DSN), null);
});
