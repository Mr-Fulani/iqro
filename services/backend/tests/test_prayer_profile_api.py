from __future__ import annotations

import json
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from decimal import Decimal
from threading import Barrier
from typing import Any, cast

import pytest
from django.contrib import admin
from django.core.cache import cache
from django.db import IntegrityError, close_old_connections, connection
from django.urls import reverse
from django.utils import timezone
from drf_spectacular.generators import SchemaGenerator
from rest_framework.test import APIClient

from quran_backend.modules.accounts.models import (
    Device,
    DevicePlatform,
    RefreshSession,
    User,
)
from quran_backend.modules.accounts.services import AccessAuthContext
from quran_backend.modules.core.privacy import PRIVATE_NO_STORE_CACHE_CONTROL
from quran_backend.modules.prayer_times.admin import PrayerProfileAdmin
from quran_backend.modules.prayer_times.engine import ENGINE_ID, ENGINE_VERSION
from quran_backend.modules.prayer_times.models import (
    HighLatitudeRule,
    PolarCircleResolution,
    PrayerConfigRelease,
    PrayerMethod,
    PrayerMethodConfig,
    PrayerProfile,
)
from quran_backend.modules.prayer_times.throttling import PrayerProfileMutationThrottle
from quran_backend.modules.prayer_times.timezones import TZDB_VERSION


@pytest.fixture
def prayer_profile_method(db: None) -> PrayerMethodConfig:
    return PrayerMethodConfig.objects.select_related("release", "method").get(
        method__code="muslim-world-league",
        release__version="2026.1",
    )


@pytest.fixture
def unsupported_prayer_profile_method(db: None) -> PrayerMethodConfig:
    method = PrayerMethod.objects.create(
        code="unsupported-profile-engine",
        name_ar="محرك غير مدعوم",
        name_en="Unsupported profile engine",
        name_ru="Неподдерживаемый движок профиля",
        authority_name="Synthetic test authority",
        authority_url="https://example.test/unsupported-profile-engine",
    )
    release = PrayerConfigRelease.objects.create(
        version="unsupported-profile-2026.1",
        configuration_schema_version=1,
        algorithm="unsupported-engine",
        algorithm_version="99.0.0",
        timezone_database_version="2026.3",
        release_notes="Synthetic unsupported engine fixture.",
    )
    configuration = PrayerMethodConfig.objects.create(
        release=release,
        method=method,
        fajr_angle=Decimal("18.00"),
        isha_angle=Decimal("17.00"),
        supports_middle_of_night=True,
        supports_seventh_of_night=True,
        supports_twilight_angle=True,
        default_high_latitude_rule=HighLatitudeRule.MIDDLE_OF_NIGHT,
        supports_polar_unresolved=True,
        supports_polar_aqrab_balad=True,
        supports_polar_aqrab_yaum=True,
        default_polar_resolution=PolarCircleResolution.UNRESOLVED,
        source_name="Synthetic unsupported parameters",
        source_url="https://example.test/unsupported-profile-parameters",
        source_version="1.0.0",
        source_checksum_sha256="b" * 64,
    )
    release.publish(make_default=False)
    release.save()
    return PrayerMethodConfig.objects.select_related("method", "release").get(pk=configuration.pk)


def _create_supported_concurrency_method() -> PrayerMethodConfig:
    method = PrayerMethod.objects.create(
        code="concurrent-profile-engine",
        name_ar="اختبار التزامن",
        name_en="Concurrent profile engine",
        name_ru="Конкурентный профиль",
        authority_name="Synthetic concurrency authority",
        authority_url="https://example.test/concurrent-profile-engine",
    )
    release = PrayerConfigRelease.objects.create(
        version="concurrent-profile-2026.1",
        configuration_schema_version=1,
        algorithm=ENGINE_ID,
        algorithm_version=ENGINE_VERSION,
        timezone_database_version=TZDB_VERSION,
        release_notes="Synthetic PostgreSQL concurrency fixture.",
    )
    configuration = PrayerMethodConfig.objects.create(
        release=release,
        method=method,
        fajr_angle=Decimal("18.00"),
        isha_angle=Decimal("17.00"),
        supports_middle_of_night=True,
        supports_seventh_of_night=True,
        supports_twilight_angle=True,
        default_high_latitude_rule=HighLatitudeRule.MIDDLE_OF_NIGHT,
        supports_polar_unresolved=True,
        supports_polar_aqrab_balad=True,
        supports_polar_aqrab_yaum=True,
        default_polar_resolution=PolarCircleResolution.UNRESOLVED,
        source_name="Synthetic concurrency parameters",
        source_url="https://example.test/concurrent-profile-parameters",
        source_version="1.0.0",
        source_checksum_sha256="c" * 64,
    )
    make_default = not PrayerConfigRelease.objects.filter(
        status="published",
        is_default=True,
    ).exists()
    release.publish(make_default=make_default)
    release.save()
    return PrayerMethodConfig.objects.select_related("method", "release").get(pk=configuration.pk)


