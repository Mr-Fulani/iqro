from __future__ import annotations

import uuid
from typing import Any, cast

import pytest
from django.conf import settings
from django.core import mail
from django.core.cache import caches
from django.core.exceptions import ImproperlyConfigured
from django.test import override_settings
from django.urls import reverse
from rest_framework.test import APIClient

from quran_backend.modules.accounts.models import (
    AuthIdentity,
    EmailAuthChallenge,
    IdentityProvider,
    User,
    UserStatus,
)
from quran_backend.modules.accounts.throttling import (
    EmailStartAppReviewThrottle,
    EmailStartIdentityThrottle,
    EmailStartIPBurstThrottle,
)
from quran_backend.settings.base import validate_app_review_sign_in

pytestmark = pytest.mark.django_db

REVIEW_EMAIL = "review@example.com"
PASSCODE = "482916"
review_sign_in = override_settings(
    QURAN_APP_REVIEW_EMAIL=REVIEW_EMAIL,
    QURAN_APP_REVIEW_PASSCODE=PASSCODE,
)


def _guest(client: APIClient) -> tuple[dict[str, Any], str]:
    credential = uuid.uuid4().hex + "A" * 11
    response = client.post(
        reverse("accounts:guest-bootstrap"),
        {
            "installation_id": str(uuid.uuid4()),
            "installation_credential": credential,
            "platform": "ios",
            "locale": "en",
            "app_version": "1.0.17",
        },
        format="json",
    )
    assert response.status_code == 200
    return cast(dict[str, Any], response.json()), credential


def _start(client: APIClient, access_token: str, email: str) -> Any:
    return client.post(
        reverse("accounts:email-start"),
        {"email": email},
        format="json",
        HTTP_AUTHORIZATION=f"Bearer {access_token}",
    )


def _verify(client: APIClient, challenge_id: str, code: str, credential: str) -> Any:
    return client.post(
        reverse("accounts:email-verify"),
        {
            "challenge_id": challenge_id,
            "code": code,
            "installation_credential": credential,
            "idempotency_key": str(uuid.uuid4()),
        },
        format="json",
    )


def test_review_sign_in_is_off_by_default(api_client: APIClient) -> None:
    session, _credential = _guest(api_client)

    started = _start(api_client, session["access_token"], REVIEW_EMAIL)

    assert settings.QURAN_APP_REVIEW_EMAIL == ""
    assert settings.QURAN_APP_REVIEW_PASSCODE == ""
    assert started.status_code == 202
    assert mail.outbox[-1].to == [REVIEW_EMAIL]


@review_sign_in
def test_review_address_signs_in_with_the_fixed_code_without_an_email(
    api_client: APIClient,
) -> None:
    session, credential = _guest(api_client)

    started = _start(api_client, session["access_token"], " Review@Example.COM ")
    verified = _verify(api_client, started.json()["challenge_id"], PASSCODE, credential)

    assert started.status_code == 202
    assert mail.outbox == []
    challenge = EmailAuthChallenge.objects.get()
    assert challenge.email == REVIEW_EMAIL
    assert PASSCODE not in challenge.code_hash
    assert verified.status_code == 200, verified.data
    assert verified.json()["user"]["status"] == UserStatus.ACTIVE
    assert verified.json()["user"]["email"] == REVIEW_EMAIL


@review_sign_in
def test_other_addresses_still_get_an_emailed_code(api_client: APIClient) -> None:
    session, _credential = _guest(api_client)

    started = _start(api_client, session["access_token"], "reader@example.com")

    assert started.status_code == 202
    assert mail.outbox[-1].to == ["reader@example.com"]


@review_sign_in
def test_wrong_codes_use_up_the_attempts_like_any_other_code(api_client: APIClient) -> None:
    session, credential = _guest(api_client)
    challenge_id = _start(api_client, session["access_token"], REVIEW_EMAIL).json()["challenge_id"]

    wrong = [_verify(api_client, challenge_id, "000000", credential).status_code for _ in range(5)]
    late_right = _verify(api_client, challenge_id, PASSCODE, credential)

    assert wrong == [400] * 5
    assert late_right.status_code == 400
    assert EmailAuthChallenge.objects.get().consumed_at is None


