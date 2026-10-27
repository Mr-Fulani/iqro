"""Sign in with a Google ID token from Google Identity Services or Credential Manager.

The client never sends us a password or an OAuth access token: it obtains a
signed OpenID Connect ID token and we verify it locally against Google's
published keys, then resolve it to an account exactly like an email code.
"""

from __future__ import annotations

import base64
import binascii
import json
import re
import uuid
from dataclasses import dataclass
from datetime import datetime
from typing import Any, TypeGuard
from urllib.request import Request, urlopen

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding
from cryptography.hazmat.primitives.asymmetric.rsa import RSAPublicKey, RSAPublicNumbers
from django.conf import settings
from django.core.cache import cache
from django.db import transaction
from django.utils import timezone
from django.views.decorators.debug import sensitive_variables

from quran_backend.modules.accounts.email_auth import (
    EmailVerificationResult,
    link_verified_identity,
)
from quran_backend.modules.accounts.exceptions import (
    GoogleEmailUnverified,
    GoogleSignInDisabled,
    GoogleSignInUnavailable,
    GoogleTokenInvalid,
)
from quran_backend.modules.accounts.models import Device, IdentityProvider, User
from quran_backend.modules.accounts.services import replace_device_credentials

GOOGLE_CERTS_URL = "https://www.googleapis.com/oauth2/v3/certs"
GOOGLE_ISSUERS = frozenset({"accounts.google.com", "https://accounts.google.com"})
CLOCK_SKEW_SECONDS = 60
JWKS_CACHE_KEY = "accounts:google-jwks:v1"
# An unknown key ID refetches the key set at most once a minute, so forged
# tokens cannot turn this endpoint into a request amplifier towards Google.
JWKS_REFRESH_GUARD_KEY = "accounts:google-jwks-refresh:v1"
JWKS_REFRESH_GUARD_SECONDS = 60
JWKS_DEFAULT_MAX_AGE_SECONDS = 60 * 60
JWKS_FETCH_TIMEOUT_SECONDS = 5
_MAX_AGE_PATTERN = re.compile(r"max-age=(\d+)")


@dataclass(frozen=True, slots=True)
class GoogleIdentity:
    subject: str
    email: str


def google_web_client_id() -> str:
    return str(getattr(settings, "QURAN_GOOGLE_WEB_CLIENT_ID", "") or "")


def google_client_ids() -> frozenset[str]:
    """Every audience we accept: the web client and the Android clients."""

    web = google_web_client_id()
    if not web:
        return frozenset()
    android = getattr(settings, "QURAN_GOOGLE_ANDROID_CLIENT_IDS", ())
    return frozenset({web, *(str(client_id) for client_id in android if client_id)})


def google_sign_in_enabled() -> bool:
    return bool(google_web_client_id())


@sensitive_variables("id_token")
def sign_in_with_google(*, user: User, device: Device, id_token: str) -> EmailVerificationResult:
    if not google_sign_in_enabled():
        raise GoogleSignInDisabled
    identity = verify_google_id_token(id_token)
    with transaction.atomic():
        target, locked_device, merged_guest = link_verified_identity(
            requester_id=user.id,
            device_id=device.id,
            provider=IdentityProvider.GOOGLE,
            provider_subject=identity.subject,
            email=identity.email,
            idempotency_key=uuid.uuid7(),
        )
        credentials = replace_device_credentials(user=target, device=locked_device)
    return EmailVerificationResult(
        user=target,
        device=locked_device,
        credentials=credentials,
        merged_guest=merged_guest,
        replayed=False,
    )