def _payload(configuration: PrayerMethodConfig, **overrides: Any) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "base_revision": 0,
        "method_config_id": str(configuration.id),
        "method_checksum_sha256": configuration.checksum_sha256,
        "asr_method": "standard",
        "high_latitude_rule": "middle_of_night",
        "polar_resolution": "unresolved",
        "adjustments": {
            "fajr": 0,
            "sunrise": 0,
            "dhuhr": 0,
            "asr": 0,
            "maghrib": 0,
            "isha": 0,
        },
        "timezone_mode": "device_local",
        "client_updated_at": timezone.now().isoformat(),
    }
    payload.update(overrides)
    return payload


def _client_with_device(
    user: User,
    *,
    suffix: str = "a",
) -> tuple[APIClient, Device]:
    device = Device.objects.create(
        user=user,
        platform=DevicePlatform.ANDROID,
        installation_id_hash=suffix * 64,
    )
    session = RefreshSession.objects.create(
        user=user,
        device=device,
        expires_at=timezone.now() + timedelta(days=1),
    )
    client = APIClient()
    client.force_authenticate(
        user=user,
        token=AccessAuthContext(device=device, session=session),  # type: ignore[arg-type]
    )
    return client, device


def _assert_private(response: Any) -> None:
    assert response.headers["Cache-Control"] == PRIVATE_NO_STORE_CACHE_CONTROL
    assert response.headers["Pragma"] == "no-cache"
    assert response.headers["Expires"] == "0"
    assert "Authorization" in response.headers["Vary"]


@pytest.mark.django_db
def test_prayer_profile_requires_authentication_and_missing_profile_is_private() -> None:
    url = reverse("prayer_profile:detail")
    unauthenticated = APIClient().get(url)
    user = User.objects.create_user()
    client = APIClient()
    client.force_authenticate(user=user)
    missing = client.get(url)

    assert unauthenticated.status_code == 401
    assert missing.status_code == 404
    assert missing.json()["code"] == "prayer_profile_not_found"
    _assert_private(unauthenticated)
    _assert_private(missing)


@pytest.mark.django_db
def test_prayer_profile_create_get_and_device_binding_are_private_and_location_free(
    prayer_profile_method: PrayerMethodConfig,
) -> None:
    user = User.objects.create_user()
    client, device = _client_with_device(user)
    url = reverse("prayer_profile:detail")

    created = client.put(
        url,
        _payload(
            prayer_profile_method,
            asr_method="hanafi",
            adjustments={"fajr": -3, "isha": 7},
            timezone_mode="fixed",
            fixed_timezone="Europe/Istanbul",
        ),
        format="json",
    )
    fetched = client.get(url)

    assert created.status_code == fetched.status_code == 200
    _assert_private(created)
    _assert_private(fetched)
    body = created.json()
    assert body == fetched.json()
    assert body["revision"] == 1
    assert body["device_id"] == str(device.id)
    assert body["method_available"] is True
    assert body["method_config"] == {
        "id": str(prayer_profile_method.id),
        "code": "muslim-world-league",
        "catalog_version": "2026.1",
        "checksum_sha256": prayer_profile_method.checksum_sha256,
    }
    assert body["fixed_timezone"] == "Europe/Istanbul"
    assert body["adjustments"] == {
        "fajr": -3,
        "sunrise": 0,
        "dhuhr": 0,
        "asr": 0,
        "maghrib": 0,
        "isha": 7,
    }
    assert not {"latitude", "longitude", "location", "city", "occurrence_times"} & set(body)
    assert PrayerProfile.objects.get(user=user).device_id == device.id


