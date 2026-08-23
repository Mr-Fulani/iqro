# Verified email authentication and guest merge

## Contract

Email authentication is passwordless and starts from an authenticated installation. A web
client uses the same-origin Next.js BFF; native clients call the backend directly and keep the
installation credential in Keychain/Keystore.

```text
POST /api/v1/auth/email/start     Bearer access token, { email }
POST /api/v1/auth/email/verify    { challenge_id, code, installation_credential, idempotency_key }
GET  /api/v1/me                   Bearer access token
```

`email/start` returns `202` for both new and existing addresses. The normalized address and a
keyed HMAC of the six-digit code are stored; the plaintext code is never persisted. A challenge
is bound to its requester and device, expires after 10 minutes by default, permits five attempts
and invalidates an earlier open challenge for the same device/address. Delivery occurs after the
database transaction; a failed delivery invalidates the challenge and returns a normalized 503.

`email/verify` also requires proof of the installation credential and a client-generated UUID
idempotency key. A new address promotes the guest to an active account. An address already linked
to an active account triggers the transactional merge below. Repeating a completed verification
with the same installation and idempotency key is safe; a different key is rejected.

## Transactional merge

The guest and target account are locked in stable order. One database transaction:

- moves guest devices and revokes every old guest token family before issuing a new family;
- keeps the newest reading position per Quran edition and unions bookmarks and reminders;
- merges consent history and compact retired-ID ledgers;
- keeps the newest prayer profile and transfers feedback ownership;
- transfers linked identities and emits authoritative sync snapshots for the merged account;
- marks the source guest inactive/deleted and creates an immutable `GuestMergeAudit` record.

Any conflict or database error rolls the whole operation back. The audit is one-to-one with the
source guest and stores the target, verified trigger identity, idempotency key and moved counts.

## Browser session boundary

The Next.js routes under `/api/web-auth/**` are the browser session boundary. Refresh tokens and
the installation credential are `HttpOnly`, `SameSite=Lax`, `Secure` production cookies scoped to
that route prefix. The short-lived access token exists only in JavaScript memory. Neither token
nor the installation credential is written to `localStorage`.

An older browser installation is migrated once: its legacy installation pair is posted to the
same-origin `/api/web-auth/installation` route, converted to HttpOnly cookies, and then removed
from local storage. This preserves the existing guest identity while eliminating continued
JavaScript access to the credential.

## Configuration and operations

Local settings use Django's console mailer, so the verification code appears in the backend
terminal. Production requires independent `QURAN_EMAIL_CODE_HASH_KEY`, SMTP host/user/password,
TLS choice and `DJANGO_DEFAULT_FROM_EMAIL`; see `.env.production.example`. Never reuse Django's
secret key or any token-digest key for the email-code HMAC.

Rate limits are split between stable identity/challenge keys and high per-IP circuit breakers.
Consumed, invalidated or long-expired challenges are retained for 24 hours by default and pruned
hourly in bounded batches by `accounts.prune_email_challenges`. Production must run exactly one
Celery Beat scheduler.

Device inventory, selective revoke and grace-period account deletion/cancellation are documented
in [auth-and-sync.md](auth-and-sync.md) and exposed in the web cabinet. Remaining identity work is
safe unlink/change plus optional Google/Apple/Telegram providers. The cabinet also keeps global
`logout-all` behind an explicit confirmation step.
