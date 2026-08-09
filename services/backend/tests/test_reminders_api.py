from __future__ import annotations

import json
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from typing import Any, cast

import pytest
from django.core.cache import cache
from django.db import close_old_connections, connection
from django.test import override_settings
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
from quran_backend.modules.quran.models import (
    Ayah,
    PublicationStatus,
    QuranEditionVersion,
    RevelationType,
    Surah,
)
from quran_backend.modules.reminders.models import ReminderRule
from quran_backend.modules.reminders.throttling import ReminderMutationThrottle


def _client(user: User) -> APIClient:
    client = APIClient()
    client.force_authenticate(user=user)
    return client


def _timestamp() -> str:
    return timezone.now().isoformat()


def _prayer_payload(
    *,
    reminder_id: uuid.UUID | None = None,
    client_updated_at: str | None = None,
    **overrides: Any,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "id": str(reminder_id or uuid.uuid7()),
        "base_revision": 0,
        "client_updated_at": client_updated_at or _timestamp(),
        "reminder_type": "prayer",
        "schedule": {
            "kind": "prayer",
            "prayer_event": "fajr",
            "prayer_offset_minutes": -10,
        },
    }
    payload.update(overrides)
    return payload


def _reading_payload(**overrides: Any) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "id": str(uuid.uuid7()),
        "base_revision": 0,
        "client_updated_at": _timestamp(),
        "reminder_type": "quran_reading",
        "schedule": {"kind": "local_time", "local_time": "07:30:00"},
        "weekdays_mask": 0b0011111,
        "timezone": {"mode": "fixed", "name": "Europe/Istanbul"},
        "signal": "vibration",
        "is_enabled": False,
    }
    payload.update(overrides)
    return payload


def _assert_private(response: Any) -> None:
    assert response.headers["Cache-Control"] == PRIVATE_NO_STORE_CACHE_CONTROL
    assert response.headers["Pragma"] == "no-cache"
    assert response.headers["Expires"] == "0"
    assert "Authorization" in {item.strip() for item in response.headers["Vary"].split(",")}


@pytest.mark.django_db
def test_reminder_endpoints_require_authentication_and_are_always_private() -> None:
    client = APIClient()

    responses = [
        client.get(reverse("reminders:reminder-list")),
        client.post(reverse("reminders:reminder-list"), _prayer_payload(), format="json"),
        client.get(reverse("reminders:reminder-detail", kwargs={"reminder_id": uuid.uuid7()})),
    ]

    for response in responses:
        assert response.status_code in {401, 403}
        _assert_private(response)


@pytest.mark.django_db
def test_create_read_snapshot_and_exact_retry_are_authoritative_and_idempotent() -> None:
    user = User.objects.create_user()
    client = _client(user)
    payload = _prayer_payload()
    list_url = reverse("reminders:reminder-list")

    created = client.post(list_url, payload, format="json")
    retried = client.post(list_url, payload, format="json")
    snapshot = client.get(list_url)
    detail = client.get(
        reverse(
            "reminders:reminder-detail",
            kwargs={"reminder_id": payload["id"]},
        )
    )

    assert created.status_code == 201
    assert retried.status_code == 200
    assert created.json() == retried.json()
    assert created.json()["revision"] == 1
    assert created.json()["schedule"] == payload["schedule"]
    assert created.json()["timezone"] == {"mode": "device_local"}
    assert created.json()["delivery_mode"] == "local"
    assert created.json()["device_id"] is None
    assert snapshot.status_code == 200
    assert snapshot.json()["mode"] == "full_snapshot"
    assert snapshot.json()["authoritative"] is True
    assert snapshot.json()["count"] == 1
    assert snapshot.json()["reminders"] == [created.json()]
    assert detail.json() == created.json()
    assert ReminderRule.objects.count() == 1
    for response in (created, retried, snapshot, detail):
        _assert_private(response)


