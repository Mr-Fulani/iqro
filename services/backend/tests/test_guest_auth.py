from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from threading import Barrier
from typing import Any, cast
from uuid import UUID, uuid4

import pytest
from django.core.cache import cache
from django.db import connection
from django.test import override_settings
from django.utils import timezone
from rest_framework.request import Request
from rest_framework.test import APIClient, APIRequestFactory

from quran_backend.modules.accounts import services as account_services
from quran_backend.modules.accounts import throttling as auth_throttling
from quran_backend.modules.accounts.authentication import SignedAccessTokenAuthentication
from quran_backend.modules.accounts.exceptions import AccessTokenInvalid
from quran_backend.modules.accounts.models import Device, RefreshSession, RefreshToken, User
from quran_backend.modules.accounts.services import AccessAuthContext
from quran_backend.modules.accounts.throttling import (
    GuestBootstrapInstallationThrottle,
    GuestBootstrapIPBurstThrottle,
    RefreshTokenIPBurstThrottle,
    RefreshTokenSessionThrottle,
)

pytestmark = [
    pytest.mark.django_db,
    pytest.mark.usefixtures("_accounts_urlconf"),
]


@pytest.fixture
def _accounts_urlconf() -> Any:
    with override_settings(ROOT_URLCONF="quran_backend.modules.accounts.urls"):
        yield


def _payload(installation_id: UUID | None = None, **overrides: object) -> dict[str, object]:
    payload: dict[str, object] = {
        "installation_id": str(installation_id or uuid4()),
        "installation_credential": "A" * 43,
        "platform": "android",
        "locale": "en",
        "app_version": "1.0.0",
    }
    payload.update(overrides)
    return payload


def _bootstrap(client: APIClient, payload: dict[str, object]) -> dict[str, Any]:
    response = client.post("/guest", payload, format="json")
    assert response.status_code == 200, response.data
    return cast(dict[str, Any], response.json())


def test_guest_bootstrap_is_identity_idempotent_and_rotates_session(api_client: APIClient) -> None:
    installation_id = uuid4()
    first = _bootstrap(api_client, _payload(installation_id))
    first_session = RefreshSession.objects.get()

    second = _bootstrap(
        api_client,
        _payload(installation_id, locale="ru", app_version="1.0.1"),
    )

    assert first["user"]["id"] == second["user"]["id"]
    assert first["device"]["id"] == second["device"]["id"]
    assert first["refresh_token"] != second["refresh_token"]
    assert first["device"]["bootstrap_generation"] == 1
    assert second["device"]["bootstrap_generation"] == 2
    assert User.objects.count() == 1
    assert Device.objects.count() == 1
    assert RefreshSession.objects.count() == 2
    first_session.refresh_from_db()
    assert first_session.revoked_at is not None
    device = Device.objects.get()
    assert device.locale == "ru"
    assert device.app_version == "1.0.1"
    assert device.installation_id_hash != str(installation_id)
    assert device.installation_credential_hash != "A" * 43


def test_guest_bootstrap_accepts_turkish_locale(api_client: APIClient) -> None:
    response = _bootstrap(api_client, _payload(locale="tr"))

    assert response["user"]["preferred_locale"] == "tr"
    assert response["device"]["locale"] == "tr"
    assert User.objects.get().preferred_locale == "tr"
    assert Device.objects.get().locale == "tr"


def test_access_authentication_resolves_bound_device_and_session(api_client: APIClient) -> None:
    auth_data = _bootstrap(api_client, _payload())
    factory = APIRequestFactory()
    request = Request(
        factory.get("/protected", HTTP_AUTHORIZATION=f"Bearer {auth_data['access_token']}")
    )

    result = SignedAccessTokenAuthentication().authenticate(request)

    assert result is not None
    user, context = result
    assert isinstance(context, AccessAuthContext)
    assert str(user.id) == auth_data["user"]["id"]
    assert str(context.device.id) == auth_data["device"]["id"]
    assert context.session.user_id == user.id


def test_refresh_rotates_one_use_token(api_client: APIClient) -> None:
    auth_data = _bootstrap(api_client, _payload())
    original_token = RefreshToken.objects.get()

    response = api_client.post(
        "/token/refresh",
        {"refresh_token": auth_data["refresh_token"]},
        format="json",
    )

    assert response.status_code == 200
    rotated = response.json()
    assert rotated["access_token"] != auth_data["access_token"]
    assert rotated["refresh_token"] != auth_data["refresh_token"]
    original_token.refresh_from_db()
    assert original_token.used_at is not None
    assert original_token.replaced_by is not None
    assert RefreshToken.objects.count() == 2


