from __future__ import annotations

import uuid
from datetime import timedelta
from typing import Any

import pytest
from django.test import override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework.test import APIClient

from quran_backend.modules.accounts.models import User
from quran_backend.modules.reading import tasks as reading_tasks
from quran_backend.modules.reading.checks import check_bookmark_id_retention_policy
from quran_backend.modules.reading.models import (
    Bookmark,
    RetiredBookmarkId,
    SyncChange,
    SyncOperation,
    UserSyncCursor,
)
from quran_backend.modules.reading.retention import prune_sync_history


def _client(user: User) -> APIClient:
    client = APIClient()
    client.force_authenticate(user=user)
    return client


def _push_bookmark(client: APIClient, *, entity_id: uuid.UUID) -> None:
    now = timezone.now().isoformat()
    response = client.post(
        reverse("reading:sync-push"),
        {
            "operations": [
                {
                    "operation_id": str(uuid.uuid7()),
                    "entity_type": "bookmark",
                    "entity_id": str(entity_id),
                    "action": "upsert",
                    "base_revision": 0,
                    "client_updated_at": now,
                    "payload": {
                        "edition_code": "madani-hafs",
                        "page_number": 1,
                    },
                }
            ]
        },
        format="json",
    )
    assert response.status_code == 200
    assert response.json()["results"][0]["outcome"] == "accepted"


@pytest.mark.django_db
@override_settings(
    QURAN_SYNC_CHANGE_RETENTION_DAYS=30,
    QURAN_SYNC_OPERATION_RETENTION_DAYS=30,
    QURAN_SYNC_PRUNE_BATCH_SIZE=100,
    QURAN_SYNC_PRUNE_USER_BATCH_SIZE=100,
)
def test_retention_advances_floor_and_expired_cursor_requires_full_resync(  # noqa: PLR0915
    quran_dataset: dict[str, Any],
) -> None:
    user = User.objects.create_user()
    client = _client(user)
    entity_ids = [uuid.uuid7() for _ in range(3)]
    for entity_id in entity_ids:
        _push_bookmark(client, entity_id=entity_id)

    old = timezone.now() - timedelta(days=31)
    old_change_ids = list(
        SyncChange.objects.filter(user=user, sequence__lte=2).values_list("id", flat=True)
    )
    SyncChange.objects.filter(id__in=old_change_ids).update(created_at=old)
    old_operation_ids = list(
        SyncOperation.objects.filter(user=user)
        .order_by("processed_at", "id")
        .values_list("id", flat=True)[:2]
    )
    SyncOperation.objects.filter(id__in=old_operation_ids).update(processed_at=old)

    dry_run = prune_sync_history(now=timezone.now(), dry_run=True)
    assert dry_run["changes"] == 2
    assert dry_run["operations"] == 2
    assert SyncChange.objects.filter(user=user).count() == 3
    assert UserSyncCursor.objects.get(user=user).minimum_valid_cursor == 0

    result = prune_sync_history(now=timezone.now())

    cursor = UserSyncCursor.objects.get(user=user)
    assert result["changes"] == 2
    assert result["operations"] == 2
    assert result["has_more"] is False
    assert cursor.value == 3
    assert cursor.minimum_valid_cursor == 2
    assert list(SyncChange.objects.filter(user=user).values_list("sequence", flat=True)) == [3]
    assert SyncOperation.objects.filter(user=user).count() == 1

    expired = client.get(reverse("reading:sync-pull"), {"cursor": 1})
    retained = client.get(reverse("reading:sync-pull"), {"cursor": 2})

    assert expired.status_code == 410
    assert expired.content_type == "application/problem+json"
    assert expired.json()["code"] == "sync_cursor_expired"
    assert expired.json()["full_resync_required"] is True
    assert expired.json()["minimum_valid_cursor"] == 2
    assert expired.json()["current_cursor"] == 3
    assert retained.status_code == 200
    assert retained.json()["mode"] == "incremental"
    assert [change["cursor"] for change in retained.json()["changes"]] == [3]

    collected: list[dict[str, Any]] = []
    page_token: str | None = None
    snapshot_cursor: int | None = None
    while True:
        query: dict[str, Any] = {"full_resync": "true", "limit": 1}
        if page_token:
            query["page_token"] = page_token
        page = client.get(reverse("reading:sync-pull"), query)
        assert page.status_code == 200
        payload = page.json()
        assert payload["mode"] == "full_resync"
        snapshot_cursor = payload["snapshot_cursor"]
        collected.extend(payload["entities"])
        page_token = payload["next_page_token"]
        if not payload["has_more"]:
            break

    assert snapshot_cursor == 3
    assert {entity["id"] for entity in collected} == {str(value) for value in entity_ids}