@pytest.mark.django_db
def test_prayer_profile_uses_optimistic_locking_and_idempotent_stale_retry(
    prayer_profile_method: PrayerMethodConfig,
) -> None:
    user = User.objects.create_user()
    client, _device = _client_with_device(user)
    url = reverse("prayer_profile:detail")
    original = _payload(prayer_profile_method)
    assert client.put(url, original, format="json").status_code == 200

    replacement = _payload(
        prayer_profile_method,
        base_revision=1,
        adjustments={"fajr": 2},
    )
    updated = client.put(url, replacement, format="json")
    stale_same_state = client.put(url, replacement, format="json")
    conflicting = client.put(
        url,
        _payload(prayer_profile_method, base_revision=1, asr_method="hanafi"),
        format="json",
    )

    assert updated.status_code == 200
    assert updated.json()["revision"] == 2
    assert stale_same_state.status_code == 200
    assert stale_same_state.json() == updated.json()
    assert conflicting.status_code == 409
    assert conflicting.json()["code"] == "prayer_profile_revision_conflict"
    assert PrayerProfile.objects.get(user=user).revision == 2


@pytest.mark.django_db
def test_prayer_profile_competing_writers_cannot_overwrite_same_revision(
    prayer_profile_method: PrayerMethodConfig,
) -> None:
    user = User.objects.create_user()
    first = APIClient()
    second = APIClient()
    first.force_authenticate(user=user)
    second.force_authenticate(user=user)
    url = reverse("prayer_profile:detail")
    assert first.put(url, _payload(prayer_profile_method), format="json").status_code == 200

    winner = first.put(
        url,
        _payload(prayer_profile_method, base_revision=1, asr_method="hanafi"),
        format="json",
    )
    loser = second.put(
        url,
        _payload(
            prayer_profile_method,
            base_revision=1,
            adjustments={"maghrib": 4},
        ),
        format="json",
    )

    assert winner.status_code == 200
    assert loser.status_code == 409
    profile = PrayerProfile.objects.get(user=user)
    assert profile.revision == 2
    assert profile.asr_method == "hanafi"
    assert profile.maghrib_adjustment_minutes == 0


@pytest.mark.django_db(transaction=True)
def test_prayer_profile_serializes_concurrent_writes_on_postgresql() -> None:
    if connection.vendor != "postgresql":
        pytest.skip("Row-lock concurrency semantics require PostgreSQL.")
    prayer_profile_method = _create_supported_concurrency_method()
    user = User.objects.create_user()
    url = reverse("prayer_profile:detail")
    barrier = Barrier(2)
    payloads = [
        _payload(prayer_profile_method, asr_method="standard"),
        _payload(prayer_profile_method, asr_method="hanafi"),
    ]

    def put(payload: dict[str, Any]) -> int:
        close_old_connections()
        try:
            client = APIClient()
            client.force_authenticate(user=User.objects.get(pk=user.pk))
            barrier.wait(timeout=10)
            return client.put(url, payload, format="json").status_code
        finally:
            close_old_connections()

    with ThreadPoolExecutor(max_workers=2) as executor:
        statuses = sorted(executor.map(put, payloads))

    assert statuses == [200, 409]
    profile = PrayerProfile.objects.get(user=user)
    assert profile.revision == 1
    assert profile.asr_method in {"standard", "hanafi"}

    barrier = Barrier(2)
    payloads = [
        _payload(
            prayer_profile_method,
            base_revision=1,
            adjustments={"fajr": 1},
        ),
        _payload(
            prayer_profile_method,
            base_revision=1,
            adjustments={"maghrib": 4},
        ),
    ]

    with ThreadPoolExecutor(max_workers=2) as executor:
        statuses = sorted(executor.map(put, payloads))

    assert statuses == [200, 409]
    profile = PrayerProfile.objects.get(user=user)
    assert profile.revision == 2
    assert (profile.fajr_adjustment_minutes, profile.maghrib_adjustment_minutes) in {
        (1, 0),
        (0, 4),
    }


