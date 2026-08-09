from __future__ import annotations

import hashlib
import json
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta
from importlib import import_module
from threading import Barrier
from types import SimpleNamespace
from typing import Any

import pytest
from django.apps import apps
from django.core.serializers.json import DjangoJSONEncoder
from django.db import close_old_connections, connection
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
from quran_backend.modules.reading.models import (
    Bookmark,
    SyncChange,
    SyncOperation,
    UserSyncCursor,
)
from quran_backend.modules.reading.serializers import SyncOperationInputSerializer
from quran_backend.modules.reminders.models import ReminderRule


def _client(user: User) -> APIClient:
    client = APIClient()
    client.force_authenticate(user=user)
    return client


def _timestamp() -> str:
    return timezone.now().isoformat()


def _functional_payload(**overrides: Any) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "reminder_type": "prayer",
        "schedule": {
            "kind": "prayer",
            "prayer_event": "fajr",
            "prayer_offset_minutes": -10,
        },
    }
    payload.update(overrides)
    return payload


def _operation(  # noqa: PLR0913
    *,
    entity_id: uuid.UUID,
    operation_id: uuid.UUID | None = None,
    base_revision: int = 0,
    action: str = "upsert",
    payload: dict[str, Any] | None = None,
    client_updated_at: str | None = None,
) -> dict[str, Any]:
    return {
        "operation_id": str(operation_id or uuid.uuid7()),
        "entity_type": "reminder",
        "entity_id": str(entity_id),
        "action": action,
        "base_revision": base_revision,
        "client_updated_at": client_updated_at or _timestamp(),
        "payload": _functional_payload()
        if payload is None and action == "upsert"
        else payload or {},
    }


def _push(client: APIClient, *operations: dict[str, Any]) -> Any:
    return client.post(
        reverse("reading:sync-push"),
        {"operations": list(operations)},
        format="json",
    )


@pytest.mark.django_db
def test_direct_reminder_mutations_append_exactly_once_to_incremental_sync() -> None:
    user = User.objects.create_user()
    client = _client(user)
    reminder_id = uuid.uuid7()
    create_payload = {
        "id": str(reminder_id),
        "base_revision": 0,
        "client_updated_at": _timestamp(),
        **_functional_payload(),
    }
    reminder_url = reverse("reminders:reminder-list")
    detail_url = reverse("reminders:reminder-detail", kwargs={"reminder_id": reminder_id})

    created = client.post(reminder_url, create_payload, format="json")
    create_retry = client.post(reminder_url, create_payload, format="json")
    patched = client.patch(
        detail_url,
        {"base_revision": 1, "client_updated_at": _timestamp(), "signal": "silent"},
        format="json",
    )
    patch_retry = client.patch(
        detail_url,
        {"base_revision": 1, "client_updated_at": _timestamp(), "signal": "silent"},
        format="json",
    )
    deleted = client.delete(
        detail_url,
        {"base_revision": 2, "client_updated_at": _timestamp()},
        format="json",
    )
    delete_retry = client.delete(
        detail_url,
        {"base_revision": 1, "client_updated_at": _timestamp()},
        format="json",
    )
    pulled = client.get(reverse("reading:sync-pull"), {"cursor": 0})

    assert [response.status_code for response in (created, create_retry, patched, patch_retry)] == [
        201,
        200,
        200,
        200,
    ]
    assert deleted.status_code == delete_retry.status_code == 200
    assert SyncChange.objects.filter(user=user).count() == 3
    assert [change["action"] for change in pulled.json()["changes"]] == [
        "delete",
        "delete",
        "delete",
    ]
    assert all(change["entity_type"] == "reminder" for change in pulled.json()["changes"])
    tombstone = pulled.json()["changes"][-1]["entity"]
    assert tombstone["entity_type"] == "reminder"
    assert tombstone["schedule"] is None
    assert tombstone["device_id"] is None
    for change in pulled.json()["changes"]:
        assert change["entity"]["schedule"] is None
        assert change["entity"]["review_target"] is None
        assert change["entity"]["timezone"] == {"mode": "device_local"}