@pytest.mark.django_db
def test_same_create_id_with_different_normalized_payload_conflicts() -> None:
    user = User.objects.create_user()
    client = _client(user)
    payload = _prayer_payload()
    url = reverse("reminders:reminder-list")
    assert client.post(url, payload, format="json").status_code == 201

    changed = {
        **payload,
        "schedule": {**payload["schedule"], "prayer_offset_minutes": 5},
    }
    response = client.post(url, changed, format="json")

    assert response.status_code == 409
    assert response.json()["code"] == "reminder_create_conflict"
    assert ReminderRule.objects.get().revision == 1


@pytest.mark.django_db
def test_patch_uses_optimistic_revision_and_accepts_stale_matching_retry() -> None:
    user = User.objects.create_user()
    client = _client(user)
    payload = _reading_payload()
    created = client.post(reverse("reminders:reminder-list"), payload, format="json").json()
    url = reverse("reminders:reminder-detail", kwargs={"reminder_id": created["id"]})
    patch = {
        "base_revision": 1,
        "client_updated_at": _timestamp(),
        "signal": "silent",
        "timezone": {"mode": "device_local"},
        "is_enabled": True,
    }

    updated = client.patch(url, patch, format="json")
    retried = client.patch(url, {**patch, "client_updated_at": _timestamp()}, format="json")
    conflict = client.patch(
        url,
        {"base_revision": 1, "client_updated_at": _timestamp(), "signal": "sound"},
        format="json",
    )

    assert updated.status_code == 200
    assert updated.json()["revision"] == 2
    assert updated.json()["timezone"] == {"mode": "device_local"}
    assert updated.json()["signal"] == "silent"
    assert retried.status_code == 200
    assert retried.json() == updated.json()
    assert conflict.status_code == 409
    assert conflict.json()["code"] == "reminder_revision_conflict"


@pytest.mark.django_db
def test_delete_is_an_idempotent_tombstone_and_uuid_cannot_be_resurrected() -> None:
    user = User.objects.create_user()
    client = _client(user)
    create_payload = _prayer_payload()
    created = client.post(reverse("reminders:reminder-list"), create_payload, format="json").json()
    url = reverse("reminders:reminder-detail", kwargs={"reminder_id": created["id"]})
    delete_payload = {"base_revision": 1, "client_updated_at": _timestamp()}

    deleted = client.delete(url, delete_payload, format="json")
    replayed = client.delete(
        url,
        {"base_revision": 1, "client_updated_at": _timestamp()},
        format="json",
    )
    patch = client.patch(
        url,
        {"base_revision": 2, "client_updated_at": _timestamp(), "is_enabled": True},
        format="json",
    )
    resurrect = client.post(reverse("reminders:reminder-list"), create_payload, format="json")
    snapshot = client.get(reverse("reminders:reminder-list"))

    assert deleted.status_code == 200
    assert deleted.json()["revision"] == 2
    assert deleted.json()["deleted_at"] is not None
    assert deleted.json()["is_enabled"] is False
    assert replayed.status_code == 200
    assert replayed.json() == deleted.json()
    assert patch.status_code == 410
    assert patch.json()["code"] == "reminder_deleted"
    assert resurrect.status_code == 410
    assert resurrect.json()["code"] == "reminder_deleted"
    assert snapshot.json()["count"] == 1
    assert snapshot.json()["reminders"][0]["deleted_at"] is not None


@pytest.mark.django_db
def test_review_target_is_normalized_and_validated(quran_dataset: dict[str, Any]) -> None:
    user = User.objects.create_user()
    client = _client(user)
    payload = _reading_payload(
        reminder_type="quran_review",
        review_target={
            "start_ayah_id": str(quran_dataset["first_ayah"].id),
            "end_ayah_id": str(quran_dataset["second_ayah"].id),
        },
    )

    response = client.post(reverse("reminders:reminder-list"), payload, format="json")
    invalid = client.post(
        reverse("reminders:reminder-list"),
        {
            **payload,
            "id": str(uuid.uuid7()),
            "review_target": {
                "start_ayah_id": str(quran_dataset["second_ayah"].id),
                "end_ayah_id": str(quran_dataset["first_ayah"].id),
            },
        },
        format="json",
    )

    assert response.status_code == 201
    assert response.json()["review_target"]["start"] == {
        "id": str(quran_dataset["first_ayah"].id),
        "surah_number": 1,
        "ayah_number": 1,
    }
    assert invalid.status_code == 400
    assert "end_ayah" in json.dumps(invalid.json()["field_errors"])