@pytest.mark.django_db
def test_prayer_profile_is_user_isolated(
    prayer_profile_method: PrayerMethodConfig,
) -> None:
    owner = User.objects.create_user()
    stranger = User.objects.create_user()
    owner_client = APIClient()
    owner_client.force_authenticate(user=owner)
    stranger_client = APIClient()
    stranger_client.force_authenticate(user=stranger)
    url = reverse("prayer_profile:detail")

    assert owner_client.put(url, _payload(prayer_profile_method), format="json").status_code == 200
    response = stranger_client.get(url)

    assert response.status_code == 404
    assert "method_config" not in response.json()


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("changes", "field"),
    [
        ({"device_id": "00000000-0000-0000-0000-000000000000"}, "device_id"),
        ({"unknown": True}, "unknown"),
        ({"adjustments": {"fajr": 0, "hidden": 1}}, "hidden"),
        ({"timezone_mode": "fixed"}, "fixed_timezone"),
        (
            {"timezone_mode": "device_local", "fixed_timezone": "Europe/Istanbul"},
            "fixed_timezone",
        ),
        ({"timezone_mode": "fixed", "fixed_timezone": "../UTC"}, "fixed_timezone"),
        ({"adjustments": {"isha": 121}}, "isha"),
    ],
)
def test_prayer_profile_strictly_rejects_unknown_or_invalid_state(
    prayer_profile_method: PrayerMethodConfig,
    changes: dict[str, Any],
    field: str,
) -> None:
    user = User.objects.create_user()
    client = APIClient()
    client.force_authenticate(user=user)
    payload = _payload(prayer_profile_method)
    payload.update(changes)

    response = client.put(reverse("prayer_profile:detail"), payload, format="json")

    assert response.status_code == 400
    assert field in json.dumps(response.json()["field_errors"], sort_keys=True)
    assert not PrayerProfile.objects.filter(user=user).exists()


@pytest.mark.django_db
def test_prayer_profile_rejects_wrong_checksum_and_reports_stale_method_without_substitution(
    prayer_profile_method: PrayerMethodConfig,
) -> None:
    user = User.objects.create_user()
    client = APIClient()
    client.force_authenticate(user=user)
    url = reverse("prayer_profile:detail")
    mismatch = client.put(
        url,
        _payload(prayer_profile_method, method_checksum_sha256="0" * 64),
        format="json",
    )
    assert mismatch.status_code == 409
    assert mismatch.json()["code"] == "prayer_method_checksum_mismatch"
    created = client.put(url, _payload(prayer_profile_method), format="json")
    prayer_profile_method.method.is_active = False
    prayer_profile_method.method.save(update_fields={"is_active", "updated_at"})

    fetched = client.get(url)
    retry = client.put(url, _payload(prayer_profile_method), format="json")
    replacement = client.put(
        url,
        _payload(prayer_profile_method, base_revision=1, asr_method="hanafi"),
        format="json",
    )

    assert created.status_code == 200
    assert fetched.status_code == 200
    assert fetched.json()["method_available"] is False
    assert fetched.json()["method_config"]["id"] == str(prayer_profile_method.id)
    assert retry.status_code == 200
    assert retry.json()["revision"] == 1
    assert retry.json()["method_available"] is False
    assert replacement.status_code == 410
    assert replacement.json()["code"] == "prayer_method_withdrawn"


@pytest.mark.django_db
def test_prayer_profile_rejects_unsupported_engine_and_marks_existing_profile_unavailable(
    unsupported_prayer_profile_method: PrayerMethodConfig,
) -> None:
    user = User.objects.create_user()
    client = APIClient()
    client.force_authenticate(user=user)
    url = reverse("prayer_profile:detail")

    rejected = client.put(url, _payload(unsupported_prayer_profile_method), format="json")

    assert rejected.status_code == 422
    assert rejected.json()["code"] == "prayer_engine_unsupported"
    assert not PrayerProfile.objects.filter(user=user).exists()

    # Simulate a profile that became stale after a backend engine/tzdb upgrade.
    PrayerProfile.objects.create(
        user=user,
        method_config=unsupported_prayer_profile_method,
        high_latitude_rule=HighLatitudeRule.MIDDLE_OF_NIGHT,
        polar_resolution=PolarCircleResolution.UNRESOLVED,
        client_updated_at=timezone.now(),
    )
    fetched = client.get(url)

    assert fetched.status_code == 200
    assert fetched.json()["method_available"] is False