@pytest.mark.django_db
def test_sync_create_patch_delete_are_visible_in_direct_snapshot_and_replay_safely() -> None:
    user = User.objects.create_user()
    client = _client(user)
    reminder_id = uuid.uuid7()
    create_operation = _operation(
        entity_id=reminder_id,
        client_updated_at="2026-08-09T12:00:00Z",
    )
    normalized_replay = {
        **create_operation,
        "client_updated_at": "2026-08-09T12:00:00+00:00",
        "payload": {
            "is_enabled": True,
            "signal": "sound",
            "timezone": {"mode": "device_local"},
            "weekdays_mask": 127,
            "schedule": {
                "prayer_offset_minutes": -10,
                "prayer_event": "fajr",
                "kind": "prayer",
            },
            "reminder_type": "prayer",
        },
    }

    created = _push(client, create_operation)
    exact_replay = _push(client, normalized_replay)
    semantic_retry = _push(
        client,
        _operation(
            entity_id=reminder_id,
            client_updated_at=create_operation["client_updated_at"],
        ),
    )
    patched = _push(
        client,
        _operation(
            entity_id=reminder_id,
            base_revision=1,
            payload={"signal": "silent"},
        ),
    )
    stale_matching_patch = _push(
        client,
        _operation(
            entity_id=reminder_id,
            base_revision=1,
            payload={"signal": "silent"},
        ),
    )
    stale_different_patch = _push(
        client,
        _operation(
            entity_id=reminder_id,
            base_revision=1,
            payload={"signal": "vibration"},
        ),
    )
    delete_operation = _operation(
        entity_id=reminder_id,
        base_revision=2,
        action="delete",
        payload={},
    )
    deleted = _push(client, delete_operation)
    omitted_delete_replay = dict(delete_operation)
    omitted_delete_replay.pop("payload")
    exact_delete_replay = _push(client, omitted_delete_replay)
    repeated_delete = _push(
        client,
        _operation(
            entity_id=reminder_id,
            base_revision=1,
            action="delete",
            payload={},
        ),
    )
    resurrection = _push(client, _operation(entity_id=reminder_id))
    snapshot = client.get(reverse("reminders:reminder-list"))

    assert created.status_code == exact_replay.status_code == semantic_retry.status_code == 200
    assert created.json()["results"][0]["entity"]["entity_type"] == "reminder"
    assert exact_replay.json()["results"][0]["replayed"] is True
    assert semantic_retry.json()["results"][0]["replayed"] is False
    assert patched.json()["results"][0]["entity"]["revision"] == 2
    assert stale_matching_patch.json()["results"][0]["outcome"] == "accepted"
    assert stale_different_patch.json()["results"][0]["outcome"] == "conflict"
    assert stale_different_patch.json()["results"][0]["conflict_reason"] == ("revision_mismatch")
    assert deleted.json()["results"][0]["entity"]["revision"] == 3
    assert exact_delete_replay.json()["results"][0]["replayed"] is True
    assert repeated_delete.json()["results"][0]["outcome"] == "accepted"
    assert resurrection.json()["results"][0]["outcome"] == "conflict"
    assert resurrection.json()["results"][0]["conflict_reason"] == ("entity_id_not_reusable")
    assert resurrection.json()["results"][0]["entity"]["deleted_at"] is not None
    assert snapshot.json()["reminders"][0]["deleted_at"] is not None
    assert ReminderRule.objects.get(id=reminder_id).revision == 3
    assert SyncChange.objects.filter(user=user, entity_id=reminder_id).count() == 3
    assert SyncOperation.objects.filter(user=user, entity_id=reminder_id).count() == 8
    assert all(
        operation.response["entity"] is None
        for operation in SyncOperation.objects.filter(user=user, entity_id=reminder_id)
    )


@pytest.mark.django_db
def test_reminder_sync_conflicts_are_persisted_and_operation_id_reuse_is_fatal() -> None:
    user = User.objects.create_user()
    client = _client(user)
    reminder_id = uuid.uuid7()
    assert _push(client, _operation(entity_id=reminder_id)).status_code == 200
    conflict_id = uuid.uuid7()
    conflict = _operation(
        entity_id=reminder_id,
        operation_id=conflict_id,
        base_revision=0,
        payload=_functional_payload(signal="silent"),
    )

    first = _push(client, conflict)
    replay = _push(client, conflict)
    reused = _push(client, {**conflict, "payload": _functional_payload(signal="vibration")})

    assert first.status_code == replay.status_code == 200
    assert first.json()["results"][0]["outcome"] == "conflict"
    assert first.json()["results"][0]["conflict_reason"] == "revision_mismatch"
    assert first.json()["results"][0]["entity"]["id"] == str(reminder_id)
    assert replay.json()["results"][0]["replayed"] is True
    assert reused.status_code == 409
    assert reused.json()["code"] == "sync_operation_reuse"
    assert SyncChange.objects.filter(user=user).count() == 1


