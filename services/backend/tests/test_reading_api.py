from __future__ import annotations

import uuid
from datetime import timedelta
from typing import Any

import pytest
from django.core.cache import cache
from django.test import override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from quran_backend.modules.accounts.models import (
    Device,
    DevicePlatform,
    RefreshSession,
    User,
)
from quran_backend.modules.accounts.services import AccessAuthContext
from quran_backend.modules.reading.models import Bookmark, SyncChange, SyncOperation
from quran_backend.modules.reading.serializers import ReadingPositionPayloadSerializer
from quran_backend.modules.reading.throttling import (
    ReadingMutationRateThrottle,
    SyncPushDailyRateThrottle,
    SyncPushRateThrottle,
)


def _authenticated_client(user: User) -> APIClient:
    client = APIClient()
    client.force_authenticate(user=user)
    return client


def _timestamp() -> str:
    return timezone.now().isoformat()


def _position_payload(*, base_revision: int) -> dict[str, Any]:
    now = _timestamp()
    return {
        "base_revision": base_revision,
        "page_number": 1,
        "surah_number": 1,
        "ayah_number": 1,
        "intra_page_anchor": {"line_number": 2, "y_ratio": 0.25},
        "progress_percent": "0.16",
        "last_read_at": now,
        "client_updated_at": now,
    }


def _bookmark_sync_operation(
    *,
    operation_id: uuid.UUID,
    entity_id: uuid.UUID,
    base_revision: int = 0,
    label: str = "Daily reading",
) -> dict[str, Any]:
    return {
        "operation_id": str(operation_id),
        "entity_type": "bookmark",
        "entity_id": str(entity_id),
        "action": "upsert",
        "base_revision": base_revision,
        "client_updated_at": _timestamp(),
        "payload": {
            "edition_code": "madani-hafs",
            "page_number": 1,
            "label": label,
            "color_key": "green",
        },
    }


@pytest.mark.django_db
def test_reading_position_create_update_and_user_isolation(
    quran_dataset: dict[str, Any],
) -> None:
    owner = User.objects.create_user()
    other_user = User.objects.create_user()
    owner_client = _authenticated_client(owner)
    url = reverse("reading:reading-position", kwargs={"edition": "madani-hafs"})

    create_response = owner_client.put(url, _position_payload(base_revision=0), format="json")
    update_response = owner_client.put(url, _position_payload(base_revision=1), format="json")
    other_response = _authenticated_client(other_user).get(url)

    assert create_response.status_code == 200
    assert create_response.headers["Cache-Control"] == "private, no-store"
    assert create_response.json()["revision"] == 1
    assert create_response.json()["ayah"]["ayah_number"] == 1
    assert update_response.status_code == 200
    assert update_response.json()["revision"] == 2
    assert other_response.status_code == 404
    assert other_response.content_type == "application/problem+json"


@pytest.mark.django_db
def test_stale_position_revision_returns_problem_details(
    quran_dataset: dict[str, Any],
) -> None:
    user = User.objects.create_user()
    client = _authenticated_client(user)
    url = reverse("reading:reading-position", kwargs={"edition": "madani-hafs"})
    client.put(url, _position_payload(base_revision=0), format="json")

    response = client.put(url, _position_payload(base_revision=0), format="json")

    assert response.status_code == 409
    assert response.content_type == "application/problem+json"
    assert response.json()["code"] == "sync_revision_conflict"


@pytest.mark.django_db
def test_reading_anchor_rejects_unknown_non_finite_and_out_of_range_values(
    quran_dataset: dict[str, Any],
) -> None:
    user = User.objects.create_user()
    client = _authenticated_client(user)
    url = reverse("reading:reading-position", kwargs={"edition": "madani-hafs"})

    unknown = client.put(
        url,
        {**_position_payload(base_revision=0), "intra_page_anchor": {"offset": 0.5}},
        format="json",
    )
    out_of_range = client.put(
        url,
        {**_position_payload(base_revision=0), "intra_page_anchor": {"line_number": 31}},
        format="json",
    )
    non_finite = ReadingPositionPayloadSerializer(
        data={
            "edition_code": "madani-hafs",
            "page_number": 1,
            "last_read_at": _timestamp(),
            "intra_page_anchor": {"x_ratio": float("nan")},
        }
    )

    assert unknown.status_code == 400
    assert unknown.json()["code"] == "invalid"
    assert out_of_range.status_code == 400
    assert non_finite.is_valid() is False
    assert "intra_page_anchor" in non_finite.errors