@pytest.mark.django_db
@pytest.mark.parametrize(
    "status_value",
    [PublicationStatus.DRAFT, PublicationStatus.PUBLISHED],
    ids=["draft", "published-but-not-active"],
)
def test_review_target_hides_ayahs_outside_a_published_active_version(
    quran_dataset: dict[str, Any],
    status_value: str,
) -> None:
    hidden_version = QuranEditionVersion.objects.create(
        edition=quran_dataset["edition"],
        version=f"hidden-{status_value}",
        checksum_sha256="9" * 64,
        status=status_value,
        published_at=timezone.now() if status_value == PublicationStatus.PUBLISHED else None,
    )
    hidden_surah = Surah.objects.create(
        edition_version=hidden_version,
        number=1,
        name_ar="اختبار",
        name_en="Hidden",
        name_ru="Скрыто",
        revelation_type=RevelationType.MECCAN,
        ayah_count=1,
    )
    hidden_ayah = Ayah.objects.create(
        surah=hidden_surah,
        number=1,
        text_uthmani="اختبار",
        text_search="اختبار",
        juz_number=1,
    )
    payload = _reading_payload(
        reminder_type="quran_review",
        review_target={
            "start_ayah_id": str(hidden_ayah.id),
            "end_ayah_id": str(hidden_ayah.id),
        },
    )

    response = _client(User.objects.create_user()).post(
        reverse("reminders:reminder-list"),
        payload,
        format="json",
    )

    assert response.status_code == 400
    assert response.json()["code"] == "invalid"
    assert response.json()["field_errors"]["review_target"] == {
        "start_ayah_id": "Ayah was not found.",
        "end_ayah_id": "Ayah was not found.",
    }
    assert ReminderRule.objects.count() == 0


@pytest.mark.django_db
def test_saved_review_retries_survive_quran_active_version_rotation(
    quran_dataset: dict[str, Any],
) -> None:
    user = User.objects.create_user()
    client = _client(user)
    payload = _reading_payload(
        reminder_type="quran_review",
        review_target={
            "start_ayah_id": str(quran_dataset["first_ayah"].id),
            "end_ayah_id": str(quran_dataset["second_ayah"].id),
        },
    )
    url = reverse("reminders:reminder-list")
    created = client.post(url, payload, format="json")
    assert created.status_code == 201

    replacement = QuranEditionVersion.objects.create(
        edition=quran_dataset["edition"],
        version="2.0.0",
        checksum_sha256="8" * 64,
        status=PublicationStatus.PUBLISHED,
        published_at=timezone.now(),
    )
    edition = quran_dataset["edition"]
    edition.active_version = replacement
    edition.full_clean()
    edition.save(update_fields=["active_version", "updated_at"])

    exact_create_retry = client.post(url, payload, format="json")
    detail_url = reverse(
        "reminders:reminder-detail",
        kwargs={"reminder_id": created.json()["id"]},
    )
    patch = {
        "base_revision": 1,
        "client_updated_at": _timestamp(),
        "review_target": payload["review_target"],
        "signal": "silent",
    }
    updated = client.patch(detail_url, patch, format="json")
    stale_retry = client.patch(
        detail_url,
        {**patch, "client_updated_at": _timestamp()},
        format="json",
    )

    assert exact_create_retry.status_code == 200
    assert exact_create_retry.json() == created.json()
    assert updated.status_code == 200
    assert updated.json()["revision"] == 2
    assert stale_retry.status_code == 200
    assert stale_retry.json() == updated.json()