@pytest.mark.django_db
def test_legacy_bookmark_operation_hash_remains_replay_compatible() -> None:
    user = User.objects.create_user()
    operation_id = uuid.uuid7()
    entity_id = uuid.uuid7()
    request_operation = {
        "operation_id": str(operation_id),
        "entity_type": "bookmark",
        "entity_id": str(entity_id),
        "action": "upsert",
        "base_revision": 0,
        "client_updated_at": "2026-08-09T12:00:00Z",
        "payload": {"edition_code": "madani-hafs", "page_number": 1},
    }
    serializer = SyncOperationInputSerializer(data=request_operation)
    serializer.is_valid(raise_exception=True)
    normalized = dict(serializer.validated_data)
    legacy_hash = hashlib.sha256(
        json.dumps(
            normalized,
            cls=DjangoJSONEncoder,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
        ).encode()
    ).hexdigest()
    SyncOperation.objects.create(
        user=user,
        operation_id=operation_id,
        entity_type="bookmark",
        entity_id=entity_id,
        action="upsert",
        request_hash=legacy_hash,
        outcome="accepted",
        response={
            "operation_id": str(operation_id),
            "outcome": "accepted",
            "replayed": False,
            "entity": None,
            "cursor": 0,
        },
    )

    replay = _push(_client(user), request_operation)

    assert replay.status_code == 200
    assert replay.json()["results"][0]["replayed"] is True
    assert SyncChange.objects.filter(user=user).exists() is False


@pytest.mark.django_db
def test_reminder_sync_migration_backfills_existing_rules_idempotently() -> None:
    user = User.objects.create_user()
    reminder = ReminderRule.objects.create(
        user=user,
        reminder_type="prayer",
        prayer_event="fajr",
        prayer_offset_minutes=-10,
        client_updated_at=timezone.now(),
    )
    migration = import_module("quran_backend.modules.reading.migrations.0005_sync_entity_reminder")
    schema_editor = SimpleNamespace(connection=connection)

    migration.backfill_reminder_changes(apps, schema_editor)
    migration.backfill_reminder_changes(apps, schema_editor)

    change = SyncChange.objects.get(user=user, entity_id=reminder.id)
    assert change.sequence == 1
    assert change.entity_type == "reminder"
    assert change.action == "upsert"
    assert change.snapshot["schedule"] == {
        "kind": "prayer",
        "prayer_event": "fajr",
        "prayer_offset_minutes": -10,
    }
    assert change.snapshot["entity_type"] == "reminder"
    assert UserSyncCursor.objects.get(user=user).value == 1


@pytest.mark.django_db
def test_reminder_dispatch_isolated_from_bookmark_with_same_uuid(
    quran_dataset: dict[str, Any],
) -> None:
    user = User.objects.create_user()
    client = _client(user)
    shared_id = uuid.uuid7()
    bookmark = client.post(
        reverse("reading:bookmark-list"),
        {
            "id": str(shared_id),
            "edition_code": "madani-hafs",
            "page_number": 1,
            "client_updated_at": _timestamp(),
        },
        format="json",
    )
    missing_reminder_delete = _push(
        client,
        _operation(
            entity_id=shared_id,
            base_revision=1,
            action="delete",
            payload={},
        ),
    )

    assert bookmark.status_code == 201
    assert missing_reminder_delete.status_code == 200
    result = missing_reminder_delete.json()["results"][0]
    assert result["outcome"] == "conflict"
    assert result["conflict_reason"] == "entity_missing"
    assert Bookmark.objects.get(user=user, id=shared_id).deleted_at is None


