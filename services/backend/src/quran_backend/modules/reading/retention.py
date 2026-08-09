from __future__ import annotations

from datetime import datetime, timedelta
from typing import TypedDict
from uuid import UUID

from django.conf import settings
from django.core.exceptions import ImproperlyConfigured
from django.db import transaction
from django.db.models import Count, Exists, IntegerField, OuterRef, QuerySet, Subquery, Value
from django.db.models.functions import Coalesce
from django.utils import timezone

from quran_backend.modules.accounts.models import User
from quran_backend.modules.reading.models import (
    Bookmark,
    RetiredBookmarkId,
    SyncChange,
    SyncEntityType,
    SyncOperation,
    UserSyncCursor,
)
from quran_backend.modules.reading.policies import bookmark_id_policy


class SyncPruneResult(TypedDict):
    dry_run: bool
    changes: int
    operations: int
    tombstones: int
    users: int
    has_more: bool
    change_retention_days: int
    operation_retention_days: int
    tombstone_retention_days: int


def prune_sync_history(
    *,
    now: datetime | None = None,
    dry_run: bool = False,
) -> SyncPruneResult:
    """Prune bounded sync history while atomically advancing each user's cursor floor."""
    effective_now = now or timezone.now()
    change_days = _positive_setting("QURAN_SYNC_CHANGE_RETENTION_DAYS", 180)
    operation_days = _positive_setting("QURAN_SYNC_OPERATION_RETENTION_DAYS", 180)
    id_policy = bookmark_id_policy()
    tombstone_days = id_policy.tombstone_retention_days
    if not id_policy.is_safe:
        msg = (
            "QURAN_BOOKMARK_TOMBSTONE_RETENTION_DAYS must exceed the unseen bookmark "
            "ID age window plus QURAN_BOOKMARK_ID_FUTURE_SKEW_SECONDS."
        )
        raise ImproperlyConfigured(msg)
    row_batch_size = _positive_setting("QURAN_SYNC_PRUNE_BATCH_SIZE", 5_000)
    user_batch_size = _positive_setting("QURAN_SYNC_PRUNE_USER_BATCH_SIZE", 1_000)
    change_cutoff = effective_now - timedelta(days=change_days)
    operation_cutoff = effective_now - timedelta(days=operation_days)
    tombstone_cutoff = effective_now - timedelta(days=tombstone_days)

    oldest_change = (
        SyncChange.objects.filter(user_id=OuterRef("user_id"))
        .order_by("sequence")
        .values("created_at")[:1]
    )
    user_ids = list(
        UserSyncCursor.objects.annotate(oldest_change_at=Subquery(oldest_change))
        .filter(oldest_change_at__lt=change_cutoff)
        .order_by("updated_at", "user_id")
        .values_list("user_id", flat=True)[:user_batch_size]
    )
    changed_rows = 0
    changed_users = 0
    remaining_change_budget = row_batch_size
    for user_id in user_ids:
        if remaining_change_budget <= 0:
            break
        count = _prune_user_changes(
            user_id=user_id,
            cutoff=change_cutoff,
            batch_size=remaining_change_budget,
            dry_run=dry_run,
        )
        if count:
            changed_users += 1
            changed_rows += count
            remaining_change_budget -= count

    operation_ids = list(
        SyncOperation.objects.filter(processed_at__lt=operation_cutoff)
        .order_by("processed_at", "id")
        .values_list("id", flat=True)[:row_batch_size]
    )
    if operation_ids and not dry_run:
        SyncOperation.objects.filter(id__in=operation_ids).delete()

    tombstone_count = _prune_bookmark_tombstones(
        cutoff=tombstone_cutoff,
        batch_size=row_batch_size,
        dry_run=dry_run,
    )

    has_more = (
        SyncChange.objects.filter(created_at__lt=change_cutoff).exists()
        or SyncOperation.objects.filter(processed_at__lt=operation_cutoff).exists()
        or _eligible_bookmark_tombstones(tombstone_cutoff).exists()
    )
    return {
        "dry_run": dry_run,
        "changes": changed_rows,
        "operations": len(operation_ids),
        "tombstones": tombstone_count,
        "users": changed_users,
        "has_more": has_more,
        "change_retention_days": change_days,
        "operation_retention_days": operation_days,
        "tombstone_retention_days": tombstone_days,
    }