@pytest.mark.django_db
@pytest.mark.parametrize(
    "mutation",
    [
        lambda payload: payload.update({"latitude": 41.0}),
        lambda payload: payload.update({"coordinates": [41.0, 29.0]}),
        lambda payload: payload.update({"occurrence_at": _timestamp()}),
        lambda payload: payload.update({"push_token": "secret"}),
        lambda payload: payload.update({"device_id": str(uuid.uuid7())}),
        lambda payload: payload["schedule"].update({"unknown": True}),
        lambda payload: payload.update(
            {"timezone": {"mode": "device_local", "name": "Europe/Istanbul"}}
        ),
        lambda payload: payload.update({"reminder_type": "quran_reading", "review_target": None}),
    ],
    ids=[
        "latitude",
        "coordinates",
        "occurrence",
        "push-token",
        "device-id",
        "nested-unknown",
        "timezone-shape",
        "type-schedule-discriminator",
    ],
)
def test_create_strictly_rejects_private_or_mismatched_fields(mutation: Any) -> None:
    user = User.objects.create_user()
    payload = _prayer_payload()
    mutation(payload)

    response = _client(user).post(reverse("reminders:reminder-list"), payload, format="json")

    assert response.status_code == 400
    _assert_private(response)
    assert ReminderRule.objects.count() == 0


@pytest.mark.django_db
def test_auth_context_is_the_only_source_of_device_provenance() -> None:
    user = User.objects.create_user()
    device = Device.objects.create(
        user=user,
        platform=DevicePlatform.ANDROID,
        installation_id_hash="f" * 64,
    )
    session = RefreshSession.objects.create(
        user=user,
        device=device,
        expires_at=timezone.now() + timedelta(days=1),
    )
    token_client = APIClient()
    token_client.force_authenticate(
        user=user,
        token=AccessAuthContext(device=device, session=session),  # type: ignore[arg-type]
    )
    session_client = _client(user)
    url = reverse("reminders:reminder-list")

    token_response = token_client.post(url, _prayer_payload(), format="json")
    session_response = session_client.post(url, _prayer_payload(), format="json")

    assert token_response.status_code == 201
    assert token_response.json()["device_id"] == str(device.id)
    assert session_response.status_code == 201
    assert session_response.json()["device_id"] is None


@pytest.mark.django_db
def test_detail_endpoints_do_not_leak_another_users_reminder() -> None:
    owner = User.objects.create_user()
    stranger = User.objects.create_user()
    created = (
        _client(owner)
        .post(reverse("reminders:reminder-list"), _prayer_payload(), format="json")
        .json()
    )
    url = reverse("reminders:reminder-detail", kwargs={"reminder_id": created["id"]})
    stranger_client = _client(stranger)

    responses = [
        stranger_client.get(url),
        stranger_client.patch(
            url,
            {"base_revision": 1, "client_updated_at": _timestamp(), "signal": "silent"},
            format="json",
        ),
        stranger_client.delete(
            url,
            {"base_revision": 1, "client_updated_at": _timestamp()},
            format="json",
        ),
    ]

    for response in responses:
        assert response.status_code == 404
        assert response.json()["code"] == "reminder_not_found"


@pytest.mark.django_db
@override_settings(
    QURAN_REMINDER_MAX_ACTIVE_PER_USER=2,
    QURAN_REMINDER_MAX_TOTAL_PER_USER=2,
)
def test_active_and_total_quotas_are_enforced_with_tombstones_counted() -> None:
    user = User.objects.create_user()
    client = _client(user)
    url = reverse("reminders:reminder-list")
    first = client.post(url, _prayer_payload(), format="json").json()
    assert client.post(url, _prayer_payload(), format="json").status_code == 201
    detail = reverse("reminders:reminder-detail", kwargs={"reminder_id": first["id"]})
    assert (
        client.delete(
            detail,
            {"base_revision": 1, "client_updated_at": _timestamp()},
            format="json",
        ).status_code
        == 200
    )

    response = client.post(url, _prayer_payload(), format="json")

    assert response.status_code == 409
    assert response.json()["code"] == "reminder_quota_exceeded"
    assert client.get(url).json()["count"] == 2