@pytest.mark.django_db
def test_cross_user_reminder_uuid_conflicts_never_expose_owner_state() -> None:
    owner = User.objects.create_user()
    stranger = User.objects.create_user()
    reminder_id = uuid.uuid7()
    assert _push(_client(owner), _operation(entity_id=reminder_id)).status_code == 200
    stranger_client = _client(stranger)

    create_collision = _push(stranger_client, _operation(entity_id=reminder_id))
    missing_patch = _push(
        stranger_client,
        _operation(entity_id=reminder_id, base_revision=1, payload={"signal": "silent"}),
    )
    missing_delete = _push(
        stranger_client,
        _operation(
            entity_id=reminder_id,
            base_revision=1,
            action="delete",
            payload={},
        ),
    )

    create_result = create_collision.json()["results"][0]
    assert create_result["outcome"] == "conflict"
    assert create_result["conflict_reason"] == "entity_id_unavailable"
    assert create_result["entity"] is None
    for response in (missing_patch, missing_delete):
        result = response.json()["results"][0]
        assert result["outcome"] == "conflict"
        assert result["conflict_reason"] == "entity_missing"
        assert result["entity"] is None
    assert ReminderRule.objects.get(id=reminder_id).user_id == owner.id


@pytest.mark.django_db
@override_settings(
    QURAN_REMINDER_MAX_ACTIVE_PER_USER=1,
    QURAN_REMINDER_MAX_TOTAL_PER_USER=2,
)
def test_sync_reminder_create_uses_the_same_active_quota_as_direct_crud() -> None:
    user = User.objects.create_user()
    client = _client(user)

    first = _push(client, _operation(entity_id=uuid.uuid7()))
    limited = _push(client, _operation(entity_id=uuid.uuid7()))

    assert first.json()["results"][0]["outcome"] == "accepted"
    assert limited.json()["results"][0]["outcome"] == "conflict"
    assert limited.json()["results"][0]["conflict_reason"] == "reminder_quota_exceeded"
    assert ReminderRule.objects.filter(user=user).count() == 1


