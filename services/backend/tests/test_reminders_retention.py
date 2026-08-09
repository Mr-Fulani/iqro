from __future__ import annotations

import io
import json
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta
from threading import Barrier
from typing import Any, cast

import pytest
from django.conf import settings
from django.core.management import call_command
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
from quran_backend.modules.reading.models import SyncChange, SyncOperation
from quran_backend.modules.reminders import tasks as reminder_tasks
from quran_backend.modules.reminders.checks import (
    check_reminder_id_retention_policy,
    check_reminder_quota_policy,
)
from quran_backend.modules.reminders.models import ReminderRule, RetiredReminderId
from quran_backend.modules.reminders.retention import prune_reminder_tombstones

SAFE_RETENTION_SETTINGS = {
    "QURAN_REMINDER_TOMBSTONE_RETENTION_DAYS": 30,
    "QURAN_REMINDER_NEW_ID_MAX_AGE_DAYS": 20,
    "QURAN_REMINDER_ID_FUTURE_SKEW_SECONDS": 3_600,
    "QURAN_REMINDER_PRUNE_BATCH_SIZE": 100,
    "QURAN_RETIRED_REMINDER_ID_MAX_PER_USER": 100,
}


def _client(user: User) -> APIClient:
    client = APIClient()
    client.force_authenticate(user=user)
    return client


def _prayer_payload(*, reminder_id: uuid.UUID | None = None) -> dict[str, Any]:
    return {
        "id": str(reminder_id or uuid.uuid7()),
        "base_revision": 0,
        "client_updated_at": timezone.now().isoformat(),
        "reminder_type": "prayer",
        "schedule": {
            "kind": "prayer",
            "prayer_event": "fajr",
            "prayer_offset_minutes": -10,
        },
    }


def _create(client: APIClient, payload: dict[str, Any]) -> dict[str, Any]:
    response = client.post(reverse("reminders:reminder-list"), payload, format="json")
    assert response.status_code == 201
    return cast(dict[str, Any], response.json())


def _delete(client: APIClient, reminder_id: str, *, revision: int = 1) -> dict[str, Any]:
    response = client.delete(
        reverse("reminders:reminder-detail", kwargs={"reminder_id": reminder_id}),
        {"base_revision": revision, "client_updated_at": timezone.now().isoformat()},
        format="json",
    )
    assert response.status_code == 200
    return cast(dict[str, Any], response.json())


def _discard_reminder_sync_changes(user: User, *reminder_ids: str | uuid.UUID) -> None:
    changes = SyncChange.objects.filter(user=user, entity_type="reminder")
    if reminder_ids:
        changes = changes.filter(entity_id__in=reminder_ids)
    changes.delete()