@sensitive_variables("id_token")
def verify_google_id_token(id_token: str, *, now: datetime | None = None) -> GoogleIdentity:
    """Check signature, issuer, audience, lifetime and the verified email."""

    parts = id_token.split(".")
    if len(parts) != 3:
        raise GoogleTokenInvalid
    header = _decode_json_segment(parts[0])
    claims = _decode_json_segment(parts[1])
    signature = _decode_segment(parts[2])
    key_id = header.get("kid")
    if header.get("alg") != "RS256" or not isinstance(key_id, str) or not key_id:
        raise GoogleTokenInvalid
    key = _signing_key(key_id)
    try:
        key.verify(
            signature,
            f"{parts[0]}.{parts[1]}".encode("ascii"),
            padding.PKCS1v15(),
            hashes.SHA256(),
        )
    except InvalidSignature as exc:
        raise GoogleTokenInvalid from exc

    timestamp = (now or timezone.now()).timestamp()
    expires_at = claims.get("exp")
    issued_at = claims.get("iat")
    if (
        claims.get("iss") not in GOOGLE_ISSUERS
        or claims.get("aud") not in google_client_ids()
        or not _is_number(expires_at)
        or not _is_number(issued_at)
        or expires_at + CLOCK_SKEW_SECONDS <= timestamp
        or issued_at - CLOCK_SKEW_SECONDS > timestamp
    ):
        raise GoogleTokenInvalid

    subject = claims.get("sub")
    email = claims.get("email")
    if not isinstance(subject, str) or not subject or len(subject) > 255:
        raise GoogleTokenInvalid
    if not isinstance(email, str) or "@" not in email or len(email) > 254:
        raise GoogleTokenInvalid
    if claims.get("email_verified") not in (True, "true"):
        raise GoogleEmailUnverified
    return GoogleIdentity(subject=subject, email=email.strip().lower())


def _signing_key(key_id: str) -> RSAPublicKey:
    keys = cache.get(JWKS_CACHE_KEY)
    if not isinstance(keys, dict) or key_id not in keys:
        # Google rotates keys; a new key ID earns one refetch per guard window.
        if isinstance(keys, dict) and not cache.add(
            JWKS_REFRESH_GUARD_KEY, 1, timeout=JWKS_REFRESH_GUARD_SECONDS
        ):
            raise GoogleTokenInvalid
        keys, max_age = fetch_google_jwks()
        cache.set(JWKS_CACHE_KEY, keys, timeout=max_age)
    jwk = keys.get(key_id)
    if not isinstance(jwk, dict):
        raise GoogleTokenInvalid
    try:
        exponent = int.from_bytes(_decode_segment(str(jwk["e"])), "big")
        modulus = int.from_bytes(_decode_segment(str(jwk["n"])), "big")
        return RSAPublicNumbers(exponent, modulus).public_key()
    except (KeyError, ValueError) as exc:
        raise GoogleTokenInvalid from exc


def fetch_google_jwks() -> tuple[dict[str, dict[str, Any]], int]:
    """Download Google's RSA keys, keyed by ``kid``, and their cache lifetime."""

    request = Request(GOOGLE_CERTS_URL, headers={"Accept": "application/json"})
    try:
        with urlopen(  # noqa: S310 -- fixed Google HTTPS endpoint.
            request, timeout=JWKS_FETCH_TIMEOUT_SECONDS
        ) as response:
            body = json.loads(response.read())
            cache_control = response.headers.get("Cache-Control", "")
    except (OSError, ValueError) as exc:
        raise GoogleSignInUnavailable from exc
    if not isinstance(body, dict) or not isinstance(body.get("keys"), list):
        raise GoogleSignInUnavailable
    keys = {
        str(jwk["kid"]): jwk
        for jwk in body["keys"]
        if isinstance(jwk, dict) and jwk.get("kty") == "RSA" and jwk.get("kid")
    }
    match = _MAX_AGE_PATTERN.search(cache_control)
    max_age = int(match.group(1)) if match else JWKS_DEFAULT_MAX_AGE_SECONDS
    return keys, min(max(max_age, 60), 24 * 60 * 60)


def _decode_segment(segment: str) -> bytes:
    try:
        return base64.urlsafe_b64decode(segment + "=" * (-len(segment) % 4))
    except (binascii.Error, ValueError) as exc:
        raise GoogleTokenInvalid from exc


def _decode_json_segment(segment: str) -> dict[str, Any]:
    try:
        value = json.loads(_decode_segment(segment))
    except ValueError as exc:
        raise GoogleTokenInvalid from exc
    if not isinstance(value, dict):
        raise GoogleTokenInvalid
    return value


def _is_number(value: object) -> TypeGuard[int | float]:
    return isinstance(value, int | float) and not isinstance(value, bool)