@pytest.mark.django_db
@override_settings(
    QURAN_SYNC_CHANGE_RETENTION_DAYS=30,
    QURAN_SYNC_OPERATION_RETENTION_DAYS=30,
    QURAN_SYNC_PRUNE_BATCH_SIZE=100,
    QURAN_SYNC_PRUNE_USER_BATCH_SIZE=100,
)
def test_retention_only_removes_contiguous_expired_prefix(
    quran_dataset: dict[str, Any],
) -> None:
    user = User.objects.create_user()
    client = _client(user)
    for _ in range(3):
        _push_bookmark(client, entity_id=uuid.uuid7())
    old = timezone.now() - timedelta(days=31)
    first = SyncChange.objects.get(user=user, sequence=1)
    third = SyncChange.objects.get(user=user, sequence=3)
    SyncChange.objects.filter(id__in=[first.id, third.id]).update(created_at=old)

    result = prune_sync_history(now=timezone.now())

    assert result["changes"] == 1
    assert result["has_more"] is True
    assert UserSyncCursor.objects.get(user=user).minimum_valid_cursor == 1
    assert list(SyncChange.objects.filter(user=user).values_list("sequence", flat=True)) == [2, 3]


@pytest.mark.django_db
@override_settings(
    QURAN_SYNC_CHANGE_RETENTION_DAYS=30,
    QURAN_SYNC_OPERATION_RETENTION_DAYS=30,
    QURAN_BOOKMARK_TOMBSTONE_RETENTION_DAYS=30,
    QURAN_BOOKMARK_NEW_ID_MAX_AGE_DAYS=20,
    QURAN_BOOKMARK_ID_FUTURE_SKEW_SECONDS=3600,
    QURAN_SYNC_PRUNE_BATCH_SIZE=100,
    QURAN_SYNC_PRUNE_USER_BATCH_SIZE=100,
)
def test_tombstone_is_pruned_only_after_its_sync_history_is_gone(
    quran_dataset: dict[str, Any],
) -> None:
    user = User.objects.create_user()
    client = _client(user)
    entity_id = uuid.uuid7()
    _push_bookmark(client, entity_id=entity_id)
    delete_response = client.post(
        reverse("reading:sync-push"),
        {
            "operations": [
                {
                    "operation_id": str(uuid.uuid7()),
                    "entity_type": "bookmark",
                    "entity_id": str(entity_id),
                    "action": "delete",
                    "base_revision": 1,
                    "client_updated_at": timezone.now().isoformat(),
                    "payload": {},
                }
            ]
        },
        format="json",
    )
    assert delete_response.status_code == 200
    assert delete_response.json()["results"][0]["outcome"] == "accepted"

    old = timezone.now() - timedelta(days=31)
    Bookmark.objects.filter(user=user, id=entity_id).update(deleted_at=old)

    retained = prune_sync_history(now=timezone.now())

    assert retained["tombstones"] == 0
    assert Bookmark.objects.filter(user=user, id=entity_id).exists()

    SyncChange.objects.filter(user=user, entity_id=entity_id).update(created_at=old)
    operation_retained = prune_sync_history(now=timezone.now())

    assert operation_retained["changes"] == 2
    assert operation_retained["tombstones"] == 0
    assert Bookmark.objects.filter(user=user, id=entity_id).exists()

    SyncOperation.objects.filter(user=user, entity_id=entity_id).update(processed_at=old)
    pruned = prune_sync_history(now=timezone.now())

    assert pruned["operations"] == 2
    assert pruned["tombstones"] == 1
    assert Bookmark.objects.filter(user=user, id=entity_id).exists() is False
    assert RetiredBookmarkId.objects.filter(user=user, bookmark_id=entity_id).exists()
    retired = RetiredBookmarkId.objects.get(user=user, bookmark_id=entity_id)
    assert retired.last_revision == 2