def test_refresh_replay_revokes_entire_family(api_client: APIClient) -> None:
    auth_data = _bootstrap(api_client, _payload())
    rotated_response = api_client.post(
        "/token/refresh",
        {"refresh_token": auth_data["refresh_token"]},
        format="json",
    )
    rotated = rotated_response.json()

    replay_response = api_client.post(
        "/token/refresh",
        {"refresh_token": auth_data["refresh_token"]},
        format="json",
    )

    assert replay_response.status_code == 401
    assert replay_response.json()["code"] == "refresh_token_reused"
    session = RefreshSession.objects.get()
    assert session.revoked_at is not None
    assert session.compromise_detected_at is not None
    assert not RefreshToken.objects.filter(session=session, revoked_at__isnull=True).exists()

    current_response = api_client.post(
        "/token/refresh",
        {"refresh_token": rotated["refresh_token"]},
        format="json",
    )
    assert current_response.status_code == 401
    assert current_response.json()["code"] == "refresh_token_invalid"


def test_wrong_refresh_secret_does_not_revoke_family(api_client: APIClient) -> None:
    auth_data = _bootstrap(api_client, _payload())
    raw_token = auth_data["refresh_token"]
    last_character = "A" if raw_token[-1] != "A" else "B"

    response = api_client.post(
        "/token/refresh",
        {"refresh_token": f"{raw_token[:-1]}{last_character}"},
        format="json",
    )

    assert response.status_code == 401
    assert response.json()["code"] == "refresh_token_invalid"
    session = RefreshSession.objects.get()
    assert session.revoked_at is None
    assert session.compromise_detected_at is None


def test_logout_revokes_current_session_and_credentials(api_client: APIClient) -> None:
    auth_data = _bootstrap(api_client, _payload())

    response = api_client.post(
        "/logout",
        format="json",
        HTTP_AUTHORIZATION=f"Bearer {auth_data['access_token']}",
    )

    assert response.status_code == 204
    session = RefreshSession.objects.get()
    assert session.revoked_at is not None
    assert RefreshToken.objects.get().revoked_at is not None

    refresh_response = api_client.post(
        "/token/refresh",
        {"refresh_token": auth_data["refresh_token"]},
        format="json",
    )
    assert refresh_response.status_code == 401
    assert refresh_response.json()["code"] == "refresh_token_invalid"

    access_response = api_client.post(
        "/logout",
        format="json",
        HTTP_AUTHORIZATION=f"Bearer {auth_data['access_token']}",
    )
    assert access_response.status_code == 401
    assert access_response.json()["code"] == "access_token_invalid"


def test_logout_all_revokes_sessions_on_other_devices(api_client: APIClient) -> None:
    auth_data = _bootstrap(api_client, _payload())
    user = User.objects.get(id=auth_data["user"]["id"])
    second_device = Device.objects.create(
        user=user,
        platform="web",
        installation_id_hash="b" * 64,
        app_version="1.0.0",
        locale="en",
    )
    now = timezone.now()
    second_session = RefreshSession.objects.create(
        user=user,
        device=second_device,
        expires_at=now + timedelta(days=30),
    )
    second_credentials = account_services._issue_credentials(
        session=second_session,
        now=now,
    )

    response = api_client.post(
        "/logout-all",
        format="json",
        HTTP_AUTHORIZATION=f"Bearer {auth_data['access_token']}",
    )

    assert response.status_code == 204
    assert RefreshSession.objects.filter(revoked_at__isnull=False).count() == 2
    second_access_response = api_client.post(
        "/logout",
        format="json",
        HTTP_AUTHORIZATION=f"Bearer {second_credentials.access_token}",
    )
    second_refresh_response = api_client.post(
        "/token/refresh",
        {"refresh_token": second_credentials.refresh_token},
        format="json",
    )
    assert second_access_response.status_code == 401
    assert second_access_response.json()["code"] == "access_token_invalid"
    assert second_refresh_response.status_code == 401
    assert second_refresh_response.json()["code"] == "refresh_token_invalid"


@pytest.mark.parametrize(
    "overrides",
    [
        {"installation_id": "not-a-uuid"},
        {"installation_id": "00000000-0000-0000-0000-000000000000"},
        {"installation_credential": "too-short"},
        {"installation_credential": "!" * 43},
        {"platform": "desktop"},
        {"locale": "fr"},
        {"app_version": "invalid version with spaces"},
    ],
)
def test_guest_bootstrap_rejects_invalid_input(
    api_client: APIClient,
    overrides: dict[str, object],
) -> None:
    payload = _payload()
    payload.update(overrides)
    response = api_client.post("/guest", payload, format="json")

    assert response.status_code == 400
    assert response["Cache-Control"] == "private, no-store"
    assert User.objects.count() == 0
    assert Device.objects.count() == 0


