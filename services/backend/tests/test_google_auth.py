from __future__ import annotations

import base64
import json
import time
import uuid
from collections.abc import Iterator
from typing import Any, cast
from unittest.mock import MagicMock, patch

import pytest
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from django.core.cache import cache
from django.test import override_settings
from django.urls import reverse
from rest_framework.test import APIClient

from quran_backend.modules.accounts import google_auth
from quran_backend.modules.accounts.models import (
    AuthIdentity,
    Device,
    GuestMergeAudit,
    IdentityProvider,
    User,
    UserStatus,
)

pytestmark = pytest.mark.django_db

WEB_CLIENT_ID = "1234-web.apps.googleusercontent.com"
ANDROID_CLIENT_ID = "1234-android.apps.googleusercontent.com"
KEY_ID = "test-key-1"
GOOGLE_SETTINGS = {
    "QURAN_GOOGLE_WEB_CLIENT_ID": WEB_CLIENT_ID,
    "QURAN_GOOGLE_ANDROID_CLIENT_IDS": [ANDROID_CLIENT_ID],
}

# The autouse fixture replaces the network fetch; two tests call the real one.
_REAL_FETCH_GOOGLE_JWKS = google_auth.fetch_google_jwks
_SIGNING_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
_FORGER_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _jwk(key: rsa.RSAPrivateKey, kid: str = KEY_ID) -> dict[str, str]:
    numbers = key.public_key().public_numbers()
    return {
        "kty": "RSA",
        "alg": "RS256",
        "use": "sig",
        "kid": kid,
        "n": _b64(numbers.n.to_bytes((numbers.n.bit_length() + 7) // 8, "big")),
        "e": _b64(numbers.e.to_bytes(3, "big")),
    }


def _claims(**overrides: object) -> dict[str, object]:
    now = int(time.time())
    claims: dict[str, object] = {
        "iss": "https://accounts.google.com",
        "aud": WEB_CLIENT_ID,
        "azp": ANDROID_CLIENT_ID,
        "sub": "109876543210",
        "email": "Reader@Gmail.com",
        "email_verified": True,
        "name": "Reader",
        "picture": "https://lh3.googleusercontent.com/a/photo",
        "iat": now - 10,
        "exp": now + 3600,
    }
    claims.update(overrides)
    return claims


def _token(
    claims: dict[str, object],
    *,
    key: rsa.RSAPrivateKey = _SIGNING_KEY,
    kid: str = KEY_ID,
    alg: str = "RS256",
) -> str:
    header = _b64(json.dumps({"alg": alg, "kid": kid, "typ": "JWT"}).encode())
    payload = _b64(json.dumps(claims).encode())
    signing_input = f"{header}.{payload}".encode("ascii")
    signature = key.sign(signing_input, padding.PKCS1v15(), hashes.SHA256())
    return f"{header}.{payload}.{_b64(signature)}"


@pytest.fixture(autouse=True)
def google_keys() -> Iterator[MagicMock]:
    cache.delete(google_auth.JWKS_CACHE_KEY)
    cache.delete(google_auth.JWKS_REFRESH_GUARD_KEY)
    with (
        override_settings(**GOOGLE_SETTINGS),
        patch.object(
            google_auth,
            "fetch_google_jwks",
            return_value=({KEY_ID: _jwk(_SIGNING_KEY)}, 3600),
        ) as fetch,
    ):
        yield fetch
    cache.delete(google_auth.JWKS_CACHE_KEY)
    cache.delete(google_auth.JWKS_REFRESH_GUARD_KEY)


def _bootstrap(client: APIClient) -> dict[str, Any]:
    response = client.post(
        reverse("accounts:guest-bootstrap"),
        {
            "installation_id": str(uuid.uuid4()),
            "installation_credential": "A" * 43,
            "platform": "android",
            "locale": "ru",
            "app_version": "1.0.0",
        },
        format="json",
    )
    assert response.status_code == 200
    return cast(dict[str, Any], response.json())


def _sign_in(client: APIClient, session: dict[str, Any], id_token: str) -> Any:
    return client.post(
        reverse("accounts:google-sign-in"),
        {"id_token": id_token},
        format="json",
        HTTP_AUTHORIZATION=f"Bearer {session['access_token']}",
    )


def test_google_sign_in_promotes_guest_and_issues_a_normal_session(
    api_client: APIClient,
) -> None:
    session = _bootstrap(api_client)

    response = _sign_in(api_client, session, _token(_claims()))

    assert response.status_code == 200, response.data
    body = response.json()
    assert body["user"]["id"] == session["user"]["id"]
    assert body["user"]["status"] == UserStatus.ACTIVE
    assert body["user"]["email"] == "reader@gmail.com"
    assert body["merged_guest"] is False
    assert body["refresh_token"]
    identity = AuthIdentity.objects.get()
    assert identity.provider == IdentityProvider.GOOGLE
    assert identity.provider_subject == "109876543210"
    assert identity.email_verified is True
    # The same tokens as an email code: they work for the account endpoints,
    # and the guest's previous token family is revoked.
    me = api_client.get(
        reverse("account_user:me"),
        HTTP_AUTHORIZATION=f"Bearer {body['access_token']}",
    )
    assert me.status_code == 200
    assert me.json()["user"]["email"] == "reader@gmail.com"
    stale = api_client.get(
        reverse("account_user:me"),
        HTTP_AUTHORIZATION=f"Bearer {session['access_token']}",
    )
    assert stale.status_code == 401


def test_android_client_id_is_an_accepted_audience(api_client: APIClient) -> None:
    session = _bootstrap(api_client)

    response = _sign_in(api_client, session, _token(_claims(aud=ANDROID_CLIENT_ID)))

    assert response.status_code == 200, response.data


def test_google_sign_in_links_existing_email_account_without_duplicates(
    api_client: APIClient,
) -> None:
    existing = User.objects.create_user(
        email="reader@gmail.com",
        status=UserStatus.ACTIVE,
        preferred_locale="ru",
    )
    AuthIdentity.objects.create(
        user=existing,
        provider=IdentityProvider.EMAIL,
        provider_subject="reader@gmail.com",
        email_at_provider="reader@gmail.com",
        email_verified=True,
    )
    session = _bootstrap(api_client)
    guest_id = session["user"]["id"]

    response = _sign_in(api_client, session, _token(_claims()))

    assert response.status_code == 200, response.data
    body = response.json()
    assert body["user"]["id"] == str(existing.id)
    assert body["merged_guest"] is True
    assert User.objects.filter(email__iexact="reader@gmail.com").count() == 1
    assert set(AuthIdentity.objects.filter(user=existing).values_list("provider", flat=True)) == {
        IdentityProvider.EMAIL,
        IdentityProvider.GOOGLE,
    }
    assert GuestMergeAudit.objects.get().source_user_id == uuid.UUID(guest_id)
    assert Device.objects.get(id=session["device"]["id"]).user_id == existing.id

    # A second sign-in from another installation finds the same account by the
    # Google subject, not by creating another user.
    second = _bootstrap(api_client)
    again = _sign_in(api_client, second, _token(_claims()))
    assert again.status_code == 200, again.data
    assert again.json()["user"]["id"] == str(existing.id)
    assert AuthIdentity.objects.filter(provider=IdentityProvider.GOOGLE).count() == 1


@pytest.mark.parametrize(
    ("token_factory", "label"),
    [
        (lambda: _token(_claims(), key=_FORGER_KEY), "forged signature"),
        (lambda: _token(_claims(aud="someone-else.apps.googleusercontent.com")), "foreign aud"),
        (lambda: _token(_claims(iss="https://evil.example.com")), "foreign iss"),
        (
            lambda: _token(_claims(iat=int(time.time()) - 7200, exp=int(time.time()) - 3600)),
            "expired",
        ),
        (lambda: _token(_claims(), alg="none"), "unsigned alg"),
        (lambda: _token(_claims(), kid="unknown-key"), "unknown key"),
        (lambda: "not-a-jwt-token-at-all", "malformed"),
    ],
)
def test_google_sign_in_rejects_invalid_tokens(
    api_client: APIClient,
    token_factory: Any,
    label: str,
) -> None:
    session = _bootstrap(api_client)

    response = _sign_in(api_client, session, token_factory())

    assert response.status_code == 400, label
    assert response.json()["code"] == "google_token_invalid", label
    assert not AuthIdentity.objects.exists()
    assert User.objects.get(id=session["user"]["id"]).status == UserStatus.GUEST


def test_tampered_payload_fails_signature_check(api_client: APIClient) -> None:
    session = _bootstrap(api_client)
    header, _payload, signature = _token(_claims()).split(".")
    tampered = _b64(json.dumps(_claims(email="victim@gmail.com")).encode())

    response = _sign_in(api_client, session, f"{header}.{tampered}.{signature}")

    assert response.status_code == 400
    assert response.json()["code"] == "google_token_invalid"


def test_google_sign_in_rejects_unverified_email(api_client: APIClient) -> None:
    session = _bootstrap(api_client)

    response = _sign_in(api_client, session, _token(_claims(email_verified=False)))

    assert response.status_code == 403
    assert response.json()["code"] == "google_email_unverified"
    assert not AuthIdentity.objects.exists()


def test_google_sign_in_is_disabled_without_client_ids(api_client: APIClient) -> None:
    session = _bootstrap(api_client)

    with override_settings(QURAN_GOOGLE_WEB_CLIENT_ID="", QURAN_GOOGLE_ANDROID_CLIENT_IDS=[]):
        config = api_client.get(reverse("accounts:google-config"))
        response = _sign_in(api_client, session, _token(_claims()))

    assert config.status_code == 200
    assert config.json() == {"enabled": False, "client_id": None}
    assert response.status_code == 404
    assert response.json()["code"] == "google_sign_in_disabled"


def test_google_config_exposes_only_the_web_client_id(api_client: APIClient) -> None:
    response = api_client.get(reverse("accounts:google-config"))

    assert response.status_code == 200
    assert response.json() == {"enabled": True, "client_id": WEB_CLIENT_ID}


def test_google_sign_in_requires_an_installation_session(api_client: APIClient) -> None:
    response = api_client.post(
        reverse("accounts:google-sign-in"),
        {"id_token": _token(_claims())},
        format="json",
    )

    assert response.status_code == 401


def test_unknown_key_refetches_google_keys_at_most_once_per_window(
    api_client: APIClient,
    google_keys: MagicMock,
) -> None:
    session = _bootstrap(api_client)
    assert _sign_in(api_client, session, _token(_claims())).status_code == 200
    assert google_keys.call_count == 1

    rotated = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    google_keys.return_value = ({"rotated": _jwk(rotated, "rotated")}, 3600)
    second = _bootstrap(api_client)
    rotated_token = _token(_claims(), key=rotated, kid="rotated")
    assert _sign_in(api_client, second, rotated_token).status_code == 200
    assert google_keys.call_count == 2

    third = _bootstrap(api_client)
    assert _sign_in(api_client, third, _token(_claims(), kid="another")).status_code == 400
    assert google_keys.call_count == 2


def test_fetch_google_jwks_reads_keys_and_cache_lifetime() -> None:
    body = json.dumps({"keys": [_jwk(_SIGNING_KEY), {"kty": "EC", "kid": "ec"}]}).encode()
    response = MagicMock()
    response.read.return_value = body
    response.headers = {"Cache-Control": "public, max-age=21600, must-revalidate"}
    response.__enter__.return_value = response
    with patch.object(google_auth, "urlopen", return_value=response):
        keys, max_age = _REAL_FETCH_GOOGLE_JWKS()

    assert set(keys) == {KEY_ID}
    assert max_age == 21600


def test_fetch_google_jwks_failure_is_a_temporary_error() -> None:
    with (
        patch.object(google_auth, "urlopen", side_effect=OSError("offline")),
        pytest.raises(google_auth.GoogleSignInUnavailable),
    ):
        _REAL_FETCH_GOOGLE_JWKS()