@pytest.mark.django_db
@override_settings(
    QURAN_SYNC_CHANGE_RETENTION_DAYS=30,
    QURAN_SYNC_OPERATION_RETENTION_DAYS=30,
    QURAN_BOOKMARK_TOMBSTONE_RETENTION_DAYS=365,
    QURAN_BOOKMARK_NEW_ID_MAX_AGE_DAYS=360,
    QURAN_BOOKMARK_ID_FUTURE_SKEW_SECONDS=86_400,
    QURAN_SYNC_PRUNE_BATCH_SIZE=100,
    QURAN_SYNC_PRUNE_USER_BATCH_SIZE=100,
)
def test_pruned_tombstone_id_cannot_be_reused(
    quran_dataset: dict[str, Any],
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    user = User.objects.create_user()
    client = _client(user)
    entity_id = uuid.uuid7()
    _push_bookmark(client, entity_id=entity_id)
    deleted = client.post(
        reverse("reading:sync-push"),
        {
            "operations": [
                {
                    "operation_id": str(uuid.uuid7()),
                    "entity_type": "bookmark",
                    "entity_id": str(entity_id),
                    "action": "delete",
                    "base_revision": 1,
                    "client_updated_at": timezone.now().isoformat(),
                    "payload": {},
                }
            ]
        },
        format="json",
    )
    assert deleted.status_code == 200

    future = timezone.now() + timedelta(days=400)
    pruned = prune_sync_history(now=future)
    assert pruned["changes"] == 2
    assert pruned["operations"] == 2
    assert pruned["tombstones"] == 1
    assert Bookmark.objects.filter(user=user, id=entity_id).exists() is False
    assert RetiredBookmarkId.objects.filter(user=user, bookmark_id=entity_id).exists()

    monkeypatch.setattr(
        "quran_backend.modules.reading.services.timezone.now",
        lambda: future,
    )
    with override_settings(
        QURAN_BOOKMARK_TOMBSTONE_RETENTION_DAYS=2000,
        QURAN_BOOKMARK_NEW_ID_MAX_AGE_DAYS=1990,
        QURAN_BOOKMARK_ID_FUTURE_SKEW_SECONDS=86_400,
    ):
        direct_retry = client.post(
            reverse("reading:bookmark-list"),
            {
                "id": str(entity_id),
                "edition_code": "madani-hafs",
                "page_number": 1,
                "client_updated_at": future.isoformat(),
            },
            format="json",
        )
        sync_retry = client.post(
            reverse("reading:sync-push"),
            {
                "operations": [
                    {
                        "operation_id": str(uuid.uuid7()),
                        "entity_type": "bookmark",
                        "entity_id": str(entity_id),
                        "action": "upsert",
                        "base_revision": 0,
                        "client_updated_at": future.isoformat(),
                        "payload": {"edition_code": "madani-hafs", "page_number": 1},
                    }
                ]
            },
            format="json",
        )

    assert direct_retry.status_code == 409
    assert direct_retry.json()["code"] == "bookmark_id_not_reusable"
    assert sync_retry.status_code == 200
    assert sync_retry.json()["results"][0]["outcome"] == "conflict"
    assert sync_retry.json()["results"][0]["conflict_reason"] == ("entity_id_not_reusable")
    assert Bookmark.objects.filter(user=user, id=entity_id).exists() is False


@pytest.mark.django_db
@override_settings(
    QURAN_RETIRED_BOOKMARK_ID_MAX_PER_USER=1,
    QURAN_SYNC_CHANGE_RETENTION_DAYS=30,
    QURAN_SYNC_OPERATION_RETENTION_DAYS=30,
    QURAN_BOOKMARK_TOMBSTONE_RETENTION_DAYS=365,
    QURAN_BOOKMARK_NEW_ID_MAX_AGE_DAYS=360,
    QURAN_BOOKMARK_ID_FUTURE_SKEW_SECONDS=86_400,
    QURAN_SYNC_PRUNE_BATCH_SIZE=100,
    QURAN_SYNC_PRUNE_USER_BATCH_SIZE=100,
)
def test_retired_id_cap_keeps_unretirable_tombstone(
    quran_dataset: dict[str, Any],
) -> None:
    user = User.objects.create_user()
    client = _client(user)
    entity_ids = [uuid.uuid7(), uuid.uuid7()]
    for entity_id in entity_ids:
        _push_bookmark(client, entity_id=entity_id)
        response = client.post(
            reverse("reading:sync-push"),
            {
                "operations": [
                    {
                        "operation_id": str(uuid.uuid7()),
                        "entity_type": "bookmark",
                        "entity_id": str(entity_id),
                        "action": "delete",
                        "base_revision": 1,
                        "client_updated_at": timezone.now().isoformat(),
                        "payload": {},
                    }
                ]
            },
            format="json",
        )
        assert response.status_code == 200

    result = prune_sync_history(now=timezone.now() + timedelta(days=400))

    assert result["tombstones"] == 1
    assert RetiredBookmarkId.objects.filter(user=user).count() == 1
    assert Bookmark.objects.filter(user=user, deleted_at__isnull=False).count() == 1


@pytest.mark.django_db
@override_settings(
    QURAN_RETIRED_BOOKMARK_ID_MAX_PER_USER=1,
    QURAN_BOOKMARK_TOMBSTONE_RETENTION_DAYS=365,
    QURAN_BOOKMARK_NEW_ID_MAX_AGE_DAYS=360,
    QURAN_BOOKMARK_ID_FUTURE_SKEW_SECONDS=86_400,
)
def test_tombstone_dry_run_respects_retired_id_capacity(
    quran_dataset: dict[str, Any],
) -> None:
    user = User.objects.create_user()
    now = timezone.now()
    for _ in range(2):
        Bookmark.objects.create(
            id=uuid.uuid7(),
            user=user,
            edition=quran_dataset["edition"],
            page=quran_dataset["page"],
            client_updated_at=now,
            deleted_at=now,
            revision=2,
        )
    future = now + timedelta(days=400)

    preview = prune_sync_history(now=future, dry_run=True)

    assert preview["tombstones"] == 1
    assert Bookmark.objects.filter(user=user).count() == 2
    assert RetiredBookmarkId.objects.filter(user=user).count() == 0


@override_settings(
    QURAN_BOOKMARK_TOMBSTONE_RETENTION_DAYS=365,
    QURAN_BOOKMARK_NEW_ID_MAX_AGE_DAYS=365,
    QURAN_BOOKMARK_ID_FUTURE_SKEW_SECONDS=86_400,
)
def test_system_check_rejects_unsafe_bookmark_id_retention_policy() -> None:
    errors = check_bookmark_id_retention_policy()

    assert any(error.id == "reading.E002" for error in errors)


@pytest.mark.django_db
@override_settings(
    QURAN_SYNC_CHANGE_RETENTION_DAYS=30,
    QURAN_SYNC_OPERATION_RETENTION_DAYS=30,
    QURAN_BOOKMARK_TOMBSTONE_RETENTION_DAYS=365,
    QURAN_SYNC_PRUNE_BATCH_SIZE=2,
    QURAN_SYNC_PRUNE_USER_BATCH_SIZE=2,
)
def test_retention_rotates_users_after_a_noisy_user_consumes_a_batch(
    quran_dataset: dict[str, Any],
) -> None:
    noisy_user = User.objects.create_user(id=uuid.UUID(int=1))
    waiting_user = User.objects.create_user(id=uuid.UUID(int=2))
    for _ in range(5):
        _push_bookmark(_client(noisy_user), entity_id=uuid.uuid7())
    _push_bookmark(_client(waiting_user), entity_id=uuid.uuid7())
    now = timezone.now()
    old = now - timedelta(days=31)
    SyncChange.objects.update(created_at=old)
    UserSyncCursor.objects.filter(user=noisy_user).update(updated_at=now - timedelta(hours=2))
    UserSyncCursor.objects.filter(user=waiting_user).update(updated_at=now - timedelta(hours=1))

    first = prune_sync_history(now=now)
    assert first["changes"] == 2
    assert SyncChange.objects.filter(user=waiting_user).exists()

    second = prune_sync_history(now=now)

    assert SyncChange.objects.filter(user=waiting_user).exists() is False
    assert UserSyncCursor.objects.get(user=waiting_user).minimum_valid_cursor == 1
    assert second["changes"] == 2


@override_settings(QURAN_RETENTION_TASK_MAX_BATCHES=5)
def test_retention_task_stops_when_a_batch_makes_no_progress(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    results = [
        {
            "dry_run": False,
            "changes": 1,
            "operations": 0,
            "tombstones": 0,
            "users": 1,
            "has_more": True,
            "change_retention_days": 180,
            "operation_retention_days": 180,
            "tombstone_retention_days": 365,
        },
        {
            "dry_run": False,
            "changes": 0,
            "operations": 0,
            "tombstones": 0,
            "users": 0,
            "has_more": True,
            "change_retention_days": 180,
            "operation_retention_days": 180,
            "tombstone_retention_days": 365,
        },
    ]
    calls = 0

    def fake_prune_sync_history() -> dict[str, Any]:
        nonlocal calls
        result = results[calls]
        calls += 1
        return result

    monkeypatch.setattr(reading_tasks, "prune_sync_history", fake_prune_sync_history)

    result = reading_tasks.prune_sync_history_task.run()

    assert calls == 2
    assert result["batches"] == 2
    assert result["changes"] == 1
    assert result["has_more"] is True