@pytest.mark.django_db
def test_mutation_throttle_is_user_device_scoped_and_429_is_private(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    cache.clear()
    monkeypatch.setattr(
        ReminderMutationThrottle,
        "THROTTLE_RATES",
        {"reminder_mutation": "1/hour"},
    )
    user = User.objects.create_user()
    client = _client(user)
    url = reverse("reminders:reminder-list")

    accepted = client.post(url, _prayer_payload(), format="json")
    limited = client.post(url, _prayer_payload(), format="json")

    assert accepted.status_code == 201
    assert limited.status_code == 429
    assert limited.json()["code"] == "reminder_rate_limited"
    assert "Retry-After" in limited.headers
    _assert_private(limited)
    cache.clear()


@pytest.mark.django_db(transaction=True)
@override_settings(
    QURAN_REMINDER_MAX_ACTIVE_PER_USER=1,
    QURAN_REMINDER_MAX_TOTAL_PER_USER=256,
)
def test_concurrent_creates_cannot_exceed_active_quota_on_postgresql() -> None:
    if connection.vendor != "postgresql":
        pytest.skip("Row-lock concurrency semantics require PostgreSQL.")
    user = User.objects.create_user()
    url = reverse("reminders:reminder-list")
    payloads = [_prayer_payload(), _prayer_payload()]

    def create(payload: dict[str, Any]) -> int:
        close_old_connections()
        try:
            return (
                _client(User.objects.get(pk=user.pk)).post(url, payload, format="json").status_code
            )
        finally:
            close_old_connections()

    with ThreadPoolExecutor(max_workers=2) as executor:
        statuses = sorted(executor.map(create, payloads))

    assert statuses == [201, 409]
    assert ReminderRule.objects.filter(user=user, deleted_at__isnull=True).count() == 1


def test_openapi_exposes_authenticated_bounded_reminder_contract() -> None:
    schema = cast(
        dict[str, Any],
        SchemaGenerator().get_schema(public=True),  # type: ignore[no-untyped-call]
    )
    paths = schema["paths"]
    collection = paths["/api/v1/me/reminders"]
    detail = paths["/api/v1/me/reminders/{reminder_id}"]

    assert set(collection) >= {"get", "post"}
    assert set(detail) >= {"get", "patch", "delete"}
    assert collection["get"]["security"] != [{}]
    assert collection["post"]["security"] != [{}]
    assert set(collection["post"]["responses"]) == {
        "200",
        "201",
        "400",
        "401",
        "409",
        "410",
        "429",
    }
    create_schema = schema["components"]["schemas"]["ReminderCreateRequest"]
    assert create_schema["additionalProperties"] is False
    for component in (
        "ReminderPrayerScheduleRequest",
        "ReminderLocalTimeScheduleRequest",
        "ReminderDeviceLocalTimezoneRequest",
        "ReminderFixedTimezoneRequest",
    ):
        assert schema["components"]["schemas"][component]["additionalProperties"] is False
    assert set(create_schema["required"]) >= {
        "id",
        "base_revision",
        "client_updated_at",
        "reminder_type",
        "schedule",
    }
    snapshot_schema = schema["components"]["schemas"]["ReminderFullSnapshot"]
    assert snapshot_schema["properties"]["count"]["maximum"] == 256
    assert schema["components"]["schemas"]["ReminderScheduleRequest"]["discriminator"] == {
        "propertyName": "kind",
        "mapping": {
            "prayer": "#/components/schemas/ReminderPrayerScheduleRequest",
            "local_time": "#/components/schemas/ReminderLocalTimeScheduleRequest",
        },
    }
    assert schema["components"]["schemas"]["ReminderTimezoneRequest"]["discriminator"] == {
        "propertyName": "mode",
        "mapping": {
            "device_local": "#/components/schemas/ReminderDeviceLocalTimezoneRequest",
            "fixed": "#/components/schemas/ReminderFixedTimezoneRequest",
        },
    }
    assert "device_id" not in create_schema["properties"]
    for forbidden in ("latitude", "longitude", "coordinates", "occurrence_at", "push_token"):
        assert forbidden not in create_schema["properties"]