def test_distinct_installations_are_isolated(api_client: APIClient) -> None:
    first = _bootstrap(api_client, _payload(uuid4()))
    second = _bootstrap(api_client, _payload(uuid4()))

    assert first["user"]["id"] != second["user"]["id"]
    assert first["device"]["id"] != second["device"]["id"]
    assert User.objects.count() == 2
    assert Device.objects.count() == 2
    first_session = RefreshSession.objects.get(user_id=first["user"]["id"])
    second_session = RefreshSession.objects.get(user_id=second["user"]["id"])
    assert first_session.device_id != second_session.device_id


def test_installation_cannot_change_platform(api_client: APIClient) -> None:
    installation_id = uuid4()
    auth_data = _bootstrap(api_client, _payload(installation_id, platform="ios"))

    response = api_client.post(
        "/guest",
        _payload(installation_id, platform="web"),
        format="json",
    )

    assert response.status_code == 403
    assert response.json()["code"] == "guest_bootstrap_unavailable"
    assert User.objects.count() == 1
    assert Device.objects.get().platform == "ios"
    assert RefreshSession.objects.get().revoked_at is None
    assert auth_data["access_token"]


def test_installation_id_alone_cannot_take_over_guest(api_client: APIClient) -> None:
    installation_id = uuid4()
    original = _bootstrap(
        api_client,
        _payload(installation_id, installation_credential="A" * 43),
    )

    response = api_client.post(
        "/guest",
        _payload(installation_id, installation_credential="B" * 43),
        format="json",
    )

    assert response.status_code == 403
    assert response.json()["code"] == "guest_bootstrap_unavailable"
    assert RefreshSession.objects.get().revoked_at is None
    assert original["access_token"]