@review_sign_in
def test_fixed_code_confirms_account_deletion(api_client: APIClient) -> None:
    session, credential = _guest(api_client)
    signed_in = _verify(
        api_client,
        _start(api_client, session["access_token"], REVIEW_EMAIL).json()["challenge_id"],
        PASSCODE,
        credential,
    ).json()
    reauth_id = _start(api_client, signed_in["access_token"], REVIEW_EMAIL).json()["challenge_id"]
    reauthenticated = _verify(api_client, reauth_id, PASSCODE, credential).json()

    requested = api_client.post(
        reverse("account_user:deletion-request"),
        {"reauth_challenge_id": reauth_id},
        format="json",
        HTTP_AUTHORIZATION=f"Bearer {reauthenticated['access_token']}",
    )

    assert requested.status_code == 202, requested.data
    assert requested.json()["user"]["status"] == UserStatus.PENDING_DELETION
    assert mail.outbox == []


@review_sign_in
@pytest.mark.parametrize("by_identity", [False, True])
def test_fixed_code_never_opens_a_staff_account(
    api_client: APIClient, *, by_identity: bool
) -> None:
    staff = User.objects.create_user(
        email="admin@example.com" if by_identity else REVIEW_EMAIL,
        status=UserStatus.ACTIVE,
        is_staff=True,
    )
    if by_identity:
        AuthIdentity.objects.create(
            user=staff,
            provider=IdentityProvider.EMAIL,
            provider_subject=REVIEW_EMAIL,
            email_at_provider=REVIEW_EMAIL,
            email_verified=True,
        )
    session, _credential = _guest(api_client)

    started = _start(api_client, session["access_token"], REVIEW_EMAIL)

    assert started.status_code == 403
    assert started.json()["code"] == "account_link_unavailable"
    assert not EmailAuthChallenge.objects.exists()
    assert mail.outbox == []


@review_sign_in
def test_review_address_has_one_quota_shared_by_every_device(
    api_client: APIClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    rates = {
        "email_start_ip_burst": "10000/minute",
        "email_start_identity": "10000/minute",
        "email_start_app_review": "2/day",
    }
    for throttle in (
        EmailStartIPBurstThrottle,
        EmailStartIdentityThrottle,
        EmailStartAppReviewThrottle,
    ):
        monkeypatch.setattr(throttle, "THROTTLE_RATES", rates)
    caches["throttling"].clear()
    guests = [_guest(api_client)[0]["access_token"] for _ in range(3)]

    review = [_start(api_client, token, REVIEW_EMAIL) for token in guests]
    reader = _start(api_client, guests[2], "reader@example.com")
    caches["throttling"].clear()

    assert [response.status_code for response in review] == [202, 202, 429]
    assert review[2].json()["code"] == "auth_rate_limited"
    assert int(review[2]["Retry-After"]) > 0
    assert reader.status_code == 202


@pytest.mark.parametrize(
    ("email", "passcode"),
    [
        (REVIEW_EMAIL, ""),
        ("", PASSCODE),
        ("not-an-address", PASSCODE),
        (REVIEW_EMAIL, "48291"),
        (REVIEW_EMAIL, "48291a"),
        (REVIEW_EMAIL, "000000"),
        (REVIEW_EMAIL, "123456"),
        (REVIEW_EMAIL, "987654"),
    ],
)
def test_misconfigured_review_sign_in_stops_the_server(email: str, passcode: str) -> None:
    with pytest.raises(ImproperlyConfigured):
        validate_app_review_sign_in(email, passcode)


@pytest.mark.parametrize(("email", "passcode"), [("", ""), (REVIEW_EMAIL, PASSCODE)])
def test_review_sign_in_settings_that_start(email: str, passcode: str) -> None:
    validate_app_review_sign_in(email, passcode)