@pytest.mark.django_db
def test_delete_immediately_minimizes_sensitive_schedule_target_and_device(
    quran_dataset: dict[str, Any],
) -> None:
    user = User.objects.create_user()
    device = Device.objects.create(
        user=user,
        platform=DevicePlatform.ANDROID,
        installation_id_hash="7" * 64,
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
    create_payload = {
        "id": str(uuid.uuid7()),
        "base_revision": 0,
        "client_updated_at": timezone.now().isoformat(),
        "reminder_type": "quran_review",
        "schedule": {"kind": "local_time", "local_time": "21:45:00"},
        "review_target": {
            "start_ayah_id": str(quran_dataset["first_ayah"].id),
            "end_ayah_id": str(quran_dataset["second_ayah"].id),
        },
        "weekdays_mask": 0b0010000,
        "timezone": {"mode": "fixed", "name": "Europe/Istanbul"},
        "signal": "sound",
    }
    created = _create(client, create_payload)
    assert created["device_id"] == str(device.id)

    deleted = _delete(client, created["id"])
    replayed = _delete(client, created["id"], revision=1)

    assert deleted == replayed
    assert deleted["schedule"] is None
    assert deleted["review_target"] is None
    assert deleted["timezone"] == {"mode": "device_local"}
    assert deleted["weekdays_mask"] == 127
    assert deleted["signal"] == "silent"
    assert deleted["device_id"] is None
    assert deleted["is_enabled"] is False
    rule = ReminderRule.objects.get(pk=created["id"])
    assert rule.device_id is None
    assert rule.prayer_event is None
    assert rule.local_time is None
    assert rule.prayer_offset_minutes is None
    assert rule.start_ayah_id is None
    assert rule.end_ayah_id is None
    assert rule.timezone_name is None


@pytest.mark.django_db
@override_settings(**SAFE_RETENTION_SETTINGS)
def test_prune_replaces_expired_tombstone_with_ownership_aware_retired_id() -> None:
    user = User.objects.create_user()
    client = _client(user)
    payload = _prayer_payload()
    created = _create(client, payload)
    deleted = _delete(client, created["id"])
    old = timezone.now() - timedelta(days=31)
    ReminderRule.objects.filter(pk=created["id"]).update(deleted_at=old)
    _discard_reminder_sync_changes(user, created["id"])

    preview = prune_reminder_tombstones(now=timezone.now(), dry_run=True)
    result = prune_reminder_tombstones(now=timezone.now())
    repeated = prune_reminder_tombstones(now=timezone.now())

    assert preview["tombstones"] == 1
    assert result == {
        "dry_run": False,
        "tombstones": 1,
        "retired_ids_evicted": 0,
        "has_more": False,
        "retention_days": 30,
    }
    assert ReminderRule.objects.filter(pk=created["id"]).exists() is False
    assert repeated["tombstones"] == 0
    assert repeated["has_more"] is False
    retired = RetiredReminderId.objects.get(reminder_id=created["id"])
    assert retired.user_id == user.id
    assert retired.last_revision == deleted["revision"]

    same_user = client.post(reverse("reminders:reminder-list"), payload, format="json")
    cross_user = _client(User.objects.create_user()).post(
        reverse("reminders:reminder-list"), payload, format="json"
    )

    assert same_user.status_code == 410
    assert same_user.json()["code"] == "reminder_deleted"
    assert cross_user.status_code == 409
    assert cross_user.json()["code"] == "reminder_create_conflict"


@pytest.mark.django_db
@override_settings(**SAFE_RETENTION_SETTINGS)
@pytest.mark.parametrize("retained_kind", ["change", "operation"])
def test_prune_waits_for_matching_retained_sync_history(retained_kind: str) -> None:
    user = User.objects.create_user()
    client = _client(user)
    created = _create(client, _prayer_payload())
    deleted = _delete(client, created["id"])
    reminder_id = uuid.UUID(created["id"])
    ReminderRule.objects.filter(pk=reminder_id).update(
        deleted_at=timezone.now() - timedelta(days=31)
    )

    if retained_kind == "change":
        assert SyncChange.objects.filter(
            user=user,
            entity_type="reminder",
            entity_id=reminder_id,
        ).exists()
    else:
        _discard_reminder_sync_changes(user, reminder_id)
        SyncOperation.objects.create(
            user=user,
            operation_id=uuid.uuid7(),
            entity_type="reminder",
            entity_id=reminder_id,
            action="delete",
            request_hash="a" * 64,
            outcome="accepted",
            response={"entity": deleted},
        )

    blocked = prune_reminder_tombstones(now=timezone.now())

    assert blocked["tombstones"] == 0
    assert ReminderRule.objects.filter(pk=reminder_id).exists()
    assert RetiredReminderId.objects.filter(reminder_id=reminder_id).exists() is False

    SyncChange.objects.filter(user=user, entity_id=reminder_id).delete()
    SyncOperation.objects.filter(user=user, entity_id=reminder_id).delete()

    released = prune_reminder_tombstones(now=timezone.now())

    assert released["tombstones"] == 1
    assert ReminderRule.objects.filter(pk=reminder_id).exists() is False
    assert RetiredReminderId.objects.filter(reminder_id=reminder_id).exists()


@pytest.mark.django_db
@override_settings(**SAFE_RETENTION_SETTINGS)
def test_prune_ignores_sync_history_for_other_entity_type_or_user() -> None:
    owner = User.objects.create_user()
    other_user = User.objects.create_user()
    created = _create(_client(owner), _prayer_payload())
    _delete(_client(owner), created["id"])
    reminder_id = uuid.UUID(created["id"])
    ReminderRule.objects.filter(pk=reminder_id).update(
        deleted_at=timezone.now() - timedelta(days=31)
    )
    _discard_reminder_sync_changes(owner, reminder_id)
    SyncChange.objects.create(
        user=owner,
        sequence=3,
        entity_type="bookmark",
        entity_id=reminder_id,
        action="delete",
        revision=1,
        snapshot={},
    )
    SyncOperation.objects.create(
        user=other_user,
        operation_id=uuid.uuid7(),
        entity_type="reminder",
        entity_id=reminder_id,
        action="delete",
        request_hash="b" * 64,
        outcome="accepted",
        response={},
    )

    result = prune_reminder_tombstones(now=timezone.now())

    assert result["tombstones"] == 1
    assert ReminderRule.objects.filter(pk=reminder_id).exists() is False
    assert RetiredReminderId.objects.filter(reminder_id=reminder_id).exists()


@pytest.mark.django_db
@override_settings(
    **SAFE_RETENTION_SETTINGS,
    QURAN_REMINDER_MAX_ACTIVE_PER_USER=2,
    QURAN_REMINDER_MAX_TOTAL_PER_USER=2,
)
def test_pruning_releases_total_quota_without_allowing_id_reuse() -> None:
    user = User.objects.create_user()
    client = _client(user)
    first_payload = _prayer_payload()
    first = _create(client, first_payload)
    _create(client, _prayer_payload())
    _delete(client, first["id"])
    ReminderRule.objects.filter(pk=first["id"]).update(
        deleted_at=timezone.now() - timedelta(days=31)
    )
    _discard_reminder_sync_changes(user, first["id"])
    before_prune = client.post(reverse("reminders:reminder-list"), _prayer_payload(), format="json")
    assert before_prune.status_code == 409
    assert before_prune.json()["code"] == "reminder_quota_exceeded"

    result = prune_reminder_tombstones()
    replacement = client.post(reverse("reminders:reminder-list"), _prayer_payload(), format="json")
    retired_retry = client.post(reverse("reminders:reminder-list"), first_payload, format="json")

    assert result["tombstones"] == 1
    assert replacement.status_code == 201
    assert retired_retry.status_code == 410
    assert ReminderRule.objects.filter(user=user).count() == 2


def _uuid7_at(moment: datetime) -> uuid.UUID:
    base = uuid.uuid7()
    timestamp_bits = int(moment.timestamp() * 1_000) << 80
    return uuid.UUID(int=timestamp_bits | (base.int & ((1 << 80) - 1)))


@pytest.mark.django_db
@override_settings(**SAFE_RETENTION_SETTINGS)
@pytest.mark.parametrize(
    "offset",
    [timedelta(days=-21), timedelta(hours=2)],
    ids=["too-old", "too-far-in-future"],
)
def test_unseen_uuidv7_outside_freshness_window_is_not_reusable(offset: timedelta) -> None:
    payload = _prayer_payload(reminder_id=_uuid7_at(timezone.now() + offset))

    response = _client(User.objects.create_user()).post(
        reverse("reminders:reminder-list"), payload, format="json"
    )

    assert response.status_code == 409
    assert response.json()["code"] == "reminder_id_not_reusable"
    assert ReminderRule.objects.count() == 0


@override_settings(
    QURAN_REMINDER_TOMBSTONE_RETENTION_DAYS=20,
    QURAN_REMINDER_NEW_ID_MAX_AGE_DAYS=20,
    QURAN_REMINDER_ID_FUTURE_SKEW_SECONDS=3_600,
)
def test_system_check_rejects_unsafe_tombstone_freshness_policy() -> None:
    assert {error.id for error in check_reminder_id_retention_policy()} == {"reminders.E002"}


@pytest.mark.parametrize(
    ("active", "total"),
    [(65, 256), (64, 257), (10, 9)],
)
def test_system_check_keeps_runtime_quota_within_snapshot_contract(
    active: int,
    total: int,
) -> None:
    with override_settings(
        QURAN_REMINDER_MAX_ACTIVE_PER_USER=active,
        QURAN_REMINDER_MAX_TOTAL_PER_USER=total,
    ):
        assert {error.id for error in check_reminder_quota_policy()} == {"reminders.E003"}


@pytest.mark.django_db
@override_settings(**(SAFE_RETENTION_SETTINGS | {"QURAN_RETIRED_REMINDER_ID_MAX_PER_USER": 1}))
def test_bounded_ledger_evicts_only_ids_already_rejected_by_freshness(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    user = User.objects.create_user()
    client = _client(user)
    payloads = [_prayer_payload(), _prayer_payload()]
    for payload in payloads:
        created = _create(client, payload)
        _delete(client, created["id"])
    old = timezone.now() - timedelta(days=31)
    ReminderRule.objects.filter(user=user).update(deleted_at=old)
    _discard_reminder_sync_changes(user)
    future = timezone.now() + timedelta(days=31)

    first = prune_reminder_tombstones(now=future)
    second = prune_reminder_tombstones(now=future)

    assert first["tombstones"] == 1
    assert first["has_more"] is True
    assert second["tombstones"] == 1
    assert second["retired_ids_evicted"] == 1
    assert ReminderRule.objects.filter(user=user).count() == 0
    assert RetiredReminderId.objects.filter(user=user).count() == 1

    monkeypatch.setattr(
        "quran_backend.modules.reminders.services.timezone.now",
        lambda: future,
    )
    responses = [
        client.post(reverse("reminders:reminder-list"), payload, format="json")
        for payload in payloads
    ]
    assert sorted(response.status_code for response in responses) == [409, 410]
    assert {response.json()["code"] for response in responses} == {
        "reminder_deleted",
        "reminder_id_not_reusable",
    }


@pytest.mark.django_db
@override_settings(
    **(
        SAFE_RETENTION_SETTINGS
        | {
            "QURAN_REMINDER_PRUNE_BATCH_SIZE": 1,
            "QURAN_RETENTION_TASK_MAX_BATCHES": 5,
        }
    )
)
def test_task_drains_multiple_bounded_batches_and_command_supports_dry_run() -> None:
    user = User.objects.create_user()
    client = _client(user)
    for _ in range(2):
        created = _create(client, _prayer_payload())
        _delete(client, created["id"])
    ReminderRule.objects.filter(user=user).update(deleted_at=timezone.now() - timedelta(days=31))
    _discard_reminder_sync_changes(user)

    output = io.StringIO()
    call_command("prune_reminder_tombstones", "--dry-run", stdout=output)
    preview = json.loads(output.getvalue())
    task_result = reminder_tasks.prune_reminder_tombstones_task.run()

    assert preview["dry_run"] is True
    assert preview["tombstones"] == 1
    assert ReminderRule.objects.filter(user=user).count() == 0
    assert task_result["tombstones"] == 2
    assert task_result["batches"] == 2
    assert task_result["has_more"] is False


def test_celery_beat_schedules_bounded_reminder_retention() -> None:
    schedule = settings.CELERY_BEAT_SCHEDULE["prune-reminder-tombstones-hourly"]
    assert schedule == {"task": "reminders.prune_tombstones", "schedule": 3_600.0}


@pytest.mark.django_db(transaction=True)
@override_settings(**SAFE_RETENTION_SETTINGS)
def test_concurrent_postgresql_pruners_retire_a_tombstone_once() -> None:
    if connection.vendor != "postgresql":
        pytest.skip("Row-lock concurrency semantics require PostgreSQL.")
    user = User.objects.create_user()
    client = _client(user)
    created = _create(client, _prayer_payload())
    _delete(client, created["id"])
    ReminderRule.objects.filter(pk=created["id"]).update(
        deleted_at=timezone.now() - timedelta(days=31)
    )
    _discard_reminder_sync_changes(user, created["id"])
    barrier = Barrier(2)

    def prune() -> int:
        close_old_connections()
        try:
            barrier.wait(timeout=5)
            return prune_reminder_tombstones()["tombstones"]
        finally:
            close_old_connections()

    with ThreadPoolExecutor(max_workers=2) as executor:
        counts = list(executor.map(lambda _index: prune(), range(2)))

    assert sum(counts) == 1
    assert ReminderRule.objects.filter(pk=created["id"]).exists() is False
    assert RetiredReminderId.objects.filter(reminder_id=created["id"]).count() == 1