def test_guest_bootstrap_is_rate_limited_per_installation(
    api_client: APIClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    rates = {
        "guest_bootstrap_installation": "1/minute",
        "guest_bootstrap_ip_burst": "10000/minute",
    }
    monkeypatch.setattr(
        GuestBootstrapInstallationThrottle,
        "THROTTLE_RATES",
        rates,
    )
    monkeypatch.setattr(
        GuestBootstrapIPBurstThrottle,
        "THROTTLE_RATES",
        rates,
    )
    cache.clear()
    payload = _payload(uuid4())
    first = api_client.post("/guest", payload, format="json")
    second = api_client.post("/guest", payload, format="json")
    cache.clear()

    assert first.status_code == 200
    assert second.status_code == 429
    assert second.json()["code"] == "auth_rate_limited"
    assert int(second["Retry-After"]) > 0


def test_distinct_installations_do_not_share_the_primary_rate_limit(
    api_client: APIClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    rates = {
        "guest_bootstrap_installation": "1/minute",
        "guest_bootstrap_ip_burst": "10000/minute",
    }
    monkeypatch.setattr(GuestBootstrapInstallationThrottle, "THROTTLE_RATES", rates)
    monkeypatch.setattr(GuestBootstrapIPBurstThrottle, "THROTTLE_RATES", rates)
    cache.clear()
    first = api_client.post("/guest", _payload(uuid4()), format="json")
    second = api_client.post("/guest", _payload(uuid4()), format="json")
    cache.clear()

    assert first.status_code == 200
    assert second.status_code == 200


def test_guest_bootstrap_has_a_separate_high_ip_circuit_breaker(
    api_client: APIClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    rates = {
        "guest_bootstrap_installation": "10000/minute",
        "guest_bootstrap_ip_burst": "1/minute",
    }
    monkeypatch.setattr(GuestBootstrapInstallationThrottle, "THROTTLE_RATES", rates)
    monkeypatch.setattr(GuestBootstrapIPBurstThrottle, "THROTTLE_RATES", rates)
    cache.clear()
    first = api_client.post("/guest", _payload(uuid4()), format="json")
    second = api_client.post("/guest", _payload(uuid4()), format="json")
    cache.clear()

    assert first.status_code == 200
    assert second.status_code == 429
    assert second.json()["code"] == "auth_rate_limited"


def test_refresh_rate_limit_follows_the_verified_session_across_rotation(
    api_client: APIClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    rates = {
        "token_refresh_session": "1/minute",
        "token_refresh_ip_burst": "10000/minute",
    }
    monkeypatch.setattr(RefreshTokenSessionThrottle, "THROTTLE_RATES", rates)
    monkeypatch.setattr(RefreshTokenIPBurstThrottle, "THROTTLE_RATES", rates)
    cache.clear()
    auth_data = _bootstrap(api_client, _payload())
    first = api_client.post(
        "/token/refresh",
        {"refresh_token": auth_data["refresh_token"]},
        format="json",
    )
    second = api_client.post(
        "/token/refresh",
        {"refresh_token": first.json()["refresh_token"]},
        format="json",
    )
    cache.clear()

    assert first.status_code == 200
    assert second.status_code == 429
    assert second.json()["code"] == "auth_rate_limited"


def test_refresh_ip_breaker_short_circuits_the_database_identity_lookup(
    api_client: APIClient,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    rates = {
        "token_refresh_session": "10000/minute",
        "token_refresh_ip_burst": "1/minute",
    }
    monkeypatch.setattr(RefreshTokenSessionThrottle, "THROTTLE_RATES", rates)
    monkeypatch.setattr(RefreshTokenIPBurstThrottle, "THROTTLE_RATES", rates)
    identity_lookups = 0

    def fake_identity(_raw_token: str) -> None:
        nonlocal identity_lookups
        identity_lookups += 1

    monkeypatch.setattr(auth_throttling, "refresh_token_rate_limit_identity", fake_identity)
    cache.clear()
    first_token = f"qrt1.{uuid4().hex}.{'A' * 64}"
    second_token = f"qrt1.{uuid4().hex}.{'B' * 64}"
    first = api_client.post("/token/refresh", {"refresh_token": first_token}, format="json")
    second = api_client.post("/token/refresh", {"refresh_token": second_token}, format="json")
    cache.clear()

    assert first.status_code == 401
    assert second.status_code == 429
    assert identity_lookups == 1


def test_expired_session_has_stable_error_codes(api_client: APIClient) -> None:
    auth_data = _bootstrap(api_client, _payload())
    RefreshSession.objects.update(expires_at=timezone.now() - timedelta(seconds=1))
    RefreshToken.objects.update(expires_at=timezone.now() - timedelta(seconds=1))

    refresh_response = api_client.post(
        "/token/refresh",
        {"refresh_token": auth_data["refresh_token"]},
        format="json",
    )
    access_response = api_client.post(
        "/logout",
        format="json",
        HTTP_AUTHORIZATION=f"Bearer {auth_data['access_token']}",
    )

    assert refresh_response.status_code == 401
    assert refresh_response.json()["code"] == "refresh_token_invalid"
    assert access_response.status_code == 401
    assert access_response.json()["code"] == "access_token_invalid"


def test_refresh_secret_is_not_persisted(api_client: APIClient) -> None:
    auth_data = _bootstrap(api_client, _payload())
    raw_token = auth_data["refresh_token"]
    secret = raw_token.rsplit(".", maxsplit=1)[1]
    stored = RefreshToken.objects.get()

    assert stored.secret_hash != secret
    assert len(stored.secret_hash) == 64
    assert secret not in stored.secret_hash


def test_tampered_access_token_is_rejected(api_client: APIClient) -> None:
    auth_data = _bootstrap(api_client, _payload())
    raw_token = auth_data["access_token"]
    tampered = f"{raw_token[:-1]}{'A' if raw_token[-1] != 'A' else 'B'}"
    factory = APIRequestFactory()
    request = Request(factory.get("/protected", HTTP_AUTHORIZATION=f"Bearer {tampered}"))

    with pytest.raises(AccessTokenInvalid):
        SignedAccessTokenAuthentication().authenticate(request)


@pytest.mark.django_db(transaction=True)
def test_concurrent_refresh_replay_is_serialized_on_postgresql(api_client: APIClient) -> None:
    if connection.vendor != "postgresql":
        pytest.skip("Row-lock behavior is verified by the PostgreSQL CI job.")
    auth_data = _bootstrap(api_client, _payload())
    barrier = Barrier(2)

    def refresh() -> tuple[int, str | None]:
        client = APIClient()
        barrier.wait(timeout=5)
        response = client.post(
            "/token/refresh",
            {"refresh_token": auth_data["refresh_token"]},
            format="json",
        )
        return response.status_code, response.json().get("code")

    with ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(lambda _index: refresh(), range(2)))

    assert sorted(status_code for status_code, _code in results) == [200, 401]
    assert "refresh_token_reused" in {code for _status, code in results}
    session = RefreshSession.objects.get()
    assert session.revoked_at is not None
    assert session.compromise_detected_at is not None