@pytest.mark.django_db
def test_reading_mutation_rate_limit_is_scoped_to_user_and_device(
    quran_dataset: dict[str, Any],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    cache.clear()
    monkeypatch.setattr(
        ReadingMutationRateThrottle,
        "THROTTLE_RATES",
        {"reading_mutation": "1/hour"},
    )
    user = User.objects.create_user()
    first_device = Device.objects.create(
        user=user,
        platform=DevicePlatform.WEB,
        installation_id_hash="c" * 64,
    )
    second_device = Device.objects.create(
        user=user,
        platform=DevicePlatform.ANDROID,
        installation_id_hash="d" * 64,
    )
    first_session = RefreshSession.objects.create(
        user=user,
        device=first_device,
        expires_at=timezone.now() + timedelta(days=1),
    )
    second_session = RefreshSession.objects.create(
        user=user,
        device=second_device,
        expires_at=timezone.now() + timedelta(days=1),
    )
    first_client = APIClient()
    first_client.force_authenticate(
        user=user,
        token=AccessAuthContext(device=first_device, session=first_session),  # type: ignore[arg-type]
    )
    second_client = APIClient()
    second_client.force_authenticate(
        user=user,
        token=AccessAuthContext(device=second_device, session=second_session),  # type: ignore[arg-type]
    )
    url = reverse("reading:bookmark-list")

    accepted = first_client.post(
        url,
        {
            "id": str(uuid.uuid7()),
            "edition_code": "madani-hafs",
            "page_number": 1,
            "client_updated_at": _timestamp(),
        },
        format="json",
    )
    limited = first_client.post(
        url,
        {
            "id": str(uuid.uuid7()),
            "edition_code": "madani-hafs",
            "page_number": 1,
            "client_updated_at": _timestamp(),
        },
        format="json",
    )
    independent = second_client.post(
        url,
        {
            "id": str(uuid.uuid7()),
            "edition_code": "madani-hafs",
            "page_number": 1,
            "client_updated_at": _timestamp(),
        },
        format="json",
    )

    assert accepted.status_code == 201
    assert limited.status_code == 429
    assert limited.json()["code"] == "reading_rate_limited"
    assert "Retry-After" in limited.headers
    assert independent.status_code == 201
    cache.clear()


@pytest.mark.django_db
def test_sync_push_rate_limit_counts_operations_not_only_requests(
    quran_dataset: dict[str, Any],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    cache.clear()
    monkeypatch.setattr(
        SyncPushRateThrottle,
        "THROTTLE_RATES",
        {"sync_push": "2/hour"},
    )
    monkeypatch.setattr(
        SyncPushDailyRateThrottle,
        "THROTTLE_RATES",
        {"sync_push_daily": "100/day"},
    )
    user = User.objects.create_user()
    client = _authenticated_client(user)
    url = reverse("reading:sync-push")

    accepted = client.post(
        url,
        {
            "operations": [
                _bookmark_sync_operation(
                    operation_id=uuid.uuid7(),
                    entity_id=uuid.uuid7(),
                ),
                _bookmark_sync_operation(
                    operation_id=uuid.uuid7(),
                    entity_id=uuid.uuid7(),
                ),
            ]
        },
        format="json",
    )
    limited = client.post(
        url,
        {
            "operations": [
                _bookmark_sync_operation(
                    operation_id=uuid.uuid7(),
                    entity_id=uuid.uuid7(),
                )
            ]
        },
        format="json",
    )

    assert accepted.status_code == 200
    assert limited.status_code == 429
    assert limited.json()["code"] == "reading_rate_limited"
    cache.clear()


@pytest.mark.django_db
def test_sync_push_daily_budget_is_shared_by_a_users_devices(
    quran_dataset: dict[str, Any],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    cache.clear()
    monkeypatch.setattr(SyncPushRateThrottle, "THROTTLE_RATES", {"sync_push": "100/hour"})
    monkeypatch.setattr(
        SyncPushDailyRateThrottle,
        "THROTTLE_RATES",
        {"sync_push_daily": "2/day"},
    )
    user = User.objects.create_user()
    client = _authenticated_client(user)
    url = reverse("reading:sync-push")
    accepted = client.post(
        url,
        {
            "operations": [
                _bookmark_sync_operation(
                    operation_id=uuid.uuid7(),
                    entity_id=uuid.uuid7(),
                ),
                _bookmark_sync_operation(
                    operation_id=uuid.uuid7(),
                    entity_id=uuid.uuid7(),
                ),
            ]
        },
        format="json",
    )
    limited = client.post(
        url,
        {
            "operations": [
                _bookmark_sync_operation(
                    operation_id=uuid.uuid7(),
                    entity_id=uuid.uuid7(),
                )
            ]
        },
        format="json",
    )

    assert accepted.status_code == 200
    assert limited.status_code == 429
    assert limited.json()["code"] == "reading_rate_limited"
    cache.clear()


@pytest.mark.django_db
@override_settings(QURAN_BOOKMARK_MAX_PER_USER=1)
def test_bookmark_quota_applies_to_direct_and_sync_creates(
    quran_dataset: dict[str, Any],
) -> None:
    direct_user = User.objects.create_user()
    direct_client = _authenticated_client(direct_user)
    direct_url = reverse("reading:bookmark-list")
    direct_payload = {
        "id": str(uuid.uuid7()),
        "edition_code": "madani-hafs",
        "page_number": 1,
        "client_updated_at": _timestamp(),
    }
    assert direct_client.post(direct_url, direct_payload, format="json").status_code == 201

    direct_limited = direct_client.post(
        direct_url,
        {**direct_payload, "id": str(uuid.uuid7())},
        format="json",
    )

    sync_user = User.objects.create_user()
    sync_client = _authenticated_client(sync_user)
    sync_url = reverse("reading:sync-push")
    first_sync = _bookmark_sync_operation(
        operation_id=uuid.uuid7(),
        entity_id=uuid.uuid7(),
    )
    second_sync = _bookmark_sync_operation(
        operation_id=uuid.uuid7(),
        entity_id=uuid.uuid7(),
    )
    assert (
        sync_client.post(
            sync_url,
            {"operations": [first_sync]},
            format="json",
        ).status_code
        == 200
    )
    sync_limited = sync_client.post(
        sync_url,
        {"operations": [second_sync]},
        format="json",
    )

    assert direct_limited.status_code == 409
    assert direct_limited.json()["code"] == "bookmark_quota_exceeded"
    assert sync_limited.status_code == 200
    assert sync_limited.json()["results"][0]["outcome"] == "conflict"
    assert sync_limited.json()["results"][0]["conflict_reason"] == ("bookmark_quota_exceeded")
    assert Bookmark.objects.filter(user=direct_user).count() == 1
    assert Bookmark.objects.filter(user=sync_user).count() == 1


@pytest.mark.django_db
@override_settings(QURAN_BOOKMARK_MAX_PER_USER=1)
def test_sync_quota_conflict_is_per_operation_and_retryable(
    quran_dataset: dict[str, Any],
) -> None:
    user = User.objects.create_user()
    client = _authenticated_client(user)
    url = reverse("reading:sync-push")
    operations = [
        _bookmark_sync_operation(
            operation_id=uuid.uuid7(),
            entity_id=uuid.uuid7(),
        ),
        _bookmark_sync_operation(
            operation_id=uuid.uuid7(),
            entity_id=uuid.uuid7(),
        ),
    ]

    first = client.post(url, {"operations": operations}, format="json")
    retry = client.post(url, {"operations": operations}, format="json")

    assert first.status_code == 200
    assert [result["outcome"] for result in first.json()["results"]] == [
        "accepted",
        "conflict",
    ]
    assert first.json()["results"][1]["conflict_reason"] == "bookmark_quota_exceeded"
    assert retry.status_code == 200
    assert [result["replayed"] for result in retry.json()["results"]] == [True, True]
    assert Bookmark.objects.filter(user=user).count() == 1
    assert SyncOperation.objects.filter(user=user).count() == 2


@pytest.mark.django_db
def test_fatal_late_sync_error_rolls_back_the_entire_batch(
    quran_dataset: dict[str, Any],
) -> None:
    user = User.objects.create_user()
    client = _authenticated_client(user)
    first = _bookmark_sync_operation(
        operation_id=uuid.uuid7(),
        entity_id=uuid.uuid7(),
    )
    second = _bookmark_sync_operation(
        operation_id=uuid.uuid7(),
        entity_id=uuid.uuid7(),
    )
    second["payload"]["page_number"] = 2

    response = client.post(
        reverse("reading:sync-push"),
        {"operations": [first, second]},
        format="json",
    )

    assert response.status_code == 400
    assert Bookmark.objects.filter(user=user).count() == 0
    assert SyncChange.objects.filter(user=user).count() == 0
    assert SyncOperation.objects.filter(user=user).count() == 0


@pytest.mark.django_db
def test_unseen_bookmark_rejects_unusable_uuid7_timestamp(
    quran_dataset: dict[str, Any],
) -> None:
    user = User.objects.create_user()
    client = _authenticated_client(user)
    unusable_id = uuid.UUID("ffffffff-ffff-7000-8000-000000000000")

    direct = client.post(
        reverse("reading:bookmark-list"),
        {
            "id": str(unusable_id),
            "edition_code": "madani-hafs",
            "page_number": 1,
            "client_updated_at": _timestamp(),
        },
        format="json",
    )
    sync = client.post(
        reverse("reading:sync-push"),
        {
            "operations": [
                _bookmark_sync_operation(
                    operation_id=uuid.uuid7(),
                    entity_id=unusable_id,
                )
            ]
        },
        format="json",
    )

    assert direct.status_code == 409
    assert direct.json()["code"] == "bookmark_id_not_reusable"
    assert sync.status_code == 200
    assert sync.json()["results"][0]["conflict_reason"] == "entity_id_not_reusable"
    assert Bookmark.objects.filter(user=user).exists() is False


@pytest.mark.django_db
def test_bookmark_tombstone_hidden_from_default_list(
    quran_dataset: dict[str, Any],
) -> None:
    user = User.objects.create_user()
    client = _authenticated_client(user)
    list_url = reverse("reading:bookmark-list")
    create_response = client.post(
        list_url,
        {
            "id": str(uuid.uuid7()),
            "edition_code": "madani-hafs",
            "page_number": 1,
            "label": "Review",
            "client_updated_at": _timestamp(),
        },
        format="json",
    )
    bookmark_id = create_response.json()["id"]
    detail_url = reverse("reading:bookmark-detail", kwargs={"bookmark_id": bookmark_id})

    delete_response = client.delete(
        detail_url,
        query_params={
            "base_revision": 1,
            "client_updated_at": _timestamp(),
        },
    )
    active_list = client.get(list_url)
    tombstone_list = client.get(list_url, {"include_deleted": "true"})

    assert create_response.status_code == 201
    assert delete_response.status_code == 200
    assert delete_response.json()["revision"] == 2
    assert delete_response.json()["deleted_at"] is not None
    assert active_list.json()["results"] == []
    assert len(tombstone_list.json()["results"]) == 1


@pytest.mark.django_db
def test_bookmark_create_retry_is_idempotent_after_payload_normalization(
    quran_dataset: dict[str, Any],
) -> None:
    user = User.objects.create_user()
    client = _authenticated_client(user)
    bookmark_id = uuid.uuid7()
    client_updated_at = _timestamp()
    url = reverse("reading:bookmark-list")
    first_payload = {
        "id": str(bookmark_id),
        "edition_code": "madani-hafs",
        "page_number": 1,
        "client_updated_at": client_updated_at,
    }
    normalized_retry = {
        **first_payload,
        "label": "",
        "color_key": "default",
        "note": "",
    }

    first = client.post(url, first_payload, format="json")
    retry = client.post(url, normalized_retry, format="json")

    assert first.status_code == 201
    assert retry.status_code == 200
    assert retry.json() == first.json()
    assert retry.json()["revision"] == 1
    assert Bookmark.objects.filter(user=user, id=bookmark_id).count() == 1
    assert SyncChange.objects.filter(user=user).count() == 1


@pytest.mark.django_db
def test_bookmark_create_retry_with_changed_payload_conflicts(
    quran_dataset: dict[str, Any],
) -> None:
    user = User.objects.create_user()
    client = _authenticated_client(user)
    bookmark_id = uuid.uuid7()
    client_updated_at = _timestamp()
    url = reverse("reading:bookmark-list")
    original = {
        "id": str(bookmark_id),
        "edition_code": "madani-hafs",
        "page_number": 1,
        "label": "Original",
        "client_updated_at": client_updated_at,
    }
    client.post(url, original, format="json")

    response = client.post(url, {**original, "label": "Changed"}, format="json")

    assert response.status_code == 409
    assert response.json()["code"] == "bookmark_create_conflict"
    assert Bookmark.objects.get(user=user, id=bookmark_id).label == "Original"
    assert SyncChange.objects.filter(user=user).count() == 1


@pytest.mark.django_db
def test_bookmark_openapi_declares_cursor_and_page_size(
    quran_dataset: dict[str, Any],
) -> None:
    user = User.objects.create_user()
    response = _authenticated_client(user).get(
        reverse("openapi-schema"),
        headers={"Accept": "application/json"},
    )

    assert response.status_code == 200
    operation = response.json()["paths"]["/api/v1/me/bookmarks"]["get"]
    parameter_names = {parameter["name"] for parameter in operation["parameters"]}
    assert {"cursor", "page_size", "include_deleted"} <= parameter_names


@pytest.mark.django_db
def test_bookmark_detail_is_isolated_by_user(quran_dataset: dict[str, Any]) -> None:
    owner = User.objects.create_user()
    stranger = User.objects.create_user()
    create_response = _authenticated_client(owner).post(
        reverse("reading:bookmark-list"),
        {
            "id": str(uuid.uuid7()),
            "edition_code": "madani-hafs",
            "page_number": 1,
            "client_updated_at": _timestamp(),
        },
        format="json",
    )
    url = reverse(
        "reading:bookmark-detail",
        kwargs={"bookmark_id": create_response.json()["id"]},
    )

    response = _authenticated_client(stranger).get(url)

    assert response.status_code == 404
    assert response.json()["code"] == "bookmark_not_found"


@pytest.mark.django_db
def test_sync_push_is_idempotent(quran_dataset: dict[str, Any]) -> None:
    user = User.objects.create_user()
    client = _authenticated_client(user)
    operation = _bookmark_sync_operation(
        operation_id=uuid.uuid7(),
        entity_id=uuid.uuid7(),
    )
    url = reverse("reading:sync-push")

    first_response = client.post(url, {"operations": [operation]}, format="json")
    replay_response = client.post(url, {"operations": [operation]}, format="json")

    assert first_response.status_code == 200
    assert first_response.json()["results"][0]["outcome"] == "accepted"
    assert first_response.json()["results"][0]["replayed"] is False
    assert replay_response.status_code == 200
    assert replay_response.json()["results"][0]["replayed"] is True
    assert replay_response.json()["cursor"] == first_response.json()["cursor"] == 1
    assert Bookmark.objects.filter(user=user).count() == 1
    assert SyncChange.objects.filter(user=user).count() == 1
    assert SyncOperation.objects.filter(user=user).count() == 1


@pytest.mark.django_db
def test_sync_client_id_collision_does_not_expose_another_users_entity(
    quran_dataset: dict[str, Any],
) -> None:
    first_user = User.objects.create_user()
    second_user = User.objects.create_user()
    entity_id = uuid.uuid7()
    push_url = reverse("reading:sync-push")
    first_response = _authenticated_client(first_user).post(
        push_url,
        {
            "operations": [
                _bookmark_sync_operation(
                    operation_id=uuid.uuid7(),
                    entity_id=entity_id,
                    label="Private label",
                )
            ]
        },
        format="json",
    )

    collision_response = _authenticated_client(second_user).post(
        push_url,
        {
            "operations": [
                _bookmark_sync_operation(
                    operation_id=uuid.uuid7(),
                    entity_id=entity_id,
                    label="Collision",
                )
            ]
        },
        format="json",
    )

    assert first_response.json()["results"][0]["outcome"] == "accepted"
    collision = collision_response.json()["results"][0]
    assert collision["outcome"] == "conflict"
    assert collision["conflict_reason"] == "entity_id_unavailable"
    assert collision["entity"] is None
    assert Bookmark.objects.filter(id=entity_id, user=first_user).count() == 1
    assert Bookmark.objects.filter(user=second_user).count() == 0


@pytest.mark.django_db
def test_bearer_auth_context_prevents_device_masquerading(
    quran_dataset: dict[str, Any],
) -> None:
    user = User.objects.create_user()
    authenticated_device = Device.objects.create(
        user=user,
        platform=DevicePlatform.WEB,
        installation_id_hash="a" * 64,
    )
    other_device = Device.objects.create(
        user=user,
        platform=DevicePlatform.ANDROID,
        installation_id_hash="b" * 64,
    )
    session = RefreshSession.objects.create(
        user=user,
        device=authenticated_device,
        expires_at=timezone.now() + timedelta(days=1),
    )
    client = APIClient()
    client.force_authenticate(
        user=user,
        token=AccessAuthContext(device=authenticated_device, session=session),  # type: ignore[arg-type]
    )

    rejected = client.post(
        reverse("reading:bookmark-list"),
        {
            "id": str(uuid.uuid7()),
            "edition_code": "madani-hafs",
            "page_number": 1,
            "client_updated_at": _timestamp(),
            "device_id": str(other_device.id),
        },
        format="json",
    )
    accepted = client.post(
        reverse("reading:bookmark-list"),
        {
            "id": str(uuid.uuid7()),
            "edition_code": "madani-hafs",
            "page_number": 1,
            "client_updated_at": _timestamp(),
        },
        format="json",
    )

    assert rejected.status_code == 400
    assert accepted.status_code == 201
    assert accepted.json()["device_id"] == str(authenticated_device.id)


@pytest.mark.django_db
def test_reusing_operation_id_with_different_payload_is_rejected(
    quran_dataset: dict[str, Any],
) -> None:
    user = User.objects.create_user()
    client = _authenticated_client(user)
    operation_id = uuid.uuid7()
    entity_id = uuid.uuid7()
    original = _bookmark_sync_operation(operation_id=operation_id, entity_id=entity_id)
    changed = dict(original)
    changed["payload"] = {**original["payload"], "label": "Changed"}
    url = reverse("reading:sync-push")
    client.post(url, {"operations": [original]}, format="json")

    response = client.post(url, {"operations": [changed]}, format="json")

    assert response.status_code == 409
    assert response.json()["code"] == "sync_operation_reuse"
    assert SyncChange.objects.filter(user=user).count() == 1


@pytest.mark.django_db
def test_sync_conflict_preserves_server_bookmark(quran_dataset: dict[str, Any]) -> None:
    user = User.objects.create_user()
    client = _authenticated_client(user)
    entity_id = uuid.uuid7()
    create = _bookmark_sync_operation(operation_id=uuid.uuid7(), entity_id=entity_id)
    first_update = _bookmark_sync_operation(
        operation_id=uuid.uuid7(),
        entity_id=entity_id,
        base_revision=1,
        label="First writer",
    )
    stale_update = _bookmark_sync_operation(
        operation_id=uuid.uuid7(),
        entity_id=entity_id,
        base_revision=1,
        label="Stale writer",
    )
    url = reverse("reading:sync-push")
    client.post(url, {"operations": [create]}, format="json")
    accepted = client.post(url, {"operations": [first_update]}, format="json")

    conflict = client.post(url, {"operations": [stale_update]}, format="json")

    assert accepted.json()["results"][0]["outcome"] == "accepted"
    assert conflict.status_code == 200
    assert conflict.json()["results"][0]["outcome"] == "conflict"
    assert conflict.json()["results"][0]["conflict_reason"] == "revision_mismatch"
    assert conflict.json()["results"][0]["entity"]["label"] == "First writer"
    bookmark = Bookmark.objects.get(user=user, id=entity_id)
    assert bookmark.label == "First writer"
    assert bookmark.revision == 2


@pytest.mark.django_db
def test_sync_pull_is_monotonic_paginated_and_user_scoped(
    quran_dataset: dict[str, Any],
) -> None:
    first_user = User.objects.create_user()
    second_user = User.objects.create_user()
    first_client = _authenticated_client(first_user)
    second_client = _authenticated_client(second_user)
    push_url = reverse("reading:sync-push")
    for _ in range(2):
        first_client.post(
            push_url,
            {
                "operations": [
                    _bookmark_sync_operation(
                        operation_id=uuid.uuid7(),
                        entity_id=uuid.uuid7(),
                    )
                ]
            },
            format="json",
        )
    second_client.post(
        push_url,
        {
            "operations": [
                _bookmark_sync_operation(
                    operation_id=uuid.uuid7(),
                    entity_id=uuid.uuid7(),
                    label="Private second user",
                )
            ]
        },
        format="json",
    )
    pull_url = reverse("reading:sync-pull")

    first_page = first_client.get(pull_url, {"cursor": 0, "limit": 1})
    second_page = first_client.get(
        pull_url,
        {"cursor": first_page.json()["next_cursor"], "limit": 1},
    )

    assert first_page.status_code == 200
    assert first_page.json()["has_more"] is True
    assert first_page.json()["changes"][0]["cursor"] == 1
    assert second_page.json()["has_more"] is False
    assert second_page.json()["changes"][0]["cursor"] == 2
    labels = {
        first_page.json()["changes"][0]["entity"]["label"],
        second_page.json()["changes"][0]["entity"]["label"],
    }
    assert "Private second user" not in labels