@transaction.atomic
def _prune_user_changes(
    *,
    user_id: UUID,
    cutoff: datetime,
    batch_size: int,
    dry_run: bool,
) -> int:
    cursor = UserSyncCursor.objects.select_for_update().get(user_id=user_id)
    candidates = list(
        SyncChange.objects.filter(
            user_id=user_id,
            sequence__gt=cursor.minimum_valid_cursor,
        )
        .order_by("sequence")
        .values("sequence", "created_at")[:batch_size]
    )
    contiguous_expired = []
    for candidate in candidates:
        if candidate["created_at"] >= cutoff:
            break
        contiguous_expired.append(candidate)
    if not contiguous_expired:
        return 0

    new_floor = int(contiguous_expired[-1]["sequence"])
    queryset = SyncChange.objects.filter(user_id=user_id, sequence__lte=new_floor)
    count = queryset.count()
    if dry_run:
        return count

    cursor.minimum_valid_cursor = max(cursor.minimum_valid_cursor, new_floor)
    cursor.save(update_fields=["minimum_valid_cursor", "updated_at"])
    queryset.delete()
    return count


def _eligible_bookmark_tombstones(cutoff: datetime) -> QuerySet[Bookmark]:
    retained_history = SyncChange.objects.filter(
        user_id=OuterRef("user_id"),
        entity_type=SyncEntityType.BOOKMARK,
        entity_id=OuterRef("id"),
    )
    retained_operations = SyncOperation.objects.filter(
        user_id=OuterRef("user_id"),
        entity_type=SyncEntityType.BOOKMARK,
        entity_id=OuterRef("id"),
    )
    already_retired = RetiredBookmarkId.objects.filter(
        user_id=OuterRef("user_id"),
        bookmark_id=OuterRef("id"),
    )
    retired_count = (
        RetiredBookmarkId.objects.filter(user_id=OuterRef("user_id"))
        .order_by()
        .values("user_id")
        .annotate(total=Count("id"))
        .values("total")[:1]
    )
    retired_limit = _positive_setting("QURAN_RETIRED_BOOKMARK_ID_MAX_PER_USER", 50_000)
    return (
        Bookmark.objects.filter(deleted_at__lt=cutoff)
        .annotate(has_retained_history=Exists(retained_history))
        .annotate(has_retained_operation=Exists(retained_operations))
        .annotate(already_retired=Exists(already_retired))
        .annotate(
            retired_count=Coalesce(
                Subquery(retired_count, output_field=IntegerField()),
                Value(0),
            )
        )
        .filter(
            has_retained_history=False,
            has_retained_operation=False,
            already_retired=False,
            retired_count__lt=retired_limit,
        )
        .order_by("deleted_at", "id")
    )


@transaction.atomic
def _prune_bookmark_tombstones(
    *,
    cutoff: datetime,
    batch_size: int,
    dry_run: bool,
) -> int:
    queryset = _eligible_bookmark_tombstones(cutoff)
    if dry_run:
        preview = list(queryset[:batch_size])
        return len(_within_retired_id_capacity(preview))
    candidate_ids = list(queryset.values_list("id", flat=True)[:batch_size])
    if not candidate_ids:
        return 0
    user_ids = list(
        Bookmark.objects.filter(id__in=candidate_ids)
        .order_by("user_id")
        .values_list("user_id", flat=True)
        .distinct()
    )
    list(User.objects.select_for_update().filter(id__in=user_ids).order_by("id"))
    tombstones = list(
        _eligible_bookmark_tombstones(cutoff)
        .select_for_update(of=("self",))
        .filter(id__in=candidate_ids)
        .order_by("deleted_at", "id")
    )
    selected = _within_retired_id_capacity(tombstones)
    RetiredBookmarkId.objects.bulk_create(
        [
            RetiredBookmarkId(
                user_id=tombstone.user_id,
                bookmark_id=tombstone.id,
                last_revision=tombstone.revision,
                retired_at=timezone.now(),
            )
            for tombstone in selected
        ]
    )
    tombstone_ids = [tombstone.id for tombstone in selected]
    if tombstone_ids:
        Bookmark.objects.filter(id__in=tombstone_ids).delete()
    return len(tombstone_ids)


def _within_retired_id_capacity(tombstones: list[Bookmark]) -> list[Bookmark]:
    retired_limit = _positive_setting("QURAN_RETIRED_BOOKMARK_ID_MAX_PER_USER", 50_000)
    user_ids = {tombstone.user_id for tombstone in tombstones}
    counts = dict(
        RetiredBookmarkId.objects.filter(user_id__in=user_ids)
        .values_list("user_id")
        .annotate(count=Count("id"))
    )
    selected: list[Bookmark] = []
    for tombstone in tombstones:
        count = counts.get(tombstone.user_id, 0)
        if count >= retired_limit:
            continue
        selected.append(tombstone)
        counts[tombstone.user_id] = count + 1
    return selected


def _positive_setting(name: str, default: int) -> int:
    try:
        value = int(getattr(settings, name, default))
    except (TypeError, ValueError) as exc:
        raise ImproperlyConfigured(f"{name} must be a positive integer.") from exc
    if value <= 0:
        raise ImproperlyConfigured(f"{name} must be a positive integer.")
    return value