@pytest.mark.django_db
def test_prayer_profile_device_is_nullable_and_never_accepted_from_request(
    prayer_profile_method: PrayerMethodConfig,
) -> None:
    user = User.objects.create_user()
    client, device = _client_with_device(user)
    url = reverse("prayer_profile:detail")
    client.put(url, _payload(prayer_profile_method), format="json")

    device.delete()
    profile = PrayerProfile.objects.get(user=user)
    response = client.get(url)

    assert profile.device_id is None
    # The forced auth object still contains the deleted device, but GET never persists it.
    assert response.status_code == 200
    assert response.json()["device_id"] is None


@pytest.mark.django_db
def test_prayer_profile_database_enforces_one_row_per_user(
    prayer_profile_method: PrayerMethodConfig,
) -> None:
    user = User.objects.create_user()
    now = timezone.now()
    common = {
        "user": user,
        "method_config": prayer_profile_method,
        "high_latitude_rule": "middle_of_night",
        "polar_resolution": "unresolved",
        "client_updated_at": now,
    }
    PrayerProfile.objects.create(**common)

    with pytest.raises(IntegrityError):
        PrayerProfile.objects.create(**common)


@pytest.mark.django_db
def test_prayer_profile_mutation_throttle_is_private(
    prayer_profile_method: PrayerMethodConfig,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    cache.clear()
    monkeypatch.setattr(
        PrayerProfileMutationThrottle,
        "THROTTLE_RATES",
        {"prayer_profile_mutation": "1/hour"},
    )
    user = User.objects.create_user()
    client = APIClient()
    client.force_authenticate(user=user)
    url = reverse("prayer_profile:detail")

    first = client.put(url, _payload(prayer_profile_method), format="json")
    limited = client.put(url, _payload(prayer_profile_method), format="json")

    assert first.status_code == 200
    assert limited.status_code == 429
    assert limited.json()["code"] == "prayer_profile_rate_limited"
    _assert_private(limited)
    assert int(limited.headers["Retry-After"]) >= 1
    cache.clear()


def test_prayer_profile_openapi_contract_is_authenticated_strict_and_versioned() -> None:
    schema = cast(
        dict[str, Any],
        SchemaGenerator().get_schema(public=True),  # type: ignore[no-untyped-call]
    )
    path = schema["paths"]["/api/v1/me/prayer-profile"]

    assert path["get"]["security"] == [{"bearerAuth": []}, {"cookieAuth": []}]
    assert path["put"]["security"] == [{"bearerAuth": []}, {"cookieAuth": []}]
    assert set(path["get"]["responses"]) == {"200", "401", "404"}
    assert set(path["put"]["responses"]) == {
        "200",
        "400",
        "401",
        "404",
        "409",
        "410",
        "422",
        "429",
    }
    request = schema["components"]["schemas"]["PrayerProfileWriteRequest"]
    assert request["additionalProperties"] is False
    assert (
        schema["components"]["schemas"]["PrayerAdjustmentsRequest"]["additionalProperties"] is False
    )
    assert set(request["required"]) >= {
        "base_revision",
        "method_config_id",
        "method_checksum_sha256",
        "asr_method",
        "high_latitude_rule",
        "polar_resolution",
        "adjustments",
        "timezone_mode",
        "client_updated_at",
    }
    assert "device_id" not in request["properties"]
    response = schema["components"]["schemas"]["PrayerProfileResponse"]
    assert "method_available" in response["required"]
    assert not {"latitude", "longitude", "location", "city", "occurrence_times"} & set(
        response["properties"]
    )


def test_prayer_profile_admin_is_read_only() -> None:
    model_admin = cast(PrayerProfileAdmin, admin.site._registry[PrayerProfile])
    assert model_admin.has_add_permission(None) is False  # type: ignore[arg-type]
    assert model_admin.has_change_permission(None) is False  # type: ignore[arg-type]
    assert model_admin.has_delete_permission(None) is False  # type: ignore[arg-type]