@pytest.mark.django_db
def test_reminder_sync_rejects_spoofed_device_and_uses_access_context() -> None:
    user = User.objects.create_user()
    device = Device.objects.create(
        user=user,
        platform=DevicePlatform.ANDROID,
        installation_id_hash="e" * 64,
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
    entity_id = uuid.uuid7()
    create_operation = _operation(entity_id=entity_id)
    spoofed = _operation(entity_id=uuid.uuid7())
    spoofed["device_id"] = str(device.id)

    rejected = _push(token_client, spoofed)
    created = _push(token_client, create_operation)
    same_device_replay = _push(token_client, create_operation)

    second_device = Device.objects.create(
        user=user,
        platform=DevicePlatform.IOS,
        installation_id_hash="d" * 64,
    )
    second_session = RefreshSession.objects.create(
        user=user,
        device=second_device,
        expires_at=timezone.now() + timedelta(days=1),
    )
    second_client = APIClient()
    second_client.force_authenticate(
        user=user,
        token=AccessAuthContext(device=second_device, session=second_session),  # type: ignore[arg-type]
    )
    cross_device_replay = _push(second_client, create_operation)

    assert rejected.status_code == 400
    assert "device_id" in str(rejected.json()["field_errors"])
    assert created.status_code == 200
    assert created.json()["results"][0]["entity"]["device_id"] == str(device.id)
    assert same_device_replay.json()["results"][0]["replayed"] is True
    assert cross_device_replay.status_code == 409
    assert cross_device_replay.json()["code"] == "sync_operation_reuse"


@pytest.mark.django_db
def test_full_resync_paginates_bookmark_then_reminders_including_tombstones(
    quran_dataset: dict[str, Any],
) -> None:
    user = User.objects.create_user()
    client = _client(user)
    bookmark_id = uuid.uuid7()
    assert (
        client.post(
            reverse("reading:bookmark-list"),
            {
                "id": str(bookmark_id),
                "edition_code": "madani-hafs",
                "page_number": 1,
                "client_updated_at": _timestamp(),
            },
            format="json",
        ).status_code
        == 201
    )
    reminder_ids = [uuid.uuid7(), uuid.uuid7()]
    for reminder_id in reminder_ids:
        assert _push(client, _operation(entity_id=reminder_id)).status_code == 200
    assert (
        _push(
            client,
            _operation(
                entity_id=reminder_ids[0],
                base_revision=1,
                action="delete",
                payload={},
            ),
        ).status_code
        == 200
    )

    collected: list[dict[str, Any]] = []
    page_token: str | None = None
    snapshot_cursor: int | None = None
    while True:
        query: dict[str, Any] = {"full_resync": "true", "limit": 1}
        if page_token is not None:
            query["page_token"] = page_token
        response = client.get(reverse("reading:sync-pull"), query)
        assert response.status_code == 200
        body = response.json()
        if snapshot_cursor is None:
            snapshot_cursor = body["snapshot_cursor"]
        assert body["snapshot_cursor"] == snapshot_cursor
        collected.extend(body["entities"])
        page_token = body["next_page_token"]
        if not body["has_more"]:
            break

    assert [entity["entity_type"] for entity in collected] == [
        "bookmark",
        "reminder",
        "reminder",
    ]
    assert {entity["id"] for entity in collected} == {
        str(bookmark_id),
        *(str(value) for value in reminder_ids),
    }
    tombstones = [entity for entity in collected if entity.get("deleted_at") is not None]
    assert len(tombstones) == 1
    assert tombstones[0]["schedule"] is None


@pytest.mark.django_db
def test_invalid_late_reminder_operation_rolls_back_earlier_mixed_batch() -> None:
    user = User.objects.create_user()
    client = _client(user)
    first_id = uuid.uuid7()
    first = _operation(entity_id=first_id)
    invalid = _operation(
        entity_id=uuid.uuid7(),
        payload={
            "reminder_type": "quran_review",
            "schedule": {"kind": "local_time", "local_time": "07:30:00"},
            "review_target": {
                "start_ayah_id": str(uuid.uuid7()),
                "end_ayah_id": str(uuid.uuid7()),
            },
        },
    )

    response = _push(client, first, invalid)

    assert response.status_code == 400
    assert ReminderRule.objects.filter(user=user).exists() is False
    assert SyncChange.objects.filter(user=user).exists() is False
    assert SyncOperation.objects.filter(user=user).exists() is False


@pytest.mark.django_db(transaction=True)
def test_concurrent_direct_bookmark_and_mixed_sync_batch_share_lock_order(
    quran_dataset: dict[str, Any],
) -> None:
    if connection.vendor != "postgresql":
        pytest.skip("PostgreSQL row-lock regression test.")

    user = User.objects.create_user()
    client = _client(user)
    bookmark_id = uuid.uuid7()
    reminder_id = uuid.uuid7()
    bookmark_url = reverse("reading:bookmark-list")
    bookmark_detail_url = reverse(
        "reading:bookmark-detail",
        kwargs={"bookmark_id": bookmark_id},
    )
    assert (
        client.post(
            bookmark_url,
            {
                "id": str(bookmark_id),
                "edition_code": "madani-hafs",
                "page_number": 1,
                "client_updated_at": _timestamp(),
            },
            format="json",
        ).status_code
        == 201
    )
    assert _push(client, _operation(entity_id=reminder_id)).status_code == 200
    barrier = Barrier(2)

    def direct_patch() -> int:
        close_old_connections()
        try:
            barrier.wait(timeout=5)
            response = _client(user).patch(
                bookmark_detail_url,
                {
                    "base_revision": 1,
                    "client_updated_at": _timestamp(),
                    "label": "direct",
                },
                format="json",
            )
            return response.status_code
        finally:
            close_old_connections()

    def mixed_sync() -> tuple[int, list[str]]:
        close_old_connections()
        try:
            barrier.wait(timeout=5)
            response = _push(
                _client(user),
                _operation(
                    entity_id=reminder_id,
                    base_revision=1,
                    payload={"signal": "silent"},
                ),
                {
                    "operation_id": str(uuid.uuid7()),
                    "entity_type": "bookmark",
                    "entity_id": str(bookmark_id),
                    "action": "upsert",
                    "base_revision": 1,
                    "client_updated_at": _timestamp(),
                    "payload": {"label": "sync"},
                },
            )
            outcomes = [result["outcome"] for result in response.json().get("results", [])]
            return response.status_code, outcomes
        finally:
            close_old_connections()

    with ThreadPoolExecutor(max_workers=2) as executor:
        direct_future = executor.submit(direct_patch)
        sync_future = executor.submit(mixed_sync)
        direct_status = direct_future.result(timeout=15)
        sync_status, outcomes = sync_future.result(timeout=15)

    assert direct_status in {200, 409}
    assert sync_status == 200
    assert outcomes[0] == "accepted"
    assert outcomes[1] in {"accepted", "conflict"}
    assert Bookmark.objects.get(user=user, id=bookmark_id).revision == 2
    assert ReminderRule.objects.get(user=user, id=reminder_id).revision == 2
